import 'package:flutter/material.dart';

import '../../../../design/app_typography.dart';
import '../../../../widgets/paper_box.dart';
import '../../data/taste_fit_verdict.dart';

/// The verdict on the 한지 note: the one short sentence, then the hashtag
/// chips that carry the specifics, in the same ink as the 술결카드. The headline sits by the product name,
/// above the card.
class TasteFitPaperCard extends StatelessWidget {
  const TasteFitPaperCard({required this.verdict, super.key});

  final TasteFitVerdict verdict;

  @override
  Widget build(BuildContext context) {
    return PaperBox(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (verdict.sentence.isNotEmpty)
            Text(
              verdict.sentence,
              style: const AppTextStyle(
                fontSize: 15,
                height: 1.75,
                color: PaperInk.inkSoft,
              ),
            ),
          if (verdict.tags.isNotEmpty) ...<Widget>[
            if (verdict.sentence.isNotEmpty) const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[for (final tag in verdict.tags) _TagChip(tag)],
            ),
          ],
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.tag);

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      decoration: BoxDecoration(
        color: PaperInk.chip,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tag,
        style: const AppTextStyle(
          fontSize: 13,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: PaperInk.grey,
        ),
      ),
    );
  }
}
