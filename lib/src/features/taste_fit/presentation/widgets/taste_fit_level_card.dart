import 'package:flutter/material.dart';

import '../../../../widgets/level_gauge.dart';
import '../../../../widgets/paper_box.dart';

/// The bottle's levels on their own 한지 note, one gauge per row in the
/// contract's key order, drawn with the 술결카드 gauge.
class TasteFitLevelCard extends StatelessWidget {
  const TasteFitLevelCard({required this.levels, super.key});

  final Map<String, int> levels;

  static const List<String> keyOrder = <String>[
    'sweetness',
    'acidity',
    'astringency',
    'body',
    'carbonation',
    'finish_length',
  ];

  static const Map<String, String> labels = <String, String>{
    'sweetness': '단맛',
    'acidity': '산미',
    'astringency': '떫음',
    'body': '무게감',
    'carbonation': '탄산',
    'finish_length': '여운',
  };

  /// The two end words of each gauge.
  static const Map<String, (String, String)> ends = <String, (String, String)>{
    'sweetness': ('낮음', '높음'),
    'acidity': ('낮음', '높음'),
    'astringency': ('약함', '강함'),
    'carbonation': ('약함', '강함'),
    'body': ('가벼움', '무거움'),
    'finish_length': ('짧음', '김'),
  };

  @override
  Widget build(BuildContext context) {
    final keys = keyOrder.where(levels.containsKey).toList(growable: false);
    if (keys.isEmpty) return const SizedBox.shrink();
    return PaperBox(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final key in keys) ...<Widget>[
            if (key != keys.first) const SizedBox(height: 10),
            LevelGauge(
              label: labels[key]!,
              mark: levels[key]!,
              low: ends[key]!.$1,
              high: ends[key]!.$2,
            ),
          ],
        ],
      ),
    );
  }
}
