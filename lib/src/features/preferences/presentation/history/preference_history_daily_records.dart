import '../../../../widgets/app_icon_button.dart';
import '../../../../widgets/drink_photo_placeholder.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../design/app_feature_layouts.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_chip.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_surface.dart';
import '../../../../widgets/app_term_tooltip.dart';
import '../../data/preference_history_content.dart';
import '../../../../widgets/app_network_image.dart';

class HistoryDayCard extends StatefulWidget {
  const HistoryDayCard({
    required this.title,
    required this.records,
    required this.onOpenCard,
    super.key,
  });

  final String title;
  final List<HistoryRecord> records;

  /// Opens the saved card of a tapped record by its result id.
  final ValueChanged<String> onOpenCard;

  @override
  State<HistoryDayCard> createState() => _HistoryDayCardState();
}

class _HistoryDayCardState extends State<HistoryDayCard> {
  late final PageController _pageController;

  /// Records whose card line is unfolded past three lines.
  final _unfolded = <String>{};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: .84);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precachePhotos();
  }

  @override
  void didUpdateWidget(HistoryDayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) _precachePhotos();
  }

  /// The carousel builds only the cards in view; every other bottle's photo
  /// downloads now, so a swipe does not wait for one.
  void _precachePhotos() {
    for (final record in widget.records) {
      if (record.imageUrl case final url?) {
        precacheImage(networkImageProvider(url), context, onError: (_, _) {});
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggle(String resultId) => setState(() {
    if (!_unfolded.remove(resultId)) _unfolded.add(resultId);
  });

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey<String>('history-day-card-section'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.sectionTitle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '총 ${widget.records.length}개',
              textScaler: TextScaler.noScaling,
              style: AppTextStyles.historyRecordMeta,
            ),
          ],
        ),
        const SizedBox(height: PreferenceLayoutSpacing.sectionToContent),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth * .84 - AppSpacing.sm;
            final scaler = MediaQuery.textScalerOf(context);
            final style = _HistoryRecordSummary.drawnStyle(context);
            final textWidth = cardWidth - _HistoryRecordSlide.padding * 2;
            // Every card is as tall as one whose line takes three lines and
            // whose chips take as many rows as the most of the day's; an
            // unfolded card stretches the carousel by its extra lines.
            final chipStyle = DefaultTextStyle.of(
              context,
            ).style.merge(_HistoryRecordSlide.chipStyle);
            var chipRows = 1;
            var extraLines = 0;
            for (final record in widget.records) {
              chipRows = math.max(
                chipRows,
                _HistoryRecordSlide.chipRows(
                  record.tags,
                  textWidth,
                  scaler,
                  chipStyle,
                ),
              );
              final summary = record.summary;
              if (summary == null || !_unfolded.contains(record.resultId)) {
                continue;
              }
              final lines = _HistoryRecordSummary.unfoldedLines(
                summary,
                textWidth,
                scaler,
                style,
              );
              extraLines = math.max(extraLines, lines - _summaryMaxLines);
            }
            return AnimatedContainer(
              duration: AppDurations.standard,
              curve: Curves.easeOutCubic,
              height:
                  _HistoryRecordSlide.height(cardWidth, scaler, chipRows) +
                  extraLines * _HistoryRecordSummary.lineHeight(scaler),
              child: PageView.builder(
                key: const ValueKey<String>('history-day-carousel'),
                controller: _pageController,
                clipBehavior: Clip.none,
                padEnds: false,
                itemCount: widget.records.length,
                itemBuilder: (context, index) {
                  final record = widget.records[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _HistoryRecordSlide(
                      record: record,
                      unfolded: _unfolded.contains(record.resultId),
                      onToggle: () => _toggle(record.resultId),
                      onTap: () => widget.onOpenCard(record.resultId),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    ),
  );
}

/// The card's line shows this many lines before it folds.
const _summaryMaxLines = 3;

class _HistoryRecordSlide extends StatelessWidget {
  const _HistoryRecordSlide({
    required this.record,
    required this.unfolded,
    required this.onToggle,
    required this.onTap,
  });

  final HistoryRecord record;
  final bool unfolded;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  static const padding = AppSpacing.lg;
  static const _imageAspect = 708 / 459;
  static const _chipHeight = 28.0;

  /// The compact chip's name, as [AppChip] draws it.
  static final chipStyle = AppTextStyles.labelSmall.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );
  static const _chipPadding = 10.0;
  static const _chipSpacing = AppSpacing.sm;
  static const _chipRunSpacing = AppSpacing.xs;

  /// How many rows [tags] wrap into across [width], as the card's [Wrap]
  /// lays them out; at least one.
  static int chipRows(
    List<HistoryTag> tags,
    double width,
    TextScaler scaler,
    TextStyle style,
  ) {
    var rows = 1;
    var used = 0.0;
    for (final tag in tags) {
      final painter = TextPainter(
        text: TextSpan(text: tag.label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final chip = math.min(painter.width + _chipPadding * 2, width);
      painter.dispose();
      if (used > 0 && used + _chipSpacing + chip > width) {
        rows += 1;
        used = chip;
      } else {
        used += (used > 0 ? _chipSpacing : 0) + chip;
      }
    }
    return rows;
  }

  /// A card whose line takes three lines: photo, name, meta, [chipRows] rows
  /// of chips and the line, measured at the reader's text size.
  static double height(double cardWidth, TextScaler scaler, int chipRows) {
    double line(TextStyle style) =>
        scaler.scale(style.fontSize!) * (style.height ?? 1);
    final imageHeight = (cardWidth - padding * 2) / _imageAspect;
    final chipRow = math.max(_chipHeight, scaler.scale(11) * 1.4 + 12);
    return padding +
        imageHeight +
        AppSpacing.lg +
        line(AppTextStyles.sectionTitle) +
        5 +
        line(AppTextStyles.historyRecordMeta) +
        AppSpacing.md +
        chipRow * chipRows +
        _chipRunSpacing * (chipRows - 1) +
        AppSpacing.md +
        _HistoryRecordSummary.lineHeight(scaler) * _summaryMaxLines +
        padding +
        // The surface's border and the text's pixel rounding.
        6;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${record.title} 술결 카드 열기',
    child: GestureDetector(
      key: ValueKey<String>('history-record-${record.resultId}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AppSurface(
        variant: AppSurfaceVariant.card,
        borderRadius: AppRadii.compactCard,
        padding: const EdgeInsets.all(padding),
        // While the carousel grows to an unfolded line, the slide's content
        // is already its full height; it is clipped until the card catches up.
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: double.infinity,
            child: _slideContent(),
          ),
        ),
      ),
    ),
  );

  Widget _slideContent() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Stack(
        children: <Widget>[
          _HistoryRecordImage(record: record),
          if (record.note case final note?)
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: _HistoryNoteButton(resultId: record.resultId, note: note),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      _HistoryRecordDetails(
        record: record,
        unfolded: unfolded,
        onToggle: onToggle,
      ),
    ],
  );
}

/// The bottle's catalog photo, or the category colour when there is none.
class _HistoryRecordImage extends StatelessWidget {
  const _HistoryRecordImage({required this.record});

  final HistoryRecord record;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: AppColors.surfaceCanvas,
      child: DrinkPhotoPlaceholder(),
    );
    final url = record.imageUrl;
    return AspectRatio(
      aspectRatio: _HistoryRecordSlide._imageAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: url == null
            ? placeholder
            : ColoredBox(
                color: AppColors.surfaceCanvas,
                child: Image(
                  image: networkImageProvider(url),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => placeholder,
                ),
              ),
      ),
    );
  }
}

/// The reader's note, kept off the card: a mark in the photo's corner that
/// opens the note in the same balloon as a term's explanation.
class _HistoryNoteButton extends StatelessWidget {
  const _HistoryNoteButton({required this.resultId, required this.note});

  final String resultId;
  final String note;

  @override
  Widget build(BuildContext context) => AppIconButton(
    key: ValueKey<String>('history-record-note-$resultId'),
    icon: AppIconAsset.memo,
    tooltip: '메모 보기',
    onPressed: () => showTermTooltip(context, title: '남긴 메모', text: note),
    variant: AppIconButtonVariant.floating,
    size: AppIconButtonSize.small,
    tone: AppIconButtonTone.accent,
  );
}

class _HistoryRecordDetails extends StatelessWidget {
  const _HistoryRecordDetails({
    required this.record,
    required this.unfolded,
    required this.onToggle,
  });

  final HistoryRecord record;
  final bool unfolded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        record.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.sectionTitle,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        record.meta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.historyRecordMeta,
      ),
      const SizedBox(height: AppSpacing.md),
      if (record.tags.isNotEmpty)
        Wrap(
          spacing: _HistoryRecordSlide._chipSpacing,
          runSpacing: _HistoryRecordSlide._chipRunSpacing,
          children: <Widget>[
            for (final tag in record.tags)
              AppChip(
                key: ValueKey<String>('history-record-tag-${tag.label}'),
                label: tag.label,
                variant: AppChipVariant.flat,
                size: AppChipSize.compact,
                tone: AppChipTone.warm,
              ),
          ],
        ),
      if (record.summary case final summary?) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        _HistoryRecordSummary(
          text: summary,
          unfolded: unfolded,
          onToggle: onToggle,
        ),
      ],
    ],
  );
}

/// The card's line: three lines, then "… 더보기" that unfolds the rest in
/// place and "접기" that folds it back. A line that fits is plain text, so
/// a tap on it opens the card like the rest of the slide.
class _HistoryRecordSummary extends StatelessWidget {
  const _HistoryRecordSummary({
    required this.text,
    required this.unfolded,
    required this.onToggle,
  });

  final String text;
  final bool unfolded;
  final VoidCallback onToggle;

  static const _style = AppTextStyles.detail;

  /// The line's style as [Text] draws it: merged over the inherited style,
  /// which brings the app's font. Measuring with the bare style would lay
  /// the text out in the platform font and miscount the lines.
  static TextStyle drawnStyle(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(_style);
  static const _more = '더 보기';
  static const _less = '접기';
  static TextStyle _action(TextStyle style) => style.copyWith(
    fontWeight: FontWeight.w700,
    color: AppColors.textWarmTertiary,
  );

  static double lineHeight(TextScaler scaler) =>
      scaler.scale(_style.fontSize!) * _style.height!;

  /// How many lines the unfolded line takes, "접기" included.
  static int unfoldedLines(
    String text,
    double width,
    TextScaler scaler,
    TextStyle style,
  ) {
    final painter = _painter(_unfolded(text, style), scaler)
      ..layout(maxWidth: width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines;
  }

  static TextPainter _painter(InlineSpan span, TextScaler scaler, {int? max}) =>
      TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: max,
      );

  static bool _fits(InlineSpan span, double width, TextScaler scaler) {
    final painter = _painter(span, scaler, max: _summaryMaxLines)
      ..layout(maxWidth: width);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    return fits;
  }

  /// The longest head of [text] that leaves room for "… 더보기" on the
  /// third line.
  static String _foldedHead(
    String text,
    double width,
    TextScaler scaler,
    TextStyle style,
  ) {
    final chars = text.characters.toList();
    var low = 0;
    var high = chars.length;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      final head = chars.take(mid).join().trimRight();
      if (_fits(_folded(head, style), width, scaler)) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return chars.take(low).join().trimRight();
  }

  static TextSpan _folded(String head, TextStyle style) => TextSpan(
    text: '$head… ',
    style: style,
    children: <InlineSpan>[TextSpan(text: _more, style: _action(style))],
  );

  static TextSpan _unfolded(String text, TextStyle style) => TextSpan(
    text: '$text  ',
    style: style,
    children: <InlineSpan>[TextSpan(text: _less, style: _action(style))],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final style = drawnStyle(context);
      final width = constraints.maxWidth;
      if (_fits(TextSpan(text: text, style: style), width, scaler)) {
        return Text(
          text,
          key: const ValueKey<String>('history-record-summary'),
          style: _style,
        );
      }
      final span = unfolded
          ? _unfolded(text, style)
          : _folded(_foldedHead(text, width, scaler, style), style);
      return Semantics(
        button: true,
        label: unfolded ? '내용 접기' : '내용 더보기',
        child: GestureDetector(
          key: const ValueKey<String>('history-record-summary-toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Text.rich(
            span,
            key: const ValueKey<String>('history-record-summary'),
          ),
        ),
      );
    },
  );
}
