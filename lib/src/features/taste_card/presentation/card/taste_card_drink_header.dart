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
      // The price line ends the header, so a tap just under the header is
      // a tap just under the line.
      child: _TapReach(
        below: recordPrice == null ? 0 : _priceTapReach,
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
                    _TapReach(
                      above: _priceTapReach,
                      child: _DrinkPriceLine(editor: editor),
                    ),
                ],
              ),
            ),
          ],
        ),
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
  static final addPrice = category.copyWith(
    fontWeight: FontWeight.w600,
    color: _TasteCardColors.wine,
  );
}

/// 구매 정보 : 38,000원 · 한 병 · 바, which opens the sheet to change it;
/// with no price, 구매 정보 : + 입력, whose quiet link opens the sheet to add one.
class _DrinkPriceLine extends StatelessWidget {
  const _DrinkPriceLine({required this.editor});

  final RecordPriceEditor editor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) {
      if (!editor.settled) return const SizedBox.shrink();
      final price = editor.price;
      return Semantics(
        button: true,
        label: price == null ? '구매 정보 입력' : '${price.line}, 수정',
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey<String>('taste-card-price'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(editor.edit(context)),
          child: price == null
              ? Text.rich(
                  TextSpan(
                    text: '구매 정보 : ',
                    children: <InlineSpan>[
                      TextSpan(text: '+ 입력', style: _DrinkHeaderText.addPrice),
                    ],
                  ),
                  style: _DrinkHeaderText.category,
                )
              : Text(price.line, style: _DrinkHeaderText.category),
        ),
      );
    },
  );
}

/// How far over and under the price line a tap still opens its sheet. The
/// line is one row of small text, about 20 high; with this on both sides
/// the finger has the 44 a tap needs.
const _priceTapReach = 13.0;

/// Lets a tap that lands up to [above] over [child] or [below] under it
/// count as a tap on the child's nearest edge. It takes no room and draws
/// nothing, so a small line gets a finger-sized target while the page
/// around it stays as it is.
class _TapReach extends SingleChildRenderObjectWidget {
  const _TapReach({required super.child, this.above = 0, this.below = 0});

  final double above;
  final double below;

  @override
  _RenderTapReach createRenderObject(BuildContext context) =>
      _RenderTapReach(above, below);

  @override
  void updateRenderObject(BuildContext context, _RenderTapReach renderObject) {
    renderObject
      ..above = above
      ..below = below;
  }
}

class _RenderTapReach extends RenderProxyBox {
  _RenderTapReach(this.above, this.below);

  double above;
  double below;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (position.dx < 0 ||
        position.dx >= size.width ||
        position.dy < -above ||
        position.dy >= size.height + below) {
      return false;
    }
    // The nearest row that is still inside the child.
    final lastRow = size.height > 0.5 ? size.height - 0.5 : 0.0;
    final inside = position.dy.clamp(0.0, lastRow);
    return super.hitTest(result, position: Offset(position.dx, inside));
  }
}
