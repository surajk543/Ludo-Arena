import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'events.dart';
import 'json_read.dart';
import 'message_types.dart';

/// Client → server envelope: `{"t": type, "id": id, "p": payload}`.
@immutable
class ClientMessage {
  const ClientMessage({required this.type, this.id, this.payload});

  /// `ping` (no id needed).
  const ClientMessage.ping() : this(type: ClientMessageTypes.ping);

  final String type;

  /// 1–64 chars, unique per user for 2 minutes (server de-dup window).
  /// Required for every type except `ping`.
  final String? id;
  final Map<String, dynamic>? payload;

  Map<String, dynamic> toJson() => {
    't': type,
    'id': ?id,
    if (payload != null && payload!.isNotEmpty) 'p': payload,
  };

  String encode() => jsonEncode(toJson());
}

/// Server → client envelope: `{"t": type, "r": replyTo, "p": payload}` with
/// the payload already parsed into a typed [event].
@immutable
class ServerMessage {
  const ServerMessage({
    required this.type,
    required this.event,
    this.replyTo,
    this.payload = const {},
  });

  /// Wire type (`t`).
  final String type;

  /// `r`: the client message id this directly replies to.
  final String? replyTo;

  /// Raw payload (`p`) for anything the typed [event] does not expose.
  final Map<String, dynamic> payload;

  /// Typed payload; [UnknownEvent] for unknown types.
  final ServerEvent event;

  bool get isError => event is ServerErrorEvent;

  /// Synthetic local message (see [LocalResyncRequired]).
  static const ServerMessage localResync = ServerMessage(
    type: ServerMessageTypes.localResyncRequired,
    event: LocalResyncRequired(),
  );

  @override
  String toString() =>
      'ServerMessage($type${replyTo == null ? '' : ' r=$replyTo'})';
}

/// A frame that is not a valid protocol envelope (malformed JSON, not an
/// object, or missing `t`). The connection drops such frames.
class ProtocolDecodeException implements Exception {
  const ProtocolDecodeException(this.message);

  final String message;

  @override
  String toString() => 'ProtocolDecodeException: $message';
}

/// Decodes one text frame. Throws [ProtocolDecodeException] for malformed
/// frames; never throws for unknown types or fields.
///
/// Kept as a top-level function so a background-isolate decoder can be
/// swapped in via `MessageDecoder` if messages ever grow large.
ServerMessage decodeServerMessage(String raw) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException catch (e) {
    throw ProtocolDecodeException('invalid JSON: ${e.message}');
  }
  if (json is! Map) throw const ProtocolDecodeException('not an object');
  final type = json['t'];
  if (type is! String || type.isEmpty) {
    throw const ProtocolDecodeException('missing "t"');
  }
  final payload = readMap(json['p']);
  final ServerEvent event;
  try {
    event = ServerEvent.parse(type, payload);
  } catch (e) {
    // Lenient readers should make this unreachable; never crash the socket.
    throw ProtocolDecodeException('bad payload for $type: $e');
  }
  return ServerMessage(
    type: type,
    replyTo: readStringOrNull(json['r']),
    payload: payload,
    event: event,
  );
}

/// Pluggable decoder (default: [decodeServerMessage]).
typedef MessageDecoder = ServerMessage Function(String raw);
