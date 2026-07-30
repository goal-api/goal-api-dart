import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native: authenticates the handshake with the same `Authorization: Bearer` header
/// as REST, so no token round trip.
WebSocketChannel openChannel(Uri uri, Map<String, dynamic> headers) =>
    IOWebSocketChannel.connect(uri, headers: headers);
