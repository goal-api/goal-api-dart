import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'errors.dart';
import 'transport.dart';
import 'ws_connect_stub.dart'
    if (dart.library.io) 'ws_connect_io.dart'
    if (dart.library.js_interop) 'ws_connect_web.dart';

/// Server → client message types.
abstract final class LiveMessageType {
  static const String authSuccess = 'auth_success';
  static const String matchUpdate = 'match_update';
  static const String pong = 'pong';
  static const String status = 'status';
  static const String serverShutdown = 'server_shutdown';
  static const String error = 'error';

  // Replies to client requests are named `<request>_response`.
  static const String subscribeResponse = 'subscribe_response';
  static const String unsubscribeResponse = 'unsubscribe_response';
  static const String getSubscriptionsResponse = 'get_subscriptions_response';
}

/// Live match updates over WebSocket. Reconnects with backoff and re-sends
/// subscriptions.
///
/// ```dart
/// final live = goal.live();
/// live.on(LiveMessageType.matchUpdate).listen((message) => print(message['data']));
/// await live.connect();
/// live.subscribe(fixtureId);
/// ```
///
/// The connection authenticates twice, because two services are involved:
///
/// 1. The gateway authorises the HTTP upgrade. Native sends `Authorization: Bearer`;
///    browsers can't set headers, so pass `useConnectToken: true` and the client gets
///    a single-use token from `POST /ws/token` for the `?wsToken=` query param.
/// 2. websocket-service then requires `{"type": "auth", ...}` as the very first frame,
///    and closes with 4001 if anything else arrives first.
///
/// [connect] completes on `auth_success`, not on socket open, so a completed future
/// means the connection is actually usable. (The key is still in the app bundle either
/// way, so proxy through your own backend for anything public.)
class LiveClient {
  LiveClient(
    this._t, {
    String? url,
    this.autoReconnect = true,
    this.maxReconnectAttempts,
    this.pingInterval = const Duration(seconds: 30),
    this.useConnectToken = false,
    this.authTimeout = const Duration(seconds: 10),
  }) : _url = url ?? deriveWsUrl(_t.baseUrl);

  final Transport _t;
  final String _url;
  final bool autoReconnect;
  final int? maxReconnectAttempts;

  /// Ping cadence. [Duration.zero] disables it.
  final Duration pingInterval;

  /// Use a `?wsToken=` instead of an Authorization header. Required on web.
  final bool useConnectToken;

  /// How long to wait for `auth_success` before giving up.
  final Duration authTimeout;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  bool _authenticated = false;

  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _subscriptions = <String>{};
  int _attempt = 0;
  bool _closedByUser = false;

  /// Every message from the server, decoded.
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  /// Just the messages of one [type], e.g. [LiveMessageType.matchUpdate].
  Stream<Map<String, dynamic>> on(String type) =>
      _messages.stream.where((message) => message['type'] == type);

  /// The matches this client is subscribed to.
  Set<String> get subscriptions => Set.unmodifiable(_subscriptions);

  /// True once authenticated, not merely once the socket is open.
  bool get connected => _channel != null && !_closedByUser && _authenticated;

  Future<LiveClient> connect() async {
    _closedByUser = false;

    final Uri uri;
    final Map<String, dynamic> headers;
    final Map<String, dynamic> authFrame;
    if (useConnectToken) {
      final response = await _t.post('/ws/token', const <String, dynamic>{});
      final token = (response['data'] as Map?)?['token'] as String?;
      if (token == null) {
        throw AuthenticationException(
            'Server did not return a WebSocket connection token');
      }
      uri = Uri.parse('$_url?wsToken=${Uri.encodeQueryComponent(token)}');
      headers = const {};
      authFrame = {'type': 'auth', 'token': token};
    } else {
      uri = Uri.parse(_url);
      headers = {'Authorization': 'Bearer ${_t.apiKey}'};
      authFrame = {'type': 'auth', 'apiKey': _t.apiKey};
    }

    try {
      // Resolved by the conditional import above: native sends the headers, web
      // ignores them and relies on the wsToken query param.
      _channel = openChannel(uri, headers);
      await _channel!.ready;
    } catch (error) {
      throw GoalApiConnectionException(
          'Could not open WebSocket to $uri: $error',
          cause: error);
    }

    _authenticated = false;
    final authed = Completer<Map<String, dynamic>>();

    _subscription = _channel!.stream.listen(
      (dynamic raw) {
        final message = _decode(raw);
        if (message == null) return;
        if (!authed.isCompleted) {
          if (message['type'] == 'auth_success') {
            authed.complete(message);
          } else if (message['type'] == 'error') {
            final error = message['error'];
            final detail = (error is Map ? error['message'] : null) ??
                message['message'] ??
                'authentication failed';
            authed.completeError(AuthenticationException('$detail'));
            return;
          }
        }
        if (!_messages.isClosed) _messages.add(message);
      },
      onError: (Object error) {
        if (!authed.isCompleted) {
          authed.completeError(GoalApiConnectionException(
              'WebSocket error: $error',
              cause: error));
        }
        _messages.addError(
          GoalApiConnectionException('WebSocket error: $error', cause: error),
        );
      },
      onDone: () {
        if (!authed.isCompleted) {
          authed.completeError(GoalApiConnectionException(
              'WebSocket closed before authenticating'));
        }
        _handleDone();
      },
      cancelOnError: false,
    );

    // Must be the first frame on the wire, or the server closes with 4001.
    _channel!.sink.add(jsonEncode(authFrame));

    try {
      await authed.future.timeout(authTimeout);
    } on TimeoutException {
      await _channel?.sink.close();
      throw AuthenticationException('Timed out waiting for auth_success');
    }

    _authenticated = true;
    _attempt = 0;
    _startPing();

    for (final matchId in _subscriptions.toList()) {
      _send({'type': 'subscribe', 'resource': 'match', 'matchId': matchId});
    }

    return this;
  }

  Map<String, dynamic>? _decode(dynamic raw) {
    try {
      final decoded =
          jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      if (!_messages.isClosed) {
        _messages
            .addError(GoalApiException('Received malformed WebSocket frame'));
      }
      return null;
    }
  }

  /// Fine to call before [connect]; it is sent on open.
  void subscribe(String matchId) {
    _subscriptions.add(matchId);
    _send({'type': 'subscribe', 'resource': 'match', 'matchId': matchId});
  }

  void unsubscribe(String matchId) {
    _subscriptions.remove(matchId);
    _send({'type': 'unsubscribe', 'resource': 'match', 'matchId': matchId});
  }

  /// Reply arrives on [messages] as a `get_subscriptions` frame.
  void listSubscriptions() => _send({'type': 'get_subscriptions'});

  void requestStatus() => _send({'type': 'status'});

  void ping() => _send({'type': 'ping'});

  Future<void> close(
      [int code = ws_status.normalClosure,
      String reason = 'client closed']) async {
    _closedByUser = true;
    _authenticated = false;
    _stopPing();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(code, reason);
    _channel = null;
    await _messages.close();
  }

  void _handleDone() {
    _stopPing();
    _authenticated = false;
    if (autoReconnect && !_closedByUser) {
      _scheduleReconnect();
    } else if (!_messages.isClosed) {
      _messages.close();
    }
  }

  void _send(Map<String, dynamic> message) {
    // subscribe/unsubscribe are held in _subscriptions and replayed on open.
    if (!connected) {
      final type = message['type'];
      if (type != 'subscribe' && type != 'unsubscribe' && !_messages.isClosed) {
        _messages.addError(
            GoalApiException('Cannot send "$type": socket is not open'));
      }
      return;
    }
    _channel!.sink.add(jsonEncode(message));
  }

  void _startPing() {
    _stopPing();
    if (pingInterval == Duration.zero) return;
    _pingTimer = Timer.periodic(pingInterval, (_) => ping());
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _scheduleReconnect() {
    final max = maxReconnectAttempts;
    if (max != null && _attempt >= max) {
      if (!_messages.isClosed) {
        _messages.addError(
            GoalApiException('Giving up after $_attempt reconnect attempts'));
        _messages.close();
      }
      return;
    }
    final base = min(1000 * (1 << _attempt), 30000);
    final jittered = (base * (0.5 + Random().nextDouble() / 2)).round();
    _attempt++;
    Timer(Duration(milliseconds: jittered), () {
      if (_closedByUser) return;
      connect().catchError((Object error) {
        if (!_messages.isClosed) _messages.addError(error);
        _scheduleReconnect();
        return this;
      });
    });
  }
}

/// The live socket is served at `/ws` on the host root, not under `/v1`.
///
/// nginx routes it with `location ^~ /ws`, the only location carrying the Upgrade
/// headers. `/v1/ws` falls into the REST location instead and silently answers 200
/// rather than upgrading, which is a confusing failure because the URL looks right.
String deriveWsUrl(String baseUrl) {
  final uri = Uri.parse(baseUrl);
  return uri
      .replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws',
        query: '',
      )
      .toString()
      .replaceFirst(RegExp(r'\?$'), '');
}
