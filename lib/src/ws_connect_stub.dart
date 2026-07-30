import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens the live WebSocket. Resolved at compile time by the conditional import in
/// `live.dart`: native sends [headers], web can't and uses `?wsToken=` instead.
WebSocketChannel openChannel(Uri uri, Map<String, dynamic> headers) =>
    WebSocketChannel.connect(uri);
