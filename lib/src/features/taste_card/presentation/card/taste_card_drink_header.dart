part of '../taste_card_screen.dart';

/// 준마이 긴조 · 15% · 2026.11.10: the style (the category when the card has
/// none), the ABV, and the record date in the reader's own time zone. The
/// card's header and the head of its tasting note both write it.
String _drinkFactsLine(TasteCardProductViewData product, DateTime? recordedAt) {
  final date = recordedAt?.toLocal();
  final abv = product.abvPercent;
  return <String>[
    ?(product.styleLabel ?? product.categoryLabel),
    if (abv != null) formatAbv(abv),
    if (date != null) formatDotDate(date),
  ].join(' · ');
}

/// The catalog photo's address; other sources show no photo.
String? _catalogPhotoUrl(TasteCardProductViewData product) =>
    switch (product.imageReference) {
      TasteCardImageReference(
        source: TasteCardImageSource.catalog,
        :final reference,
      ) =>
        reference,
      _ => null,
    };

/// The drink the card is about, at the top of the summary box: its catalog
/// photo when it has one, its name, then its style, ABV and the record date,
/// and on an app record its 구매 정보.
class _DrinkHeader extends StatelessWidget {
  const _DrinkHeader({
    required this.product,
    required this.recordedAt,
    this.recordPrice,
  });

  final TasteCardProductViewData product;
  final DateTime? recordedAt;

  /// The record's price; null leaves the price line out, as on the web.
  final RecordPriceEditor? recordPrice;

  @override
  Widget build(BuildContext context) {
    final photoUrl = _catalogPhotoUrl(product);
    final facts = _drinkFactsLine(product, recordedAt);
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
                if (recordPrice case final editor?)
                  _DrinkPriceLine(editor: editor),
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

/// 구매 정보 : 38,000원 · 와인샵, once the price has been read and when the
/// record has one; it is written on the 테이스팅 노트's form.
class _DrinkPriceLine extends StatelessWidget {
  const _DrinkPriceLine({required this.editor});

  final RecordPriceEditor editor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) => switch (editor.price) {
      final price? when editor.settled => Text(
        price.line,
        key: const ValueKey<String>('taste-card-price'),
        style: _DrinkHeaderText.category,
      ),
      _ => const SizedBox.shrink(),
    },
  );
}
