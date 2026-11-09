import '../../taste_card/data/taste_card_snapshot_view_data.dart';
import '../../taste_card/data/taste_card_wire_parser.dart';
import '../../taste_card/data/taste_card_wire_requests.dart';

/// One slide of the home's 다음 한 잔 가이드: the guide a recent card wrote
/// (다음 술은 이렇게 골라보세요) with the bottle's kind, and the card it came
/// from.
class NextDrinkGuide {
  const NextDrinkGuide({
    required this.resultId,
    required this.kindLabel,
    required this.categoryLabel,
    required this.guide,
  });

  final String resultId;

  /// 와인, 위스키, 사케, 한국 전통주: names the picks' section of the guide.
  final String? categoryLabel;

  /// 레드 와인, 준마이 긴조, 싱글몰트 위스키; the category when the bottle has
  /// no finer kind.
  final String kindLabel;
  final TasteCardGuideViewData guide;

  static NextDrinkGuide fromRow(Object? value, String path) {
    if (value is! Map) throw TasteCardWireException('object_expected', path);
    final resultId = value['result_id'];
    final kindLabel = value['kind_label'];
    if (resultId is! String || resultId.isEmpty) {
      throw TasteCardWireException('result_id_invalid', '$path.result_id');
    }
    if (kindLabel is! String || kindLabel.isEmpty) {
      throw TasteCardWireException('kind_label_invalid', '$path.kind_label');
    }
    final categoryLabel = value['category_label'];
    if (categoryLabel is! String?) {
      throw TasteCardWireException(
        'category_label_invalid',
        '$path.category_label',
      );
    }
    return NextDrinkGuide(
      resultId: resultId,
      kindLabel: kindLabel,
      categoryLabel: categoryLabel,
      guide: TasteCardWireParser.parseGuide(value['guide'], '$path.guide'),
    );
  }
}

/// The owner's latest guides, newest first; cards without a guide are not
/// in the list.
abstract interface class NextDrinkGuidesGateway {
  Future<List<NextDrinkGuide>> load();
}
