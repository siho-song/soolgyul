part of '../taste_card_screen.dart';

/// The drink the card is about, at the top of the summary box: its catalog
/// photo when it has one, its name, then its style, ABV and the record date.
class _DrinkHeader extends StatelessWidget {
  const _DrinkHeader({required this.product, required this.recordedAt});

  final TasteCardProductViewData product;
  final DateTime? recordedAt;

  /// 준마이 긴조 · 15% · 2026.11.10: the style (the category when the card
  /// has none), the ABV, and the date in the reader's own time zone.
  String get _facts {
    final date = recordedAt?.toLocal();
    final abv = product.abvPercent;
    return <String>[
      ?(product.styleLabel ?? product.categoryLabel),
      if (abv != null) '${abv % 1 == 0 ? abv.toInt() : abv}%',
      if (date != null) formatDotDate(date),
    ].join(' · ');
  }

  /// The catalog photo's address; other sources show no photo.
  String? get _photoUrl => switch (product.imageReference) {
    TasteCardImageReference(
      source: TasteCardImageSource.catalog,
      :final reference,
    ) =>
      reference,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final photoUrl = _photoUrl;
    final facts = _facts;
    return KeyedSubtree(
      key: const ValueKey<String>('taste-card-drink'),
      child: Row(
        children: <Widget>[
          if (photoUrl != null) ...<Widget>[
            DrinkResultPhoto(url: photoUrl, selected: false, size: 48),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  product.drinkNameSnapshot,
                  key: const ValueKey<String>('taste-card-drink-name'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _DrinkHeaderText.name,
                ),
                if (facts.isNotEmpty)
                  Text(
                    facts,
                    key: const ValueKey<String>('taste-card-drink-facts'),
                    style: _DrinkHeaderText.category,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

abstract final class _DrinkHeaderText {
  static const name = AppTextStyle(
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: _TasteCardColors.ink,
  );
  static const category = AppTextStyle(
    fontSize: 13,
    height: 1.5,
    color: _TasteCardColors.inkSoft,
  );
}
