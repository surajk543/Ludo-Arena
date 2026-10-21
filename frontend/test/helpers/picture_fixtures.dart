import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ludo_royale/core/assets/assets_api.dart';
import 'package:ludo_royale/core/assets/profile_picture_cache.dart';
import 'package:ludo_royale/core/protocol/models.dart'
    show CatalogAsset, EmoteAsset, PlayerPicture;
import 'package:lottie/lottie.dart';

/// A tiny hand-written Lottie (one pulsing circle, 30 frames, 64×64).
const String kTestLottieJson =
    '{"v":"5.7.4","fr":30,"ip":0,"op":30,"w":64,"h":64,"nm":"dot","ddd":0,'
    '"assets":[],"layers":[{"ddd":0,"ind":1,"ty":4,"nm":"circle","sr":1,'
    '"ks":{"o":{"a":0,"k":100},"r":{"a":0,"k":0},"p":{"a":0,"k":[32,32,0]},'
    '"a":{"a":0,"k":[0,0,0]},"s":{"a":1,"k":['
    '{"i":{"x":[0.5],"y":[1]},"o":{"x":[0.5],"y":[0]},"t":0,"s":[80,80,100]},'
    '{"t":30,"s":[100,100,100]}]}},"ao":0,"shapes":[{"ty":"gr","nm":"g","it":['
    '{"ty":"el","nm":"e","d":1,"p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[40,40]}},'
    '{"ty":"fl","nm":"f","c":{"a":0,"k":[0.36,0.25,0.82,1]},"o":{"a":0,"k":100},"r":1},'
    '{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},'
    '"r":{"a":0,"k":0},"o":{"a":0,"k":100}}]}],"ip":0,"op":30,"st":0,"bm":0}]}';

Uint8List get kTestLottieBytes =>
    Uint8List.fromList(utf8.encode(kTestLottieJson));

/// A valid 1×1 PNG.
final Uint8List kTestPngBytes = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x88, 0x71, 0xB8, 0xF0, //
  0x1F, 0x00, 0x04, 0xD4, 0x02, 0x6C, 0xF0, 0xD4, 0x42, 0x1B, 0x00, 0x00, //
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// The decoded [kTestLottieJson].
LottieComposition testComposition() =>
    LottieComposition.parseJsonBytes(kTestLottieBytes);

PlayerPicture lottiePicture([String name = 'dot']) => PlayerPicture(
  id: 'pp_$name',
  format: PlayerPicture.formatLottie,
  path: 'profile_pictures/lottie_animation/$name.json',
);

PlayerPicture imagePicture([String name = 'bear']) => PlayerPicture(
  id: 'pp_$name',
  format: PlayerPicture.formatImage,
  path: 'profile_pictures/image/$name.png',
);

/// Wire `PlayerPicture` JSON.
Map<String, dynamic> pictureJson(PlayerPicture p) => p.toJson();

/// Profile-picture cache for widget tests: no file system, no network.
/// Pictures in [ready] resolve at once; everything else stays on the
/// placeholder (like an offline device).
class FakeProfilePictureCache extends ProfilePictureCache {
  FakeProfilePictureCache({Map<String, LoadedPicture>? ready})
    : ready = ready ?? {},
      super(
        root: () async => Directory.systemTemp,
        sign: (_) async => const SignedAssetUrls(urls: {}, expiresAt: 0),
        download: (_, _) async => throw UnsupportedError('no network'),
      );

  /// Ready pictures by path.
  final Map<String, LoadedPicture> ready;

  /// Every path a view asked for.
  final List<String> requested = [];

  @override
  LoadedPicture? peek(CatalogAsset picture) => ready[picture.path];

  @override
  Future<LoadedPicture?> load(CatalogAsset picture) async {
    requested.add(picture.path);
    return ready[picture.path];
  }

  @override
  Future<File?> file(CatalogAsset picture) async => null;
}

/// A Store emote's art (`emotes/<name>.json`).
EmoteAsset emoteAsset([String name = 'angry']) =>
    EmoteAsset(format: 'lottie', path: 'emotes/$name.json');
