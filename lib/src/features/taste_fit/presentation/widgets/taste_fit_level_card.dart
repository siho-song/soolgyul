import '../../../../core/sensory/sensory_gauges.dart';
import '../../../../design/app_tokens.dart';
import 'package:flutter/material.dart';

import '../../../../widgets/app_surface.dart';
import '../../../../widgets/step_scale.dart';

/// The bottle's levels in their own white box, drawn as the 테이스팅 노트
/// draws a record's: each on the gauge the sheet
/// (`catalog/sensory/gauge-definitions.json`) gives the drink's kind, under
/// that gauge's name and end words, in the sheet's order.
class TasteFitLevelCard extends StatelessWidget {
  const TasteFitLevelCard({
    required this.levels,
    required this.sheet,
    this.categoryKey,
    this.styleKey,
    super.key,
  });

  /// The bottle's levels, 1 to 5, by the catalog's name for each.
  final Map<String, int> levels;
  final SensoryGaugeDefinitions sheet;

  /// The drink's 주종 and kind, which choose its gauges.
  final String? categoryKey;
  final String? styleKey;

  /// The gauge axis each level a bottle carries is read on, in the order
  /// the catalog lists them: it calls 탄닌 astringency and 탄산
  /// carbonation.
  static const Map<String, String> axisOfLevel = <String, String>{
    'sweetness': 'sweetness',
    'acidity': 'acidity',
    'astringency': 'tannin',
    'body': 'body',
    'carbonation': 'sparkling',
    'finish_length': 'finish_length',
  };

  /// The rows drawn: the gauges the drink's kind is asked, in the sheet's
  /// order, for which the bottle has a level; a gauge without one is not
  /// listed, as the note lists no gauge left unanswered. A level the bottle
  /// has on an axis its kind is not asked (a white wine's 탄닌, a whisky's
  /// 산미) is not drawn: the page shows what a record of the drink would.
  List<StepGaugeRow> get rows {
    final levelOf = <String, int>{
      for (final MapEntry(key: name, value: level) in levels.entries)
        ?axisOfLevel[name]: level.clamp(1, 5),
    };
    final asked = sheet.forDrink(categoryKey, styleKey);
    return <StepGaugeRow>[
      for (final gauge in asked.palate.followedBy(asked.finish))
        if (levelOf[gauge.axis] case final level?)
          (label: gauge.label, level: level, ends: gauge.ends),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = this.rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xxl,
      ),
      child: StepGaugeRows(keyPrefix: 'taste-fit-level-', rows: rows),
    );
  }
}
