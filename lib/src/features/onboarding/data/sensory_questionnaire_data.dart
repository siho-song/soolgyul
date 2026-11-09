import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/catalog/catalog_assignment.dart';
import '../../catalog/data/catalog_drink.dart';
import '../adaptive/aroma_catalog_input.dart';
import '../adaptive/direct_aroma_choices.dart';
import '../adaptive/onboarding_aroma_menu.dart';
import '../../../core/sensory/sensory_asked_keys.dart';
import '../../../core/sensory/sensory_meanings.dart';
import '../../../core/sensory/sensory_option_definitions.dart';
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
    this.asked = SensoryAskedKeys.all,
  });

  final SensoryMeaningRegistry registry;
  final DirectAromaChoiceEngine aromaEngine;
  final DirectAromaResolution aromas;

  /// The drink category's fixed menu, which the aroma question shows.
  final OnboardingAromaMenu aromaMenu;
  final SensoryAskedKeys asked;
}

/// Bundled rule definitions plus live public product data. Loading errors must
/// reach the retry UI, not silently become an unclassified product.
class SensoryQuestionnaireDataSource {
  SensoryQuestionnaireDataSource({
    required this.readContext,
    AssetBundle? assets,
  }) : assets = assets ?? rootBundle;

  final SensoryContextReader readContext;
  final AssetBundle assets;

  Future<SensoryQuestionnaireData> load(DrinkSelection selection) async {
    Future<Map<String, dynamic>> json(String path) async =>
        Map<String, dynamic>.from(
          jsonDecode(await assets.loadString(path)) as Map,
        );
    final configs = await Future.wait([
      json('catalog/sensory/aroma-choice-reference.json'),
      json('catalog/dictionary/terms.json'),
      json('catalog/sensory/palate-question-bank.json'),
      json('catalog/sensory/answer-option-definitions.json'),
    ]);
    final vocabulary = serviceVocabularyView(configs[1]);
    final engine = DirectAromaChoiceEngine(
      reference: configs[0],
      vocabulary: vocabulary,
      sourceCatalog: sensoryCatalogView(configs[1]),
      alcoholTaxonomy: taxonomyView(configs[1]),
    );
    final registry = SensoryMeaningRegistry(
      vocabulary: vocabulary,
      tasteBank: configs[2],
      definitions: SensoryOptionDefinitions.fromJson(configs[3]),
    );
    final id = selection.catalogId;
    final row = await readContext(id);
    if (row == null || row['id'] != id) {
      throw const FormatException('Selected public product is unavailable');
    }
    final product = AromaCatalogInputAdapter(
      engine: engine,
      reference: configs[0],
      vocabulary: vocabulary,
      sourceCatalog: sensoryCatalogView(configs[1]),
    ).read(row).product;
    final aromas = engine.resolve(product);
    if (aromas.status == AromaChoiceStatus.invalidInput) {
      throw const FormatException('Invalid product classification');
    }
    CatalogAssignmentRegistry().validate({
      'category_key': product.categoryKey,
      'style_key': product.styleKeys.singleOrNull,
      'target': product.assignmentTarget.name,
      'ingredient_keys': product.ingredientKeys.toList(),
      'production_process_keys': product.processKeys.toList(),
    }).requireValid();
    if (row['sensory_scale'] != 5) {
      throw const FormatException('Expected integer sensory scale 1..5');
    }
    return SensoryQuestionnaireData(
      registry: registry,
      aromaEngine: engine,
      aromas: aromas,
      aromaMenu: OnboardingAromaMenu.forCategory(product.categoryKey),
      asked: SensoryAskedKeys.forProduct(
        product.categoryKey,
        product.styleKeys.singleOrNull,
      ),
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
