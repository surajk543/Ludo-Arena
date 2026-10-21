import 'dart:async';
import 'dart:io';

import '../protocol/message_types.dart';

/// Minimal socket contract so `RealtimeConnection` can be tested with a fake.
abstract interface class RealtimeSocket {
  /// Inbound frames (`String` for text frames). Completes when the socket
  /// closes; [closeCode]/[closeReason] are then available.
  Stream<dynamic> get stream;

  /// Sends one text frame.
  void add(String data);

  Future<void> close([int? code, String? reason]);

  int? get closeCode;
  String? get closeReason;
}

/// Opens a socket to [uri] with the given HTTP upgrade [headers].
/// Throws [RealtimeHandshakeException] when the upgrade fails.
typedef WebSocketConnector =
    Future<RealtimeSocket> Function(Uri uri, Map<String, String> headers);

/// The HTTP upgrade was rejected ([httpStatus] set) or the network failed
/// ([httpStatus] null).
class RealtimeHandshakeException implements Exception {
  const RealtimeHandshakeException({this.httpStatus, this.message = ''});

  final int? httpStatus;
  final String message;

  @override
  String toString() =>
      'RealtimeHandshakeException(${httpStatus ?? 'network'}: $message)';
}

/// `dart:io` WebSocket adapter.
class IoRealtimeSocket implements RealtimeSocket {
  IoRealtimeSocket(this._ws);

  final WebSocket _ws;

  @override
  Stream<dynamic> get stream => _ws;

  @override
  void add(String data) => _ws.add(data);

  @override
  Future<void> close([int? code, String? reason]) => _ws.close(code, reason);

  @override
  int? get closeCode => _ws.closeCode;

  @override
  String? get closeReason => _ws.closeReason;

  /// What the server selected (`ludo-royale.v1`), if any.
  String? get protocol => _ws.protocol;
}

/// Default connector: `dart:io` [WebSocket.connect] with the
/// `ludo-royale.v1` subprotocol and permessage-deflate negotiation
/// ([CompressionOptions.compressionDefault]; decompression is transparent and
/// the application protocol is identical either way).
Future<RealtimeSocket> ioWebSocketConnector(
  Uri uri,
  Map<String, String> headers,
) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 15);
  try {
    final ws = await WebSocket.connect(
      uri.toString(),
      protocols: const [kProtocolName],
      headers: headers,
      compression: CompressionOptions.compressionDefault,
      customClient: client,
    );
    return IoRealtimeSocket(ws);
  } on WebSocketException catch (e) {
    throw RealtimeHandshakeException(
      httpStatus: e.httpStatusCode,
      message: e.message,
    );
  } on SocketException catch (e) {
    throw RealtimeHandshakeException(message: e.message);
  } on HttpException catch (e) {
    throw RealtimeHandshakeException(message: e.message);
  } on TimeoutException {
    throw const RealtimeHandshakeException(message: 'timeout');
  } on HandshakeException catch (e) {
    throw RealtimeHandshakeException(message: e.message);
  }
}
