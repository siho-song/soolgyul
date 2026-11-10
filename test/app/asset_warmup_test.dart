import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/asset_warmup.dart';

void main() {
  testWidgets('the bundle names the first screens\' art and every icon', (
    tester,
  ) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();
    final images = assets.where(AssetWarmup.warmsImage).toList();
    final svgs = assets.where(AssetWarmup.warmsSvg).toList();
    expect(
      images,
      containsAll(<String>[
        'assets/component_assets/login_hero.png',
        'assets/component_assets/onboarding_welcome_reflection_faded.png',
        'assets/component_assets/onboarding_selected_brush_underline.png',
        'assets/component_assets/taste_card/paper_cream.webp',
        'assets/component_assets/next_drink_quote_card_background.png',
        'assets/component_assets/home_soolgyul_letter_wine_processed.png',
      ]),
    );
    expect(images.where((a) => a.contains('explore_feed/')), isEmpty);
    expect(
      svgs,
      containsAll(<String>[
        'assets/icons/soolgyeol/search.svg',
        'assets/icons/soolgyeol/search_strong.svg',
        'assets/component_assets/taste_card/tags/heart.svg',
        'assets/component_assets/taste_card/flags/fr.svg',
      ]),
    );
    expect(svgs.length, greaterThan(100));
    expect(
      assets.where((a) => a.endsWith('.ttf')).any(AssetWarmup.warmsImage),
      isFalse,
    );
  });

  testWidgets('warming fills the image cache and the SVG cache', (
    tester,
  ) async {
    await tester.pumpWidget(const AssetWarmup(child: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    const image = 'assets/component_assets/login_hero.png';
    const icon = 'assets/component_assets/taste_card/tags/heart.svg';
    final key = await const AssetImage(
      image,
    ).obtainKey(createLocalImageConfiguration(context));
    expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
    svg.cache.clear();

    await tester.runAsync(
      () => AssetWarmup.warm(context, const <String>[image, icon]),
    );

    expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
    expect(svg.cache.count, 1);
    expect(
      PaintingBinding.instance.imageCache.maximumSizeBytes,
      greaterThanOrEqualTo(AssetWarmup.imageCacheBytes),
    );
    expect(svg.cache.maximumSize, greaterThanOrEqualTo(101));
  });
}
