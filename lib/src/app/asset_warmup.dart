import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Warms the asset caches right after the first frame, so the first screens
/// (login, onboarding, the card, home) draw their pictures and icons without
/// a first-paint stutter: every bundled raster the app shows early is decoded
/// into the image cache, every SVG icon is parsed into the SVG byte cache.
/// One asset at a time, so the warm-up never stalls a frame, and each failure
/// is swallowed: a warm-up is never worth a crash.
class AssetWarmup extends StatefulWidget {
  const AssetWarmup({required this.child, super.key});

  final Widget child;

  /// Room for the home letters, the onboarding art and the card papers on top
  /// of the photos a session loads; the framework's default is 100 MB.
  static const imageCacheBytes = 200 << 20;

  /// The rasters decoded ahead: every bundled picture and picture icon.
  static bool warmsImage(String asset) =>
      RegExp(r'\.(png|webp|jpe?g)$').hasMatch(asset) &&
      asset.startsWith('assets/');

  /// Every bundled SVG: the line icons, the guide's tags and flags, the logo.
  static bool warmsSvg(String asset) =>
      asset.endsWith('.svg') && asset.startsWith('assets/');

  /// Warms every asset of the bundle that [warmsImage] or [warmsSvg] names.
  static Future<void> run(BuildContext context) async {
    List<String> assets;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      assets = manifest.listAssets();
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    await warm(context, assets.where((a) => warmsImage(a) || warmsSvg(a)));
  }

  /// Decodes the rasters and parses the SVGs among [assets], in order.
  static Future<void> warm(
    BuildContext context,
    Iterable<String> assets,
  ) async {
    final list = assets.toList();
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSizeBytes = math.max(
      imageCache.maximumSizeBytes,
      imageCacheBytes,
    );
    // The SVG cache holds 100 entries by default; the icon set alone is more.
    svg.cache.maximumSize = math.max(
      svg.cache.maximumSize,
      list.where(warmsSvg).length + 100,
    );
    for (final asset in list) {
      if (!context.mounted) return;
      if (warmsSvg(asset)) {
        try {
          await SvgAssetLoader(asset).loadBytes(null);
        } catch (_) {
          // A broken SVG shows its own error where it is drawn.
        }
      } else {
        await precacheImage(AssetImage(asset), context, onError: (_, _) {});
      }
    }
  }

  @override
  State<AssetWarmup> createState() => _AssetWarmupState();
}

class _AssetWarmupState extends State<AssetWarmup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AssetWarmup.run(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
