import '../../../../core/sensory/sensory_gauges.dart';
import '../../../../design/app_tokens.dart';
import 'package:flutter/material.dart';

import '../../../../widgets/paper_box.dart';
import '../../../../widgets/step_scale.dart';

/// The bottle's levels on their own 한지 note, drawn as the 테이스팅 노트
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
  /// 산미) is kept: it follows the kind's own gauges, under the name the
  /// sheet gives that axis.
  List<StepGaugeRow> get rows {
    final levelOf = <String, int>{
      for (final MapEntry(key: name, value: level) in levels.entries)
        ?axisOfLevel[name]: level.clamp(1, 5),
    };
    StepGaugeRow row(SensoryGauge gauge) =>
        (label: gauge.label, level: levelOf[gauge.axis]!, ends: gauge.ends);
    final asked = sheet.forDrink(categoryKey, styleKey);
    final own = <SensoryGauge>[
      for (final gauge in asked.palate.followedBy(asked.finish))
        if (levelOf.containsKey(gauge.axis)) gauge,
    ];
    final ownAxes = {for (final gauge in own) gauge.axis};
    return <StepGaugeRow>[
      for (final gauge in own) row(gauge),
      for (final axis in axisOfLevel.values)
        if (!ownAxes.contains(axis) && levelOf.containsKey(axis))
          if (sheet.gaugeNamed(categoryKey, axis) case final gauge?) row(gauge),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = this.rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    return PaperBox(
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
