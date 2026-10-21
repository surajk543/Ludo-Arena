import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';

import '../network/api_client.dart';
import '../protocol/models.dart' show CatalogAsset;
import 'assets_api.dart';

/// Signs object paths (`POST /assets/sign`, ≤ [kMaxSignPaths] per call).
typedef AssetSigner = Future<SignedAssetUrls> Function(List<String> paths);

/// Downloads [url] into the file at [toPath] (created or overwritten).
/// Throws on any failure.
typedef AssetDownloader = Future<void> Function(String url, String toPath);

/// Decodes Lottie bytes. Throws when they are not a usable animation.
typedef LottieBytesDecoder = Future<LottieComposition> Function(Uint8List b);

/// A picture that is on disk and ready to draw.
@immutable
sealed class LoadedPicture {
  const LoadedPicture();
}

/// A PNG/JPEG/WebP/GIF picture: draw the [file] (Flutter's image cache keeps
/// decoded frames).
final class LoadedImagePicture extends LoadedPicture {
  const LoadedImagePicture(this.file);
  final File file;
}

/// A decoded Lottie animation, shared by every view of the same path.
final class LoadedLottiePicture extends LoadedPicture {
  const LoadedLottiePicture(this.composition);
  final LottieComposition composition;
}

/// Disk cache of catalogue assets ([CatalogAsset]: profile pictures and
/// the art of Store emotes; one instance per kind, see
/// [profilePictureCacheProvider] and [emoteAssetCacheProvider]).
///
/// - Files live at `<root>/<path>` (profile pictures:
///   `<applicationSupportDirectory>/profile_pictures/<path>`, emotes:
///   `<applicationSupportDirectory>/assets/<path>`); paths are immutable, so
///   an existing file is used as is and never downloaded again (no expiry,
///   also across app restarts).
/// - Missing files are signed in debounced batches (`POST /assets/sign`,
///   ≤ 50 paths per call), downloaded to a temporary file next to the
///   target, validated (non-empty, size cap, image magic bytes / the Lottie
///   parses) and atomically renamed into place.
/// - Concurrent requests for the same path share one download; failures
///   back off exponentially per path (and globally while the server reports
///   `assets_unavailable`).
/// - Decoded Lottie compositions are kept in a small in-memory LRU.
///
/// Every public method is failure-tolerant: `null` means "show the built-in
/// avatar". Signed URLs are never logged or kept after the download.
class ProfilePictureCache {
  ProfilePictureCache({
    required Future<Directory> Function() root,
    required this._sign,
    required this._download,
    LottieBytesDecoder? decodeLottie,
    DateTime Function()? now,
    this.signDebounce = const Duration(milliseconds: 40),
    this.maxCompositions = 48,
    this.maxBytes = 4 * 1024 * 1024,
    this.maxConcurrentDownloads = 4,
    this.baseBackoff = const Duration(seconds: 5),
    this.maxBackoff = const Duration(minutes: 10),
  }) : _rootLoader = root,
       _decodeLottie = decodeLottie ?? decodeLottieBytes,
       _now = now ?? DateTime.now;

  final Future<Directory> Function() _rootLoader;
  final AssetSigner _sign;
  final AssetDownloader _download;
  final LottieBytesDecoder _decodeLottie;
  final DateTime Function() _now;

  /// Wait after the first missing path before signing, to batch the paths
  /// of one screen into one request.
  final Duration signDebounce;

  /// Decoded Lottie compositions kept in memory.
  final int maxCompositions;

  /// Largest accepted file.
  final int maxBytes;
  final int maxConcurrentDownloads;
  final Duration baseBackoff;
  final Duration maxBackoff;

  Future<Directory>? _root;
  final Set<String> _onDisk = {};
  final LinkedHashMap<String, LottieComposition> _compositions =
      LinkedHashMap();
  final Map<String, Future<LoadedPicture?>> _loads = {};
  final Map<String, Future<File?>> _files = {};
  final Map<String, _Failure> _failures = {};
  DateTime? _signBlockedUntil;

  final Map<String, Completer<String?>> _pendingSign = {};
  Timer? _signTimer;

  int _activeDownloads = 0;
  final Queue<Completer<void>> _downloadQueue = Queue();

  bool _disposed = false;

  /// What is ready right now without any I/O: a decoded Lottie or an image
  /// already known to be on disk. Lets lists draw cached pictures in the
  /// first frame.
  LoadedPicture? peek(CatalogAsset picture) {
    final path = picture.path;
    if (picture.isLottie) {
      final c = _compositions.remove(path);
      if (c == null) return null;
      _compositions[path] = c; // most recently used
      return LoadedLottiePicture(c);
    }
    final root = _resolvedRoot;
    if (root == null || !_onDisk.contains(path)) return null;
    return LoadedImagePicture(File(_join(root, path)));
  }

  /// The picture ready to draw, downloading it once if needed. Never
  /// throws; `null` when it is unavailable right now.
  Future<LoadedPicture?> load(CatalogAsset picture) {
    if (_disposed || !picture.hasSafePath) {
      return Future.value(null);
    }
    final ready = peek(picture);
    if (ready != null) return Future.value(ready);
    return _loads[picture.path] ??= _load(picture).whenComplete(() {
      _loads.remove(picture.path);
    });
  }

  /// Ensures [picture]'s file is on disk (downloading it once) and returns
  /// it, or `null`. Never throws.
  Future<File?> file(CatalogAsset picture) async {
    if (_disposed || !picture.hasSafePath) return null;
    try {
      return await _ensureFile(picture);
    } catch (_) {
      return null;
    }
  }

  /// Warms the cache for [pictures] (e.g. a page of the Store).
  void prefetch(Iterable<CatalogAsset> pictures) {
    for (final p in pictures) {
      unawaited(load(p));
    }
  }

  void dispose() {
    _disposed = true;
    _signTimer?.cancel();
    for (final c in _pendingSign.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pendingSign.clear();
    while (_downloadQueue.isNotEmpty) {
      _downloadQueue.removeFirst().complete();
    }
    _compositions.clear();
  }

  // ------------------------------------------------------------- internals

  Directory? _rootValue;

  Directory? get _resolvedRoot => _rootValue;

  Future<Directory> _rootDir() => _root ??= _rootLoader().then((d) {
    _rootValue = d;
    return d;
  });

  static String _join(Directory root, String path) => '${root.path}/$path';

  Future<LoadedPicture?> _load(CatalogAsset picture) async {
    try {
      final file = await _ensureFile(picture);
      if (file == null || _disposed) return null;
      if (!picture.isLottie) return LoadedImagePicture(file);
      final cached = _compositions[picture.path];
      if (cached != null) return LoadedLottiePicture(cached);
      try {
        final composition = await _decodeValidLottie(await file.readAsBytes());
        _remember(picture.path, composition);
        return LoadedLottiePicture(composition);
      } catch (_) {
        // A file that no longer decodes is dropped and fetched again after
        // the backoff.
        _onDisk.remove(picture.path);
        await _deleteQuietly(file);
        _fail(picture.path);
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// One disk check / download per path at a time.
  Future<File?> _ensureFile(CatalogAsset picture) =>
      _files[picture.path] ??= _fetchFile(picture).whenComplete(() {
        // (A block body: returning the removed future would make
        // whenComplete wait for itself.)
        _files.remove(picture.path);
      });

  Future<File?> _fetchFile(CatalogAsset picture) async {
    final path = picture.path;
    final root = await _rootDir();
    final target = File(_join(root, path));
    if (_onDisk.contains(path)) return target;
    if (await target.exists()) {
      _onDisk.add(path);
      return target;
    }
    if (_inBackoff(path)) return null;

    final url = await _signed(path);
    if (url == null || _disposed) {
      _fail(path);
      return null;
    }
    await _acquireDownloadSlot();
    final tmp = File(
      '${target.path}.part-${math.Random().nextInt(1 << 32).toRadixString(36)}',
    );
    try {
      if (_disposed) return null;
      await target.parent.create(recursive: true);
      await _download(url, tmp.path);
      final bytes = await tmp.readAsBytes();
      final composition = await _validate(picture, bytes);
      await tmp.rename(target.path);
      _onDisk.add(path);
      _failures.remove(path);
      if (composition != null) _remember(path, composition);
      return target;
    } catch (_) {
      await _deleteQuietly(tmp);
      _fail(path);
      return null;
    } finally {
      _releaseDownloadSlot();
    }
  }

  /// Throws when [bytes] are not a usable picture of [picture.format].
  /// Returns the decoded composition for Lottie files.
  Future<LottieComposition?> _validate(
    CatalogAsset picture,
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('size');
    }
    if (picture.isLottie) return _decodeValidLottie(bytes);
    if (!looksLikeImage(bytes)) throw const FormatException('not an image');
    return null;
  }

  Future<LottieComposition> _decodeValidLottie(Uint8List bytes) async {
    final c = await _decodeLottie(bytes);
    if (c.layers.isEmpty ||
        c.bounds.width <= 0 ||
        c.bounds.height <= 0 ||
        c.durationFrames <= 0 ||
        c.frameRate <= 0) {
      throw const FormatException('empty animation');
    }
    return c;
  }

  void _remember(String path, LottieComposition c) {
    _compositions.remove(path);
    _compositions[path] = c;
    while (_compositions.length > maxCompositions) {
      _compositions.remove(_compositions.keys.first);
    }
  }

  // ------------------------------------------------------------ signing

  Future<String?> _signed(String path) {
    final blocked = _signBlockedUntil;
    if (blocked != null && _now().isBefore(blocked)) {
      return Future.value(null);
    }
    final existing = _pendingSign[path];
    if (existing != null) return existing.future;
    final c = _pendingSign[path] = Completer<String?>();
    _signTimer ??= Timer(signDebounce, _flushSign);
    return c.future;
  }

  Future<void> _flushSign() async {
    _signTimer = null;
    if (_pendingSign.isEmpty) return;
    final batch = Map.of(_pendingSign);
    _pendingSign.clear();
    final paths = batch.keys.toList();
    for (var i = 0; i < paths.length; i += kMaxSignPaths) {
      final chunk = paths.sublist(i, math.min(i + kMaxSignPaths, paths.length));
      Map<String, String> urls = const {};
      try {
        if (!_disposed) urls = (await _sign(chunk)).urls;
      } on ApiException catch (e) {
        if (e.code == 'assets_unavailable') {
          _signBlockedUntil = _now().add(maxBackoff ~/ 2);
        }
      } catch (_) {
        // Treated as unavailable for this batch; per-path backoff follows.
      }
      for (final p in chunk) {
        final c = batch[p]!;
        if (!c.isCompleted) c.complete(urls[p]);
      }
    }
  }

  // ----------------------------------------------------------- backoff

  bool _inBackoff(String path) {
    final f = _failures[path];
    return f != null && _now().isBefore(f.retryAt);
  }

  void _fail(String path) {
    final attempts = (_failures[path]?.attempts ?? 0) + 1;
    final factor = 1 << math.min(attempts - 1, 16);
    final wait = baseBackoff * factor;
    _failures[path] = _Failure(
      attempts,
      _now().add(wait > maxBackoff ? maxBackoff : wait),
    );
  }

  // --------------------------------------------------------- downloads

  Future<void> _acquireDownloadSlot() async {
    if (_activeDownloads < maxConcurrentDownloads) {
      _activeDownloads++;
      return;
    }
    final c = Completer<void>();
    _downloadQueue.add(c);
    await c.future;
    _activeDownloads++;
  }

  void _releaseDownloadSlot() {
    _activeDownloads--;
    if (_downloadQueue.isNotEmpty) _downloadQueue.removeFirst().complete();
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ------------------------------------------------------------ helpers

  /// PNG, JPEG, GIF or WebP signature.
  @visibleForTesting
  static bool looksLikeImage(Uint8List b) {
    bool starts(List<int> sig, [int offset = 0]) {
      if (b.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[offset + i] != sig[i]) return false;
      }
      return true;
    }

    return starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) ||
        starts(const [0xFF, 0xD8, 0xFF]) ||
        starts(const [0x47, 0x49, 0x46, 0x38]) ||
        (starts(const [0x52, 0x49, 0x46, 0x46]) &&
            starts(const [0x57, 0x45, 0x42, 0x50], 8));
  }

  /// Parses Lottie JSON (or a zipped `.lottie`) and decodes its embedded
  /// `data:` images. External image references are never fetched.
  static Future<LottieComposition> decodeLottieBytes(Uint8List bytes) async {
    final composition = await LottieComposition.fromBytes(bytes);
    for (final image in composition.images.values) {
      if (image.loadedImage != null) continue;
      final data = image.fileName.startsWith('data:')
          ? Uri.tryParse(image.fileName)?.data
          : null;
      if (data == null) continue;
      try {
        final codec = await ui.instantiateImageCodec(data.contentAsBytes());
        image.loadedImage = (await codec.getNextFrame()).image;
        codec.dispose();
      } catch (_) {
        // The layer stays empty; the rest of the animation still draws.
      }
    }
    return composition;
  }
}

@immutable
class _Failure {
  const _Failure(this.attempts, this.retryAt);
  final int attempts;
  final DateTime retryAt;
}

/// Downloads with a plain [Dio] (no app headers, no auth: the URL is
/// pre-signed), refusing bodies over [maxBytes].
AssetDownloader dioAssetDownloader(Dio dio, {int maxBytes = 4 << 20}) =>
    (url, toPath) async {
      final cancel = CancelToken();
      await dio.download(
        url,
        toPath,
        cancelToken: cancel,
        deleteOnError: true,
        options: Options(
          followRedirects: false,
          validateStatus: (s) => s == 200,
        ),
        onReceiveProgress: (received, _) {
          if (received > maxBytes) cancel.cancel();
        },
      );
    };

/// A cache under `<applicationSupportDirectory>/<folder>` that signs through
/// `POST /assets/sign` and downloads with its own plain [Dio].
ProfilePictureCache _supportDirCache(Ref ref, String folder) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  final cache = ProfilePictureCache(
    root: () async {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}/$folder');
    },
    sign: (paths) => AssetsApi(ref.read(apiClientProvider)).sign(paths),
    download: dioAssetDownloader(dio),
  );
  ref.onDispose(() {
    cache.dispose();
    dio.close(force: true);
  });
  return cache;
}

/// The app-wide profile-picture cache. Tests override it with a fake (or a
/// real cache over a temporary directory and fake transport).
final profilePictureCacheProvider = Provider<ProfilePictureCache>(
  (ref) => _supportDirCache(ref, 'profile_pictures'),
);

/// The app-wide cache of Store emote art (`emotes/…` paths, stored at
/// `<applicationSupportDirectory>/assets/emotes/…`). A separate instance from
/// the profile pictures: its own in-memory LRU of decoded animations, so a
/// match full of emotes never evicts the players' pictures.
final emoteAssetCacheProvider = Provider<ProfilePictureCache>(
  (ref) => _supportDirCache(ref, 'assets'),
);
