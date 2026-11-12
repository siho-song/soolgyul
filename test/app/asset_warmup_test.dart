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
        'assets/images/login/login_hero.png',
        'assets/images/onboarding/onboarding_preview_card.webp',
        'assets/images/onboarding/onboarding_selected_brush_underline.png',
        'assets/images/paper/paper_cream.webp',
        'assets/images/paper/next_drink_quote_card_background.png',
        'assets/images/home/home_soolgyul_letter_wine_processed.png',
      ]),
    );
    expect(
      svgs,
      containsAll(<String>[
        'assets/icons/line/search.svg',
        'assets/icons/line/nav_home.svg',
        'assets/icons/guide_tags/heart.svg',
        'assets/icons/flags/fr.svg',
      ]),
    );
    expect(svgs.length, greaterThan(70));
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
    const image = 'assets/images/login/login_hero.png';
    const icon = 'assets/icons/guide_tags/heart.svg';
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
