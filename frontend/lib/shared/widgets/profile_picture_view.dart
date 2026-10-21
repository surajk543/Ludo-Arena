import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../core/assets/profile_picture_cache.dart';
import '../../core/audio_haptics/reduced_motion.dart';
import '../../core/protocol/models.dart'
    show CatalogAsset, EmoteAsset, PlayerPicture;

/// Draws a Store profile picture from the on-device cache: a Lottie
/// animation or an image, filling a [size]×[size] square.
///
/// Shows [placeholder] until the picture is on disk and decoded, and keeps
/// showing it when the picture is unavailable (offline, storage not
/// configured, corrupt file). With reduced motion (or [animate] false) a
/// Lottie shows its first frame and never ticks.
class ProfilePictureView extends StatelessWidget {
  const ProfilePictureView({
    super.key,
    required this.picture,
    required this.size,
    this.placeholder,
    this.animate = true,
    this.fit = BoxFit.cover,
  });

  final PlayerPicture picture;
  final double size;
  final Widget? placeholder;
  final bool animate;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => CatalogAssetView(
    asset: picture,
    cache: profilePictureCacheProvider,
    size: size,
    placeholder: placeholder,
    animate: animate,
    fit: fit,
  );
}

/// Draws the art of a Store emote from the on-device emote cache
/// ([emoteAssetCacheProvider]), contained in a [size]×[size] square, with
/// [placeholder] until it is ready. Same rules as [ProfilePictureView].
class EmoteAssetView extends StatelessWidget {
  const EmoteAssetView({
    super.key,
    required this.asset,
    required this.size,
    this.placeholder,
    this.animate = true,
  });

  final EmoteAsset asset;
  final double size;
  final Widget? placeholder;
  final bool animate;

  @override
  Widget build(BuildContext context) => CatalogAssetView(
    asset: asset,
    cache: emoteAssetCacheProvider,
    size: size,
    placeholder: placeholder,
    animate: animate,
    fit: BoxFit.contain,
  );
}

/// Draws a [CatalogAsset] from [cache]: a Lottie animation or an image in a
/// [size]×[size] square, [placeholder] until it is on disk and decoded (and
/// whenever it is unavailable). With reduced motion (or [animate] false) a
/// Lottie shows its first frame and never ticks.
class CatalogAssetView extends ConsumerStatefulWidget {
  const CatalogAssetView({
    super.key,
    required this.asset,
    required this.cache,
    required this.size,
    this.placeholder,
    this.animate = true,
    this.fit = BoxFit.cover,
  });

  final CatalogAsset asset;
  final Provider<ProfilePictureCache> cache;
  final double size;
  final Widget? placeholder;
  final bool animate;
  final BoxFit fit;

  @override
  ConsumerState<CatalogAssetView> createState() => _CatalogAssetViewState();
}

class _CatalogAssetViewState extends ConsumerState<CatalogAssetView> {
  LoadedPicture? _loaded;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CatalogAssetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset || oldWidget.cache != widget.cache) {
      _loaded = null;
      _resolve();
    }
  }

  void _resolve() {
    final request = ++_request;
    final cache = ref.read(widget.cache);
    final ready = cache.peek(widget.asset);
    if (ready != null) {
      _loaded = ready;
      return;
    }
    cache.load(widget.asset).then((loaded) {
      if (!mounted || request != _request || loaded == null) return;
      setState(() => _loaded = loaded);
    });
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.placeholder ?? const SizedBox.shrink();
    final size = widget.size;
    final Widget child = switch (_loaded) {
      null => placeholder,
      LoadedLottiePicture(:final composition) => Lottie(
        composition: composition,
        width: size,
        height: size,
        fit: widget.fit,
        animate: widget.animate && !context.reduceMotion,
        filterQuality: FilterQuality.medium,
      ),
      LoadedImagePicture(:final file) => Image.file(
        file,
        width: size,
        height: size,
        fit: widget.fit,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        frameBuilder: (context, image, frame, sync) =>
            frame == null && !sync ? placeholder : image,
        errorBuilder: (context, error, stack) => placeholder,
      ),
    };
    return SizedBox.square(dimension: size, child: child);
  }
}
