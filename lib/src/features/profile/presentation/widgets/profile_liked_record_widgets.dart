import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../data/liked_cards_gateway.dart';
import '../../data/profile_content.dart';
import '../../profile_setup_draft.dart';
import 'profile_collection_chip_widgets.dart';

class LikedRecordCard extends StatelessWidget {
  const LikedRecordCard({
    required this.record,
    required this.onUnlike,
    super.key,
  });

  final LikedCard record;
  final VoidCallback? onUnlike;

  @override
  Widget build(BuildContext context) => ProfileCollectionCard(
    asset: '',
    image: record.imageUrl == null
        ? const Icon(Icons.local_bar_outlined, color: AppColors.textTertiary)
        : Image.network(
            record.imageUrl!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.local_bar_outlined,
              color: AppColors.textTertiary,
            ),
          ),
    title: record.title,
    description: record.description,
    actionIcon: Icons.favorite_rounded,
    actionTooltip: '좋아요 취소',
    onAction: onUnlike,
    footerBuilder: (compact) =>
        _LikedRecordMetadata(record: record, compact: compact),
  );
}

class _LikedRecordMetadata extends StatelessWidget {
  const _LikedRecordMetadata({required this.record, required this.compact});

  final LikedCard record;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const Icon(
        Icons.calendar_month_outlined,
        size: 13,
        color: AppColors.textTertiary,
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(
        formatProfileDate(record.recordedAt),
        style: AppTextStyles.caption.copyWith(
          fontSize: compact ? 8.5 : 9.5,
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w700,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Text(
          '|',
          style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
        ),
      ),
      const Icon(Icons.sell_outlined, size: 13, color: AppColors.textTertiary),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          DrinkInterest.values
                  .where((interest) => interest.wireKey == record.category)
                  .firstOrNull
                  ?.label ??
              '기타',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(
            fontSize: compact ? 8.5 : 9.5,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}
