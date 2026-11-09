import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_surface.dart';
import '../../data/preference_history_content.dart';

/// The month at a glance: its review in one line.
class HistoryMonthSummaryCard extends StatelessWidget {
  const HistoryMonthSummaryCard({
    required this.month,
    required this.records,
    required this.today,
    super.key,
  });

  final DateTime month;
  final List<HistoryRecord> records;

  /// Tells a running month from a finished one.
  final DateTime today;

  @override
  Widget build(BuildContext context) => AppSurface(
    variant: AppSurfaceVariant.card,
    backgroundImage: const DecorationImage(
      image: AssetImage(
        'assets/component_assets/preference_footprint/'
        'insight_paper_hanji_v2.webp',
      ),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
    ),
    borderRadius: AppRadii.compactCard,
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            '${month.month}월 한눈에 보기',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.sectionTitle,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1, color: Color(0xFFE3CEAA)),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          historyMonthSummaryLine(month, records, today: today),
          key: const ValueKey<String>('history-month-summary'),
          style: AppTextStyles.historySummaryBody.copyWith(height: 1.9),
        ),
      ],
    ),
  );
}
