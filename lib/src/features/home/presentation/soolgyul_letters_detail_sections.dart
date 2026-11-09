import 'package:flutter/material.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_chip.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_section_action.dart';
import '../../../widgets/app_surface.dart';
import '../data/home_placeholder_content.dart';
import '../data/taste_letters.dart';
import 'soolgyul_letters_card.dart';

class LettersSectionIntroduction extends StatelessWidget {
  const LettersSectionIntroduction({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(title, style: AppTextStyles.sectionTitle),
      const SizedBox(height: AppSpacing.sm),
      Text(description, style: AppTextStyles.body),
    ],
  );
}

/// The panel at the top of the detail. Without [state] and [message] it is
/// the design placeholder; [message] replaces the data lines while the
/// letters load or fail.
class SoolgyulOverviewPanel extends StatelessWidget {
  const SoolgyulOverviewPanel({super.key, this.state, this.message});

  final TasteLettersState? state;
  final String? message;

  bool get _placeholder => state == null && message == null;

  @override
  Widget build(BuildContext context) => AppPanel(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _placeholder ? '민지님의 취향 조각' : '나의 취향 조각',
          textAlign: TextAlign.center,
          style: AppTextStyles.homeLettersOverviewTitle,
        ),
        const SizedBox(height: AppSpacing.lg),
        SoolgyulLetterStrip(
          letters: _placeholder ? soolgyulLetters : tilesForState(state),
          height: 86,
          letterSize: 30,
        ),
        const SizedBox(height: AppSpacing.xl),
        if (message case final message?)
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.homeLettersOverviewBody,
          )
        else
          Text.rich(
            _placeholder ? _placeholderStatement : _statement,
            textAlign: TextAlign.center,
          ),
      ],
    ),
  );

  TextSpan get _statement {
    final state = this.state!;
    final revealed = state.revealed;
    if (revealed.isEmpty) {
      return TextSpan(
        text: state.overviewStatement,
        style: AppTextStyles.homeLettersOverviewStatement,
      );
    }
    return TextSpan(
      style: AppTextStyles.homeLettersOverviewStatement,
      children: <InlineSpan>[
        for (var index = 0; index < revealed.length; index++) ...<InlineSpan>[
          if (index > 0) const TextSpan(text: ' '),
          TextSpan(
            text: TasteLetterPole.of(state.letterOf(revealed[index]))!.phrase,
            style: _phraseStyle(revealed[index]),
          ),
        ],
        const TextSpan(text: ' 술이 편해요.'),
      ],
    );
  }

  static TextStyle _phraseStyle(TasteLetterAxis axis) => switch (axis) {
    TasteLetterAxis.aroma ||
    TasteLetterAxis.weight => AppTextStyles.homeLettersOverviewOlive,
    TasteLetterAxis.sweetness ||
    TasteLetterAxis.finish => AppTextStyles.homeLettersOverviewWine,
  };

  static const _placeholderStatement = TextSpan(
    style: AppTextStyles.homeLettersOverviewStatement,
    children: <InlineSpan>[
      TextSpan(text: '부드럽게 스며들고', style: AppTextStyles.homeLettersOverviewWine),
      TextSpan(text: '\n'),
      TextSpan(text: '은은하게 남는', style: AppTextStyles.homeLettersOverviewOlive),
      TextSpan(text: ' 술이 편해요.'),
    ],
  );
}

/// The meaning card content for one revealed axis.
LetterMeaning meaningForAxis(TasteLetterAxis axis, TasteLetterPole pole) =>
    LetterMeaning(
      letter: tileForAxis(axis, pole.letter),
      title: pole.label,
      body: pole.body,
    );

/// Both sides of one axis with their shares, and a bar filled from the left
/// by the left side's share: '산뜻함 (Fresh) 75%  ·  풍부함 (Rich) 25%'.
class TasteLetterShareGauge extends StatelessWidget {
  const TasteLetterShareGauge({
    super.key,
    required this.axis,
    required this.state,
  });

  final TasteLetterAxis axis;
  final TasteLetterAxisState state;

  static String sideText(String letter, int share) =>
      '${TasteLetterPole.of(letter)?.shareName ?? letter} $share%';

  @override
  Widget build(BuildContext context) {
    final fill = tileForAxis(axis, state.letter ?? axis.leftLetter).color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                sideText(axis.leftLetter, state.leftShare),
                style: AppTextStyles.homeLetterMeaningBody,
              ),
            ),
            Text(
              sideText(axis.rightLetter, state.rightShare),
              style: AppTextStyles.homeLetterMeaningBody,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  flex: state.leftShare,
                  child: ColoredBox(color: fill),
                ),
                Expanded(
                  flex: 100 - state.leftShare,
                  child: const ColoredBox(color: AppColors.borderSubtle),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class LetterMeaningPanel extends StatelessWidget {
  const LetterMeaningPanel({super.key, required this.meaning, this.share});

  final LetterMeaning meaning;

  /// The share gauge under the tags; the placeholder has none.
  final Widget? share;

  @override
  Widget build(BuildContext context) => AppPanel(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FramedLetterTile(
          letter: meaning.letter,
          width: 56,
          height: 62,
          fontSize: 27,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                meaning.title,
                style: AppTextStyles.homeLetterMeaningTitle(
                  meaning.letter.color,
                ),
              ),
              const SizedBox(height: 9),
              Text(meaning.body, style: AppTextStyles.homeLetterMeaningBody),
              if (share case final share?) ...<Widget>[
                const SizedBox(height: 12),
                share,
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// The section line above the closed slots.
String hiddenSectionDescription(int count) => count == 1
    ? '마지막 한 조각이 채워지면 나의 취향 조각이 모두 완성돼요.'
    : '남은 $count조각이 채워지면 나의 취향 조각이 모두 완성돼요.';

/// One closed slot: the ? tile, the axis name, what is still unknown and
/// what to record next.
class HiddenAxisPanel extends StatelessWidget {
  const HiddenAxisPanel({super.key, required this.axis, this.tileKey});

  final TasteLetterAxis axis;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) => AppPanel(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
    child: Column(
      children: <Widget>[
        _FramedLetterTile(
          key: tileKey,
          letter: unknownLetter,
          width: 56,
          height: 62,
          fontSize: 27,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(axis.hiddenCaption, style: AppTextStyles.body),
        const SizedBox(height: AppSpacing.md),
        Text(
          axis.hiddenBody,
          textAlign: TextAlign.center,
          style: AppTextStyles.homeLetterMeaningBody,
        ),
      ],
    ),
  );
}

/// The moments a letter appeared or flipped, newest first, each on its own
/// card. With [limit] only the newest few show and a link opens the whole
/// journey. A moment whose record still has its card opens it on a tap.
class TasteLetterChangeList extends StatelessWidget {
  const TasteLetterChangeList({
    super.key,
    required this.changes,
    this.limit,
    this.onShowAll,
    this.onOpenCard,
  });

  /// Oldest first, as the gateway returns them.
  final List<TasteLetterChange> changes;
  final int? limit;
  final VoidCallback? onShowAll;
  final ValueChanged<String>? onOpenCard;

  static const showAllLabel = '내 취향 여정 전체보기';

  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty) {
      return const AppPanel(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Text(
          '아직 조각이 바뀐 적은 없어요. 기록이 쌓이면 여기에 남아요.',
          style: AppTextStyles.body,
        ),
      );
    }
    final newestFirst = changes.reversed.toList();
    final shown = limit == null ? newestFirst : newestFirst.take(limit!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, change) in shown.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: AppSpacing.md),
          AppPanel(
            key: ValueKey<String>('letter-change-$index'),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            onPressed: switch ((change.resultId, onOpenCard)) {
              (final id?, final open?) => () => open(id),
              _ => null,
            },
            child: _ChangeRow(change: change, opens: onOpenCard != null),
          ),
        ],
        if (onShowAll != null && shown.length < newestFirst.length) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Align(
            alignment: Alignment.centerRight,
            child: AppSectionAction(label: showAllLabel, onPressed: onShowAll),
          ),
        ],
      ],
    );
  }
}

/// The whole journey, newest first, in a sheet over the detail. Opening a
/// moment's card closes the sheet first.
Future<void> showTasteLetterJourneySheet(
  BuildContext context,
  List<TasteLetterChange> changes, {
  ValueChanged<String>? onOpenCard,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.surfaceCanvas,
  builder: (context) => FractionallySizedBox(
    heightFactor: .9,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenX,
            AppSpacing.xl,
            AppSpacing.screenX,
            AppSpacing.md,
          ),
          child: const Text('내 취향 여정', style: AppTextStyles.sectionTitle),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenX,
              AppSpacing.sm,
              AppSpacing.screenX,
              AppSpacing.xxl,
            ),
            child: TasteLetterChangeList(
              changes: changes,
              onOpenCard: onOpenCard == null
                  ? null
                  : (resultId) {
                      Navigator.of(context).pop();
                      onOpenCard(resultId);
                    },
            ),
          ),
        ),
      ],
    ),
  ),
);

/// One moment: date and kind tag, the bottle, then the tiles that moved
/// (from → to, or the single tile that first appeared) with a short quote.
class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change, required this.opens});

  final TasteLetterChange change;

  /// Whether the list opens cards; then a name with a card reads as a link.
  final bool opens;

  @override
  Widget build(BuildContext context) {
    final axis = change.axis;
    final tone = switch (axis) {
      TasteLetterAxis.aroma || TasteLetterAxis.weight => AppChipTone.olive,
      TasteLetterAxis.sweetness || TasteLetterAxis.finish => AppChipTone.brand,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tileForAxis(axis, change.toLetter).color,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              formatChangeDate(change.changedAt),
              style: AppTextStyles.homeLetterMeaningBody,
            ),
            const SizedBox(width: AppSpacing.sm),
            AppChip(
              label: change.kindLabel,
              size: AppChipSize.compact,
              variant: AppChipVariant.flat,
              tone: tone,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                change.productName,
                style: opens && change.resultId != null
                    ? AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.actionPrimary,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.actionPrimary,
                      )
                    : AppTextStyles.body,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  if (change.fromLetter case final from?) ...<Widget>[
                    _MomentTile(letter: tileForAxis(axis, from)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: AppIcon(
                        AppIconAsset.next,
                        size: 13,
                        color: AppColors.homeLetterUnknown,
                      ),
                    ),
                  ],
                  _MomentTile(letter: tileForAxis(axis, change.toLetter)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '“${change.quote}”',
                      style: AppTextStyles.homeLetterMeaningBody,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MomentTile extends StatelessWidget {
  const _MomentTile({required this.letter});

  final SoolgyulLetter letter;

  @override
  Widget build(BuildContext context) =>
      _FramedLetterTile(letter: letter, width: 30, height: 32, fontSize: 15);
}

/// 'yyyy.MM.dd' without an intl dependency.
String formatChangeDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}.${two(date.month)}.${two(date.day)}';
}

class _FramedLetterTile extends StatelessWidget {
  const _FramedLetterTile({
    super.key,
    required this.letter,
    required this.width,
    required this.height,
    required this.fontSize,
  });

  final SoolgyulLetter letter;
  final double width;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      boxShadow: AppShadows.homeLetterTile,
    ),
    clipBehavior: Clip.antiAlias,
    child: SoolgyulLetterTile(letter: letter, fontSize: fontSize),
  );
}
