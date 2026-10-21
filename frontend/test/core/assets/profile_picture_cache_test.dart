import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/assets/assets_api.dart';
import 'package:ludo_royale/core/assets/profile_picture_cache.dart';
import 'package:ludo_royale/core/network/api_exception.dart';
import 'package:ludo_royale/core/protocol/models.dart' show PlayerPicture;

import '../../helpers/picture_fixtures.dart';

/// `POST /assets/sign` stand-in: signs every path except [omit].
class _Signer {
  final List<List<String>> calls = [];
  final Set<String> omit = {};
  Object? error;

  Future<SignedAssetUrls> call(List<String> paths) async {
    calls.add(List.of(paths));
    final e = error;
    if (e != null) throw e;
    return SignedAssetUrls(
      urls: {
        for (final p in paths)
          if (!omit.contains(p)) p: 'https://r2.test/$p?X-Amz-Signature=s',
      },
      expiresAt: 4102444800000,
    );
  }

  int get pathCount => calls.fold(0, (n, c) => n + c.length);
}

/// Download stand-in: writes [bodies] (by path) or [fallback].
class _Downloader {
  final List<String> urls = [];
  final Map<String, Uint8List> bodies = {};
  Uint8List? fallback;
  Object? error;

  /// While set, downloads wait for it (to observe concurrency).
  Completer<void>? gate;

  Future<void> call(String url, String toPath) async {
    urls.add(url);
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    final path = Uri.parse(url).path.substring(1);
    final body = bodies[path] ?? fallback;
    if (body == null) throw StateError('no body for $path');
    await File(toPath).writeAsBytes(body, flush: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory root;
  late _Signer signer;
  late _Downloader downloader;
  late DateTime now;

  /// [debounce] long enough for every concurrent disk check to finish
  /// before the batch is signed (the checks are real file I/O).
  ProfilePictureCache newCache({
    int maxCompositions = 48,
    Duration debounce = Duration.zero,
  }) => ProfilePictureCache(
    root: () async => root,
    sign: signer.call,
    download: downloader.call,
    now: () => now,
    signDebounce: debounce,
    maxCompositions: maxCompositions,
  );

  /// Waits (real time) until [done], failing after 5 s.
  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('condition not reached');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  File fileOf(PlayerPicture p) => File('${root.path}/${p.path}');

  List<String> leftovers() => tmp
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.contains('.part-'))
      .toList();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pp_cache_test_');
    root = Directory('${tmp.path}/profile_pictures');
    signer = _Signer();
    downloader = _Downloader()
      ..bodies[lottiePicture().path] = kTestLottieBytes
      ..bodies[imagePicture().path] = kTestPngBytes;
    now = DateTime(2026, 10, 21, 12);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('a file already on disk is used without any network', () async {
    final lottie = lottiePicture();
    final image = imagePicture();
    fileOf(lottie)
      ..createSync(recursive: true)
      ..writeAsBytesSync(kTestLottieBytes);
    fileOf(image)
      ..createSync(recursive: true)
      ..writeAsBytesSync(kTestPngBytes);
    final cache = newCache();
    addTearDown(cache.dispose);

    final l = await cache.load(lottie);
    final i = await cache.load(image);
    expect(l, isA<LoadedLottiePicture>());
    expect((i! as LoadedImagePicture).file.path, fileOf(image).path);
    expect(signer.calls, isEmpty);
    expect(downloader.urls, isEmpty);

    // Memory hits are synchronous and share the decoded composition.
    final again = cache.peek(lottie);
    expect(
      (again! as LoadedLottiePicture).composition,
      same((l! as LoadedLottiePicture).composition),
    );
    expect(cache.peek(image), isA<LoadedImagePicture>());
  });

  test('a miss is signed and downloaded once, then always read from disk '
      '(also after a restart)', () async {
    final p = lottiePicture();
    final cache = newCache();
    addTearDown(cache.dispose);

    expect(await cache.load(p), isA<LoadedLottiePicture>());
    expect(signer.calls, [
      [p.path],
    ]);
    expect(downloader.urls, hasLength(1));
    expect(fileOf(p).readAsBytesSync(), kTestLottieBytes);
    expect(leftovers(), isEmpty);

    expect(await cache.load(p), isA<LoadedLottiePicture>());
    final restarted = newCache();
    addTearDown(restarted.dispose);
    expect(await restarted.load(p), isA<LoadedLottiePicture>());
    expect(await restarted.file(p), isNotNull);
    expect(signer.calls, hasLength(1));
    expect(downloader.urls, hasLength(1));
  });

  test('concurrent requests share one sign batch and one download per '
      'path', () async {
    final a = lottiePicture('a');
    final b = imagePicture('b');
    downloader
      ..bodies[a.path] = kTestLottieBytes
      ..bodies[b.path] = kTestPngBytes
      ..gate = Completer<void>();
    final cache = newCache(debounce: const Duration(milliseconds: 300));
    addTearDown(cache.dispose);

    final futures = [
      cache.load(a),
      cache.load(a),
      cache.file(a),
      cache.load(b),
      cache.load(b),
    ];
    await until(() => downloader.urls.length == 2);
    await pumpEventQueue();
    expect(signer.calls, hasLength(1));
    expect(signer.calls.single, unorderedEquals([a.path, b.path]));
    expect(downloader.urls, hasLength(2));

    downloader.gate!.complete();
    final results = await Future.wait(futures);
    expect(results.whereType<Object>(), hasLength(5));
    expect(downloader.urls, hasLength(2));
  });

  test('sign batches hold at most 50 paths', () async {
    final pictures = [for (var i = 0; i < 60; i++) imagePicture('p$i')];
    downloader.fallback = kTestPngBytes;
    final cache = newCache(debounce: const Duration(milliseconds: 300));
    addTearDown(cache.dispose);

    await Future.wait(pictures.map(cache.load));
    expect(signer.calls.map((c) => c.length), [kMaxSignPaths, 10]);
    expect(signer.calls.expand((c) => c).toSet(), hasLength(60));
    expect(downloader.urls, hasLength(60));
  });

  test('a corrupt download is rejected and never stored', () async {
    final lottie = lottiePicture('broken');
    final image = imagePicture('html');
    downloader
      ..bodies[lottie.path] = Uint8List.fromList('{"v":"5"'.codeUnits)
      ..bodies[image.path] = Uint8List.fromList(
        '<html>AccessDenied</html>'.codeUnits,
      );
    final cache = newCache();
    addTearDown(cache.dispose);

    expect(await cache.load(lottie), isNull);
    expect(await cache.load(image), isNull);
    expect(fileOf(lottie).existsSync(), isFalse);
    expect(fileOf(image).existsSync(), isFalse);
    expect(leftovers(), isEmpty);

    // An empty body is rejected too.
    final empty = imagePicture('empty');
    downloader.bodies[empty.path] = Uint8List(0);
    expect(await cache.load(empty), isNull);
    expect(fileOf(empty).existsSync(), isFalse);
  });

  test('failures back off exponentially before the next attempt', () async {
    final p = imagePicture();
    downloader.error = const SocketException('offline');
    final cache = newCache();
    addTearDown(cache.dispose);

    expect(await cache.load(p), isNull);
    expect(downloader.urls, hasLength(1));

    // Inside the first backoff (5 s): no new request.
    now = now.add(const Duration(seconds: 4));
    expect(await cache.load(p), isNull);
    expect(signer.calls, hasLength(1));

    // After it: one more attempt, which fails again → 10 s backoff.
    now = now.add(const Duration(seconds: 2));
    expect(await cache.load(p), isNull);
    expect(downloader.urls, hasLength(2));
    now = now.add(const Duration(seconds: 6));
    expect(await cache.load(p), isNull);
    expect(downloader.urls, hasLength(2));

    downloader.error = null;
    now = now.add(const Duration(seconds: 5));
    expect(await cache.load(p), isA<LoadedImagePicture>());
    expect(downloader.urls, hasLength(3));
  });

  test('assets_unavailable pauses signing for every path', () async {
    signer.error = const ApiException(code: 'assets_unavailable', status: 503);
    final cache = newCache();
    addTearDown(cache.dispose);

    expect(await cache.load(imagePicture()), isNull);
    expect(await cache.load(lottiePicture()), isNull);
    expect(signer.calls, hasLength(1));
    expect(downloader.urls, isEmpty);

    signer.error = null;
    now = now.add(const Duration(minutes: 6));
    expect(await cache.load(lottiePicture()), isA<LoadedLottiePicture>());
    expect(signer.calls, hasLength(2));
  });

  test('paths the server does not sign are not downloaded', () async {
    final p = imagePicture('unknown');
    signer.omit.add(p.path);
    final cache = newCache();
    addTearDown(cache.dispose);

    expect(await cache.load(p), isNull);
    expect(signer.calls, hasLength(1));
    expect(downloader.urls, isEmpty);
  });

  test('unsafe paths never reach the network or the file system', () async {
    final cache = newCache();
    addTearDown(cache.dispose);
    for (final path in [
      'profile_pictures/../../secrets.json',
      '/etc/passwd',
      'other/x.png',
      'profile_pictures/a b.png',
    ]) {
      final p = PlayerPicture(id: 'pp_x', format: 'image', path: path);
      expect(await cache.load(p), isNull, reason: path);
      expect(await cache.file(p), isNull, reason: path);
    }
    expect(signer.calls, isEmpty);
    expect(downloader.urls, isEmpty);
    expect(tmp.listSync(), isEmpty);
  });

  test('decoded Lottie compositions are an LRU of bounded size', () async {
    final pictures = [
      for (final n in ['a', 'b', 'c']) lottiePicture(n),
    ];
    downloader.fallback = kTestLottieBytes;
    final cache = newCache(maxCompositions: 2);
    addTearDown(cache.dispose);

    for (final p in pictures) {
      await cache.load(p);
    }
    expect(cache.peek(pictures[0]), isNull); // evicted
    expect(cache.peek(pictures[1]), isNotNull);
    expect(cache.peek(pictures[2]), isNotNull);

    // Evicted: decoded again from disk, never downloaded again.
    expect(await cache.load(pictures[0]), isA<LoadedLottiePicture>());
    expect(downloader.urls, hasLength(3));
  });

  test('image signatures', () {
    expect(ProfilePictureCache.looksLikeImage(kTestPngBytes), isTrue);
    expect(
      ProfilePictureCache.looksLikeImage(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]),
      ),
      isTrue,
    );
    expect(
      ProfilePictureCache.looksLikeImage(
        Uint8List.fromList('RIFF\x00\x00\x00\x00WEBPVP8 '.codeUnits),
      ),
      isTrue,
    );
    expect(
      ProfilePictureCache.looksLikeImage(Uint8List.fromList('{}'.codeUnits)),
      isFalse,
    );
  });

  test('a Lottie without layers or size is not an animation', () async {
    final p = lottiePicture('blank');
    downloader.bodies[p.path] = Uint8List.fromList(
      '{"v":"5.7.4","fr":30,"ip":0,"op":30,"w":0,"h":0,"layers":[]}'.codeUnits,
    );
    final cache = newCache();
    addTearDown(cache.dispose);
    expect(await cache.load(p), isNull);
    expect(fileOf(p).existsSync(), isFalse);
  });
}
