/// Lenient JSON field readers used by the protocol models. The server may add
/// fields at any time (clients must ignore unknown fields) and a missing
/// optional field must never crash decoding.
library;

int readInt(Object? v, [int fallback = 0]) => switch (v) {
  int i => i,
  num n => n.toInt(),
  String s => int.tryParse(s) ?? fallback,
  _ => fallback,
};

int? readIntOrNull(Object? v) => switch (v) {
  int i => i,
  num n => n.toInt(),
  String s => int.tryParse(s),
  _ => null,
};

String readString(Object? v, [String fallback = '']) =>
    v is String ? v : fallback;

String? readStringOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

bool readBool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

Map<String, dynamic> readMap(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

Map<String, dynamic>? readMapOrNull(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : null;

List<Object?> readList(Object? v) => v is List ? v : const <Object?>[];

List<int> readIntList(Object? v) =>
    List<int>.unmodifiable(readList(v).map((e) => readInt(e)));

List<String> readStringList(Object? v) =>
    List<String>.unmodifiable(readList(v).whereType<String>());
