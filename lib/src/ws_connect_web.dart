import 'package:web_socket_channel/web_socket_channel.dart';

/// Web: browsers can't set headers on a WebSocket, so [headers] is ignored and the
/// connection needs the `?wsToken=` query param. Pass `useConnectToken: true`.
WebSocketChannel openChannel(Uri uri, Map<String, dynamic> headers) =>
    WebSocketChannel.connect(uri);
