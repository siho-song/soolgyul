import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../catalog/data/catalog_drink.dart';
import '../adaptive/aroma_catalog_input.dart';
import '../adaptive/direct_aroma_choices.dart';
import '../adaptive/onboarding_aroma_menu.dart';
import '../../../core/sensory/sensory_gauges.dart';
import '../../../core/sensory/sensory_meanings.dart';
import 'dictionary_views.dart';

typedef SensoryQuestionnaireLoader =
    Future<SensoryQuestionnaireData> Function(DrinkSelection selection);
typedef SensoryContextReader =
    Future<Map<String, dynamic>?> Function(String id);

class SensoryQuestionnaireData {
  const SensoryQuestionnaireData({
    required this.registry,
    required this.aromaEngine,
    required this.aromas,
    required this.aromaMenu,
    required this.gauges,
  });

  final SensoryMeaningRegistry registry;
  final DirectAromaChoiceEngine aromaEngine;
  final DirectAromaResolution aromas;

  /// The menu of the drink's category and kind, which the aroma question
  /// shows.
  final OnboardingAromaMenu aromaMenu;

  /// The gauges the drink's category and kind are asked.
  final GaugeSet gauges;
}

/// The bundled definitions every questionnaire reads: the aroma rules, the
/// dictionary's words for what is sensed, the DB term contract, the gauges
/// and the engines built from them.
class _Definitions {
  _Definitions({
    required Map<String, dynamic> reference,
    required Map<String, Map<String, dynamic>> senses,
    required Map<String, dynamic> taxonomy,
    required Map<String, dynamic> gauges,
  }) : engine = DirectAromaChoiceEngine(
         reference: reference,
         vocabulary: senses['vocabulary']!,
         sourceCatalog: senses['sourceCatalog']!,
         alcoholTaxonomy: taxonomy,
       ),
       registry = SensoryMeaningRegistry(vocabulary: senses['vocabulary']!),
       gauges = SensoryGaugeDefinitions.fromJson(gauges) {
    catalogInput = AromaCatalogInputAdapter(
      engine: engine,
      reference: reference,
    );
  }

  final DirectAromaChoiceEngine engine;
  final SensoryMeaningRegistry registry;
  final SensoryGaugeDefinitions gauges;
  late final AromaCatalogInputAdapter catalogInput;

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
    final loaded = await Future.wait<Object>([
      json('catalog/sensory/aroma-choice-reference.json'),
      assets
          .load('catalog/dictionary/senses.json')
          .then(
            (bytes) =>
                inBackground ? compute(_senseViews, bytes) : _senseViews(bytes),
          ),
      json('config/catalog/enrichment_taxonomy_v2.json'),
      json('catalog/sensory/gauge-definitions.json'),
    ]);
    return _Definitions(
      reference: loaded[0] as Map<String, dynamic>,
      senses: loaded[1] as Map<String, Map<String, dynamic>>,
      taxonomy: loaded[2] as Map<String, dynamic>,
      gauges: loaded[3] as Map<String, dynamic>,
    );
  }
}

/// The two views of the dictionary's words the engines read. Top-level so it
/// can run on another isolate.
Map<String, Map<String, dynamic>> _senseViews(ByteData bytes) {
  final senses = Map<String, dynamic>.from(
    jsonDecode(
          utf8.decode(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          ),
        )
        as Map,
  );
  return {
    'vocabulary': serviceVocabularyView(senses),
    'sourceCatalog': sensoryCatalogView(senses),
  };
}

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

/// Bundled rule definitions plus live public product data. Loading errors must
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
    final product = definitions.catalogInput.read(row).product;
    // Keys this app does not know are dropped inside; only a category it
    // cannot place stops the questionnaire.
    final aromas = definitions.engine.resolve(product);
    if (aromas.status == AromaChoiceStatus.invalidInput) {
      throw FormatException('Unknown product category', product.categoryKey);
    }
    return SensoryQuestionnaireData(
      registry: definitions.registry,
      aromaEngine: definitions.engine,
      aromas: aromas,
      aromaMenu: OnboardingAromaMenu.forDrink(
        product.categoryKey,
        aromas.styleKey,
      ),
      gauges: definitions.gauges.forDrink(product.categoryKey, aromas.styleKey),
    );
  }
}

Future<SensoryQuestionnaireData> loadSensoryQuestionnaireData(
  DrinkSelection selection,
) => SensoryQuestionnaireDataSource(
  readContext: (id) async {
    final value = await Supabase.instance.client.rpc(
      'soolgyul_get_sensory_question_context',
      params: {'target_catalog_id': id},
    );
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  },
).load(selection);
