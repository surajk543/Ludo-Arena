import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet with [text]. The invite text only ever
/// contains the room code (never room, player or account ids).
typedef ShareTextFn =
    Future<void> Function(String text, {String? subject, Rect? origin});

final roomShareProvider = Provider<ShareTextFn>(
  (ref) => (text, {subject, origin}) async {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: subject, sharePositionOrigin: origin),
    );
  },
);
