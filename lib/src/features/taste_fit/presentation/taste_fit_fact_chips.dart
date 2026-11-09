import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../widgets/app_chip.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_term_tooltip.dart';
import '../taste_fit_verdict.dart';

/// Producer, grape, region and process as chips under the product name. A
/// chip with an explanation carries an ⓘ mark and opens the explanation in a
/// balloon whose tail points at the chip; the chip stays filled while the
/// balloon is open. A chip without an explanation stays plain.
class TasteFitFactChips extends StatefulWidget {
  const TasteFitFactChips({required this.facts, super.key});

  final List<TasteFitFact> facts;

  static String kindLabel(String kind) => switch (kind) {
    'producer' => '생산자',
    'grape' => '품종',
    'region' => '산지',
    'process' => '만드는 방식',
    _ => '정보',
  };

  @override
  State<TasteFitFactChips> createState() => _TasteFitFactChipsState();
}

class _TasteFitFactChipsState extends State<TasteFitFactChips> {
  TasteFitFact? _open;

  Future<void> _show(BuildContext chipContext, TasteFitFact fact) async {
    setState(() => _open = fact);
    await showTermTooltip(
      chipContext,
      title: fact.label,
      kind: TasteFitFactChips.kindLabel(fact.kind),
      text: fact.description!,
    );
    if (mounted) setState(() => _open = null);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.facts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        for (final fact in widget.facts)
          Builder(
            key: ValueKey<String>('taste-fit-fact-${fact.kind}-${fact.label}'),
            builder: (chipContext) {
              final open = identical(_open, fact);
              return AppChip(
                label: fact.label,
                variant: AppChipVariant.outline,
                size: AppChipSize.compact,
                tone: open ? AppChipTone.brand : AppChipTone.neutral,
                selected: open,
                trailingIcon: fact.description == null
                    ? null
                    : AppIconAsset.info,
                onPressed: fact.description == null
                    ? null
                    : () => _show(chipContext, fact),
              );
            },
          ),
      ],
    );
  }
}
