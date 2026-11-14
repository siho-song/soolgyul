import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_badge.dart';

void main() {
  test('each verdict has its own face and words; an unjudged bottle none', () {
    final faces = <TasteFitBadge, String?>{
      for (final badge in TasteFitBadge.values)
        badge: TasteFitBadgeIcon.assetOf(badge),
    };
    final labels = <TasteFitBadge, String?>{
      for (final badge in TasteFitBadge.values)
        badge: TasteFitRowBadge.labelOf(badge),
    };
    expect(labels, <TasteFitBadge, String?>{
      TasteFitBadge.star: '취향 저격',
      TasteFitBadge.neutral: '편안해요',
      TasteFitBadge.unfamiliar: '낯설 수 있어요',
      TasteFitBadge.caution: '아쉬울 수 있어요',
      TasteFitBadge.noInfo: null,
    });
    expect(faces[TasteFitBadge.noInfo], isNull);
    final drawn = faces.values.nonNulls.toList();
    expect(drawn.toSet(), hasLength(4));
    for (final asset in drawn) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('the server names survive a round trip; an unknown one is unjudged', () {
    for (final badge in TasteFitBadge.values) {
      expect(TasteFitBadge.fromWire(badge.wire), badge);
    }
    expect(TasteFitBadge.fromWire('unfamiliar'), TasteFitBadge.unfamiliar);
    expect(TasteFitBadge.fromWire('something_newer'), TasteFitBadge.noInfo);
  });
}
