import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/async_shown.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_surface.dart';
import '../../../widgets/app_section_action.dart';
import '../data/home_placeholder_content.dart';
import '../data/home_providers.dart';
import '../data/taste_letters.dart';

/// The tile for one axis: olive for 향·무게, wine for 단맛·여운, the unknown
/// tile while the axis has no letter. The stored letter is drawn as its
/// Korean glyph.
SoolgyulLetter tileForAxis(TasteLetterAxis axis, String? letter) {
  if (letter == null) return unknownLetter;
  final glyph = TasteLetterPole.glyphOf(letter);
  return switch (axis) {
    TasteLetterAxis.aroma || TasteLetterAxis.weight => (
      asset: oliveLetter.asset,
      letter: glyph,
      color: oliveLetter.color,
    ),
    TasteLetterAxis.sweetness || TasteLetterAxis.finish => (
      asset: wineLetter.asset,
      letter: glyph,
      color: wineLetter.color,
    ),
  };
}

List<SoolgyulLetter> tilesForState(TasteLettersState? state) => [
  for (final axis in TasteLetterAxis.values)
    tileForAxis(axis, state?.letterOf(axis)),
];

/// The home card. Without a gateway it shows the design placeholder.
class SoolgyulLettersCard extends ConsumerWidget {
  const SoolgyulLettersCard({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(tasteLettersGatewayProvider) == null) {
      return _SoolgyulLettersCardBody(
        onOpen: onOpen,
        letters: soolgyulLetters,
        supporting: '부드럽게 넘어가고 은은한 여운이 남는 술이 잘 맞아요.',
      );
    }
    final letters = ref.watch(tasteLettersProvider);
    final loaded = shownValue(letters);
    final state = loaded?.state;
    final supporting = loaded != null
        ? state?.overviewStatement ?? '첫 술결을 남기면 내 취향 조각이 채워져요.'
        : letters.hasError && !letters.isLoading
        ? '취향 조각을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'
        : '가이드를 불러오는 중이에요...';
    return _SoolgyulLettersCardBody(
      onOpen: onOpen,
      letters: tilesForState(state),
      supporting: supporting,
    );
  }
}

class _SoolgyulLettersCardBody extends StatelessWidget {
  const _SoolgyulLettersCardBody({
    required this.onOpen,
    required this.letters,
    required this.supporting,
  });

  final VoidCallback onOpen;
  final List<SoolgyulLetter> letters;
  final String supporting;

  @override
  Widget build(BuildContext context) => AppPanel(
    onPressed: onOpen,
    semanticLabel: '취향 조각 자세히 보기',
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      18,
      AppSpacing.xl,
      AppSpacing.xl,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Row(
          children: <Widget>[
            Expanded(
              child: Text('나의 취향 조각', style: AppTextStyles.sectionTitle),
            ),
            AppSectionAction(label: '자세히 보기'),
          ],
        ),
        const SizedBox(height: 17),
        SoolgyulLetterStrip(letters: letters),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const AppIcon(
              AppIconAsset.smooth,
              size: 17,
              color: AppColors.textSupporting,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                supporting,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.homeCardSupporting,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// The four tiles in axis order with the axis name (향·단맛·무게·여운)
/// captioned under each one.
class SoolgyulLetterStrip extends StatelessWidget {
  const SoolgyulLetterStrip({
    super.key,
    this.letters = soolgyulLetters,
    this.height = 58,
    this.letterSize = 23,
  });

  final List<SoolgyulLetter> letters;
  final double height;
  final double letterSize;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          boxShadow: AppShadows.homeLetterStrip,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: <Widget>[
            for (final letter in letters)
              Expanded(
                child: SoolgyulLetterTile(letter: letter, fontSize: letterSize),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: <Widget>[
          for (final axis in TasteLetterAxis.values)
            Expanded(
              child: Text(
                axis.label,
                textAlign: TextAlign.center,
                style: AppTextStyles.homeLetterCaption,
              ),
            ),
        ],
      ),
    ],
  );
}

class SoolgyulLetterTile extends StatelessWidget {
  const SoolgyulLetterTile({
    super.key,
    required this.letter,
    this.fontSize = 23,
  });

  final SoolgyulLetter letter;
  final double fontSize;

  bool get _unknown => letter == unknownLetter;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      Image.asset(
        letter.asset,
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
      ),
      if (_unknown)
        const CustomPaint(painter: _DashedFramePainter(), child: SizedBox()),
      Center(
        child: Text(
          letter.letter,
          style: AppTextStyles.homeLetter(
            fontSize: fontSize,
            color: letter.color,
          ),
        ),
      ),
    ],
  );
}

/// A dashed frame just inside the tile edge, marking a slot not yet opened.
class _DashedFramePainter extends CustomPainter {
  const _DashedFramePainter();

  static const _inset = 5.0;
  static const _dash = 4.0;
  static const _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.homeLetterUnknown.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Rect.fromLTWH(
      _inset,
      _inset,
      size.width - _inset * 2,
      size.height - _inset * 2,
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFramePainter oldDelegate) => false;
}
