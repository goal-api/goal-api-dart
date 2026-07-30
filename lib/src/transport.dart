import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'errors.dart';

const String defaultBaseUrl = 'https://api.goal-api.com/v1';
const String sdkVersion = '1.0.0';

const Set<int> _retryableStatus = {429, 500, 502, 503, 504};

/// Quota from the last response.
class RateLimitInfo {
  const RateLimitInfo({this.limit, this.remaining, this.reset, this.type});

  final int? limit;
  final int? remaining;

  /// When the window rolls over, as unix seconds.
  final int? reset;

  /// `DAILY` or `MONTHLY`.
  final String? type;

  @override
  String toString() =>
      'RateLimitInfo(limit: $limit, remaining: $remaining, reset: $reset, type: $type)';
}

/// Auth, query encoding, retries and rate-limit tracking.
class Transport {
  Transport({
    required this.apiKey,
    String baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 2,
    http.Client? httpClient,
    String? userAgent,
    Map<String, String> headers = const {},
  })  : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _ownsClient = httpClient == null,
        _client = httpClient ?? http.Client(),
        userAgent = userAgent ?? 'goal-api-dart/$sdkVersion',
        extraHeaders = headers {
    if (apiKey.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey',
          'is required. Create one at https://goal-api.com/dashboard');
    }
  }

  final String apiKey;
  final String baseUrl;
  final Duration timeout;
  final int maxRetries;
  final String userAgent;
  final Map<String, String> extraHeaders;

  final http.Client _client;
  final bool _ownsClient;

  RateLimitInfo _rateLimit = const RateLimitInfo();

  RateLimitInfo get rateLimit => _rateLimit;

  /// Drops null/empty and joins iterables with commas.
  ///
  /// Callers pass whole option maps with keys unset, and `?season=null` is a 400.
  /// Booleans go out as `true`/`false`, which is what the validators check for.
  static Map<String, String> encodeParams(Map<String, dynamic>? params) {
    final out = <String, String>{};
    if (params == null) return out;

    params.forEach((key, value) {
      if (value == null) return;
      if (value is bool) {
        out[key] = value ? 'true' : 'false';
      } else if (value is Iterable) {
        final joined = value.map((v) => '$v').join(',');
        if (joined.isNotEmpty) out[key] = joined;
      } else {
        final encoded = '$value';
        if (encoded.isNotEmpty) out[key] = encoded;
      }
    });
    return out;
  }

  Future<Map<String, dynamic>> get(String path,
      [Map<String, dynamic>? params]) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: () {
        final query = encodeParams(params);
        return query.isEmpty ? null : query;
      }(),
    );

    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await _once('GET', uri);
      } catch (error) {
        lastError = error;
        if (attempt == maxRetries || !_shouldRetry(error)) rethrow;
        await Future<void>.delayed(_backoff(attempt, error));
      }
    }
    throw lastError!; // unreachable: the loop always returns or rethrows
  }

  /// Not retried: `/ws/token` is single-use, so a retry would burn the token the
  /// first attempt may already have minted.
  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _once('POST', Uri.parse('$baseUrl$path'), body: body);

  Future<Map<String, dynamic>> _once(String method, Uri uri,
      {Object? body}) async {
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
        'User-Agent': userAgent,
        if (body != null) 'Content-Type': 'application/json',
        ...extraHeaders,
      });
    if (body != null) request.body = jsonEncode(body);

    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException catch (error) {
      throw GoalApiTimeoutException(
          'Request to $uri timed out after ${timeout.inMilliseconds}ms',
          cause: error);
    } catch (error) {
      throw GoalApiConnectionException('Could not reach $uri: $error',
          cause: error);
    }

    final headers = response.headers;
    _captureRateLimit(headers);

    final parsed = _parseBody(response.body);
    if (response.statusCode >= 400) {
      throw errorFromResponse(response.statusCode, parsed, headers);
    }
    return parsed ?? const <String, dynamic>{};
  }

  static Map<String, dynamic>? _parseBody(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{'data': decoded};
    } on FormatException {
      // nginx returns HTML for 502s. Keep an excerpt so the message is still useful.
      final excerpt = body.length > 200 ? body.substring(0, 200) : body;
      return <String, dynamic>{'message': excerpt.trim()};
    }
  }

  void _captureRateLimit(Map<String, String> headers) {
    // /public/* sends RateLimit-* (draft standard) instead, so leave the snapshot
    // alone.
    if (headers['x-ratelimit-limit'] == null &&
        headers['x-ratelimit-type'] == null) {
      return;
    }
    _rateLimit = RateLimitInfo(
      limit: int.tryParse(headers['x-ratelimit-limit'] ?? ''),
      remaining: int.tryParse(headers['x-ratelimit-remaining'] ?? ''),
      reset: int.tryParse(headers['x-ratelimit-reset'] ?? ''),
      type: headers['x-ratelimit-type'],
    );
  }

  bool _shouldRetry(Object error) {
    if (error is GoalApiConnectionException) return true;
    if (error is GoalApiException) {
      return _retryableStatus.contains(error.status);
    }
    return false;
  }

  /// Exponential backoff with jitter. A server-sent Retry-After takes priority.
  Duration _backoff(int attempt, Object error) {
    if (error is RateLimitException && error.retryAfter != null) {
      final seconds = error.retryAfter!.clamp(0, 60);
      return Duration(seconds: seconds);
    }
    final ceiling = min(500 * (1 << attempt), 8000);
    return Duration(milliseconds: Random().nextInt(ceiling));
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Ids, dates and country names come from callers, so they can't be interpolated
/// raw.
String segment(Object? value) {
  if (value == null || '$value'.isEmpty) {
    throw ArgumentError('Path segment is required');
  }
  return Uri.encodeComponent('$value');
}
