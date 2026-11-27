import 'taste_card_note_view_data.dart';

/// 외관 as `catalog/sensory/appearance.json` holds it: the colours of each
/// kind and the textures, read by the record's first question. The server
/// reads the same file for the 테이스팅 노트, where the same choices are
/// shown and changed.
class TasteCardAppearanceChoices {
  TasteCardAppearanceChoices.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported appearance definitions');
    }
    _color = json['color'] as Map<String, dynamic>;
    _viscosity = json['viscosity'] as Map<String, dynamic>;
    _turbidity = json['turbidity'] as Map<String, dynamic>;
  }

  late final Map<String, dynamic> _color;
  late final Map<String, dynamic> _viscosity;
  late final Map<String, dynamic> _turbidity;

  static const colorField = 'appearance';
  static const textureField = 'appearance_texture';

  /// What a drink of [categoryKey] and [styleKey] may note of its look, as
  /// the 테이스팅 노트 asks it: a 탁주 its cloudiness alone, a wine and a
  /// whisky their colour and how they cling to the glass, any other kind
  /// nothing. A sparkling wine is read on the white wine's colours.
  List<TasteCardNoteChoiceViewData> forDrink(
    String? categoryKey,
    String? styleKey,
  ) {
    if (styleKey == 'takju') return [_state(_turbidity)];
    if (categoryKey != 'wine' && categoryKey != 'whisky') return const [];
    final palette = switch (categoryKey) {
      'whisky' => 'whisky',
      _ when styleKey == 'sparkling_wine' => 'white_wine',
      _ => styleKey,
    };
    final colours = (_color['palettes'] as Map<String, dynamic>)[palette];
    return [
      if (colours is List)
        TasteCardNoteChoiceViewData(
          field: colorField,
          label: _color['label'] as String,
          prompt: _color['prompt'] as String,
          options: [
            for (final raw in colours)
              TasteCardNoteOptionViewData(
                key: (raw as List)[0] as String,
                label: raw[1] as String,
                swatch: _swatch(raw[2] as String),
              ),
          ],
        ),
      _state(_viscosity),
    ];
  }

  TasteCardNoteChoiceViewData _state(Map<String, dynamic> group) =>
      TasteCardNoteChoiceViewData(
        field: textureField,
        label: group['label'] as String,
        prompt: group['prompt'] as String,
        options: [
          for (final raw in group['choices'] as List)
            TasteCardNoteOptionViewData(
              key: (raw as List)[0] as String,
              label: raw[1] as String,
              icon: raw[2] as String,
            ),
        ],
      );

  /// `#4E1D3B` as an opaque colour value.
  static int _swatch(String hex) =>
      0xFF000000 | int.parse(hex.substring(1), radix: 16);
}
