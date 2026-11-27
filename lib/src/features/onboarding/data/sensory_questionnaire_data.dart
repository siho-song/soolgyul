import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../catalog/data/catalog_drink.dart';
import '../../taste_card/data/taste_card_appearance_choices.dart';
import '../../taste_card/data/taste_card_note_view_data.dart';
import '../adaptive/onboarding_aroma_menu.dart';
import '../../../core/catalog/catalog_assignment.dart';
import '../../../core/sensory/sensory_gauges.dart';
import '../../../core/sensory/sensory_meanings.dart';
import '../../../core/supabase/time_limited_client.dart';
import 'aroma_chip_names.dart';
import 'dictionary_views.dart';

typedef SensoryQuestionnaireLoader =
    Future<SensoryQuestionnaireData> Function(DrinkSelection selection);
typedef SensoryContextReader =
    Future<Map<String, dynamic>?> Function(String id);

class SensoryQuestionnaireData {
  const SensoryQuestionnaireData({
    required this.registry,
    required this.aromaMenu,
    required this.gauges,
    this.appearance = const [],
  });

  final SensoryMeaningRegistry registry;

  /// The menu of the drink's category and kind, which the aroma question
  /// shows.
  final OnboardingAromaMenu aromaMenu;

  /// The gauges the drink's category and kind are asked.
  final GaugeSet gauges;

  /// The colour and texture the drink's kind may note, which a record asks
  /// beside 재음용 의사; empty for a kind that notes neither.
  final List<TasteCardNoteChoiceViewData> appearance;
}

/// The bundled definitions every questionnaire reads: the dictionary's
/// words for what is sensed, the kinds of drink the DB term contract knows,
/// the gauges and the look a kind may note.
class _Definitions {
  _Definitions({
    required Map<String, dynamic> vocabulary,
    required Map<String, dynamic> taxonomy,
    required Map<String, dynamic> gauges,
    required Map<String, dynamic> appearance,
  }) : appearance = TasteCardAppearanceChoices.fromJson(appearance),
       registry = SensoryMeaningRegistry(vocabulary: vocabulary),
       gauges = SensoryGaugeDefinitions.fromJson(gauges),
       _kindRedirects = Map<String, String>.from(
         taxonomy['style_redirects'] as Map? ?? const {},
       ) {
    nameAromaChips(registry.aromaLabel);
  }

  final SensoryMeaningRegistry registry;
  final SensoryGaugeDefinitions gauges;
  final TasteCardAppearanceChoices appearance;

  /// A kind since folded into another, by the kind it is asked as now: a
  /// 도쿠베쓰 준마이 as a 준마이.
  final Map<String, String> _kindRedirects;
  final _assignments = CatalogAssignmentRegistry();

  /// The category and kind a product [row] is asked by, or null for a
  /// category this app does not know, which stops the questionnaire. The
  /// kind is the row's one kind as it is called now; a row with several, or
  /// with a kind this app cannot place in its category, is asked by its
  /// category alone: the server may add kinds after this app shipped.
  ({String category, String? kind})? placeOf(Map<String, dynamic> row) {
    final kinds = {
      for (final kind in switch (row['styles']) {
        final List<Object?> several => several,
        _ => [row['style_key']],
      })
        if (kind is String) _kindRedirects[kind] ?? kind,
    };
    final placed = _assignments.validateKnown({
      'category_key': row['category'],
      'style_key': kinds.length == 1 ? kinds.single : null,
    }).value;
    return placed == null
        ? null
        : (category: placed.categoryKey.key, kind: placed.styleKey?.key);
  }

  /// [inBackground] decodes the dictionary's words off the calling isolate.
  /// Widget tests cannot wait on another isolate, so they read in place.
  static Future<_Definitions> load(
    AssetBundle assets, {
    required bool inBackground,
  }) async {
    Future<Map<String, dynamic>> json(String path) async =>
        Map<String, dynamic>.from(
          jsonDecode(await assets.loadString(path, cache: false)) as Map,
        );
    final loaded = await Future.wait<Map<String, dynamic>>([
      assets
          .load('catalog/dictionary/senses.json')
          .then(
            (bytes) =>
                inBackground ? compute(_vocabulary, bytes) : _vocabulary(bytes),
          ),
      json('config/catalog/enrichment_taxonomy_v2.json'),
      json('catalog/sensory/gauge-definitions.json'),
      json('catalog/sensory/appearance.json'),
    ]);
    return _Definitions(
      vocabulary: loaded[0],
      taxonomy: loaded[1],
      gauges: loaded[2],
      appearance: loaded[3],
    );
  }
}

/// The dictionary's words as the reader is offered them. Top-level so it can
/// run on another isolate.
Map<String, dynamic> _vocabulary(ByteData bytes) => serviceVocabularyView(
  Map<String, dynamic>.from(
    jsonDecode(
          utf8.decode(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          ),
        )
        as Map,
  ),
);

/// The app bundle's definitions, built once per app session.
Future<_Definitions>? _bundled;

Future<_Definitions> _bundledDefinitions() {
  if (_bundled case final loading?) return loading;
  final loading = _Definitions.load(rootBundle, inBackground: true);
  _bundled = loading;
  // A failed read is tried again by the next questionnaire.
  loading.then<void>((_) {}, onError: (Object _) => _bundled = null);
  return loading;
}

/// Reads the app bundle's definitions ahead of the first questionnaire, so
/// a card opened before one draws its aromas with their pictures. A failed
/// read is left to the first questionnaire.
Future<void> readBundledDefinitions() =>
    _bundledDefinitions().then<void>((_) {}, onError: (Object _) {});

/// Bundled definitions plus live public product data. Loading errors must
/// reach the retry UI, not silently become an unclassified product.
class SensoryQuestionnaireDataSource {
  /// Without [assets] the app's own bundle is read once per session. Given
  /// [assets], as tests do, each load reads them again on this isolate.
  SensoryQuestionnaireDataSource({
    required this.readContext,
    AssetBundle? assets,
  }) : _definitions = assets == null
           ? _bundledDefinitions
           : (() => _Definitions.load(assets, inBackground: false));

  final SensoryContextReader readContext;
  final Future<_Definitions> Function() _definitions;

  Future<SensoryQuestionnaireData> load(DrinkSelection selection) async {
    final id = selection.catalogId;
    // The product is fetched while the definitions are read.
    final loaded = await Future.wait<Object?>([
      _definitions(),
      Future.sync(() => readContext(id)),
    ]);
    final definitions = loaded[0]! as _Definitions;
    final row = loaded[1] as Map<String, dynamic>?;
    if (row == null || row['id'] != id) {
      throw const FormatException('Selected public product is unavailable');
    }
    if (row['sensory_scale'] != 5) {
      throw const FormatException('Expected integer sensory scale 1..5');
    }
    final placed = definitions.placeOf(row);
    if (placed == null) {
      throw FormatException('Unknown product category', row['category']);
    }
    final (:category, :kind) = placed;
    return SensoryQuestionnaireData(
      registry: definitions.registry,
      aromaMenu: OnboardingAromaMenu.forDrink(category, kind),
      gauges: definitions.gauges.forDrink(category, kind),
      appearance: definitions.appearance.forDrink(category, kind),
    );
  }
}

Future<SensoryQuestionnaireData> loadSensoryQuestionnaireData(
  DrinkSelection selection,
) => SensoryQuestionnaireDataSource(
  readContext: (id) async {
    // This call only reads, but a database function is called as a write,
    // which waits longer for its answer (and for a login renewed first).
    // The questions' page shows a bare spinner meanwhile, so the read's
    // own limit ends the wait.
    final value = await Supabase.instance.client
        .rpc(
          'soolgyul_get_sensory_question_context',
          params: {'target_catalog_id': id},
        )
        .timeout(TimeLimitedClient.defaultReadLimit);
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  },
).load(selection);
