import '../../../../widgets/app_icon_button.dart';
import '../../../../widgets/drink_photo_placeholder.dart';
import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_surface.dart';
import '../../../../widgets/app_term_tooltip.dart';
import '../../data/liked_cards_gateway.dart';
import '../../../../core/format/dates.dart';
import '../../data/profile_setup_draft.dart';
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
                      top: 0,
                      left: 0,
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
                      Row(
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
                              DrinkInterest.values
                                      .where(
                                        (interest) =>
                                            interest.wireKey == record.category,
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
                            _NoteButton(recordId: record.id, note: note),
                        ],
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

/// The filled heart on the photo's corner; a tap takes the like back.
class _UnlikeButton extends StatelessWidget {
  const _UnlikeButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xs),
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

/// The reader's note, as on the 취향 tab: a mark that opens the note in the
/// same balloon as a term's explanation.
class _NoteButton extends StatelessWidget {
  const _NoteButton({required this.recordId, required this.note});

  final String recordId;
  final String note;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '메모 보기',
    child: GestureDetector(
      key: ValueKey<String>('liked-card-note-$recordId'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showTermTooltip(context, title: '남긴 메모', text: note),
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
