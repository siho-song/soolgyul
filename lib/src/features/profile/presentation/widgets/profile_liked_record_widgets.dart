import '../../../../core/catalog/drink_type.dart';
import '../../../../widgets/app_icon_button.dart';
import '../../../../widgets/drink_photo_placeholder.dart';
import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_surface.dart';
import '../../../../widgets/app_tap_slop.dart';
import '../../../../widgets/app_term_tooltip.dart';
import '../../data/liked_cards_gateway.dart';
import '../../../../core/format/dates.dart';
import '../../../../widgets/app_network_image.dart';

/// One liked card in 저장한 술결 카드: the bottle's photo with the unlike heart
/// in its corner, then the name in up to two lines and the card's one line in
/// up to three, and the date and kind under them. The whole card opens the
/// 술결 카드.
class LikedRecordCard extends StatelessWidget {
  const LikedRecordCard({
    required this.record,
    required this.onUnlike,
    this.onOpen,
    super.key,
  });

  final LikedCard record;
  final VoidCallback? onUnlike;

  /// `null` for a record without a card.
  final VoidCallback? onOpen;

  /// Fits two title lines and three summary lines at the normal text size;
  /// a larger text size shows fewer summary lines instead of overflowing.
  static const _height = 144.0;
  static const _imageWidth = 100.0;
  static const _compactImageWidth = 88.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 330;
      final metaStyle = AppTextStyles.caption.copyWith(
        fontSize: compact ? 8.5 : 9.5,
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w700,
      );
      return AppPanel(
        padding: const EdgeInsets.all(AppSpacing.s6),
        onPressed: onOpen,
        semanticLabel: onOpen == null ? null : '${record.title} 술결 카드 열기',
        child: SizedBox(
          height: _height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: compact ? _compactImageWidth : _imageWidth,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: ColoredBox(
                        color: AppColors.surfaceCanvas,
                        child: record.imageUrl == null
                            ? const DrinkPhotoPlaceholder()
                            : Image(
                                image: networkImageProvider(record.imageUrl!),
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const DrinkPhotoPlaceholder(),
                              ),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.xs,
                      left: AppSpacing.xs,
                      child: _UnlikeButton(onPressed: onUnlike),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? AppSpacing.sm : AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    AppSpacing.s10,
                    AppSpacing.s6,
                    AppSpacing.s6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // The name and the line take the space above the date
                      // row; the line gives way first on a large text size.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              record.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.cardTitle.copyWith(
                                fontSize: 12,
                                height: 1.25,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (record.summary case final summary?) ...<Widget>[
                              const SizedBox(height: AppSpacing.sm),
                              Flexible(
                                child: Text(
                                  summary,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body.copyWith(
                                    fontSize: compact ? 10 : 11,
                                    height: 1.6,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // The memo mark is small: a tap up to a tap target
                      // above this row, or left of the mark, lands on it.
                      AppTapSlop(
                        slop: const EdgeInsets.only(top: _noteSlopTop),
                        along: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.calendar_month_outlined,
                              size: AppSizes.iconXs,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                formatDotDate(record.recordedAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                              ),
                              child: Text('|', style: metaStyle),
                            ),
                            const Icon(
                              Icons.sell_outlined,
                              size: AppSizes.iconXs,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                DrinkType.values
                                        .where(
                                          (interest) =>
                                              interest.key == record.category,
                                        )
                                        .firstOrNull
                                        ?.label ??
                                    '기타',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ),
                            if (record.note case final note?)
                              AppTapSlop(
                                slop: const EdgeInsets.only(
                                  left: _noteSlopLeft,
                                ),
                                child: _NoteButton(
                                  recordId: record.id,
                                  note: note,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// What the memo mark (an icon of [AppSizes.iconXs] after a gap of
/// [AppSpacing.sm]) lacks of a tap target, to its left and above its row.
const _noteSlopLeft =
    AppSizes.minimumTapTarget - AppSizes.iconXs - AppSpacing.sm;
const _noteSlopTop = AppSizes.minimumTapTarget - AppSizes.iconXs;

/// The filled heart on the photo's corner; a tap takes the like back.
class _UnlikeButton extends StatelessWidget {
  const _UnlikeButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppTapSlop(
    // Up to the photo's corner on one side, a full tap target on the other.
    slop: const EdgeInsets.fromLTRB(
      AppSpacing.xs,
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.sm,
    ),
    child: AppIconButton(
      onPressed: onPressed,
      tooltip: '보관 취소',
      variant: AppIconButtonVariant.floating,
      size: AppIconButtonSize.small,
      child: const Icon(
        Icons.favorite_rounded,
        size: AppSizes.iconSm,
        color: AppColors.actionPrimary,
      ),
    ),
  );
}

/// The reader's 총평, as on the 취향 tab: a mark that opens it in the same
/// balloon as a term's explanation.
class _NoteButton extends StatelessWidget {
  const _NoteButton({required this.recordId, required this.note});

  final String recordId;
  final String note;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '총평 보기',
    child: GestureDetector(
      key: ValueKey<String>('liked-card-note-$recordId'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showTermTooltip(context, title: '총평', text: note),
      child: const Padding(
        padding: EdgeInsets.only(left: AppSpacing.sm),
        child: AppIcon(
          AppIconAsset.memo,
          size: AppSizes.iconXs,
          color: AppColors.actionPrimary,
        ),
      ),
    ),
  );
}
