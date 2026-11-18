import 'dart:convert';
import 'dart:io';

import 'package:soolgyul/src/core/sensory/sensory_gauges.dart';
import 'package:soolgyul/src/core/sensory/sensory_meanings.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/direct_aroma_choices.dart';
import 'package:soolgyul/src/features/onboarding/data/dictionary_views.dart';

/// Reads a bundled JSON asset from the repository, relative to its root.
Map<String, dynamic> readJsonAsset(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// A deep copy, for tests that mutate a config without touching the original.
Map<String, dynamic> deepCopyJson(Map<String, dynamic> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>;

Map<String, dynamic> _senses() =>
    readJsonAsset('catalog/dictionary/senses.json');

Map<String, dynamic> serviceVocabulary() => serviceVocabularyView(_senses());

Map<String, dynamic> sensoryCatalog() => sensoryCatalogView(_senses());

Map<String, dynamic> alcoholTaxonomy() =>
    readJsonAsset('config/catalog/enrichment_taxonomy_v2.json');

Map<String, dynamic> aromaChoiceReference() =>
    readJsonAsset('catalog/sensory/aroma-choice-reference.json');

/// The bundled gauge definitions, which the server reads too.
SensoryGaugeDefinitions gaugeDefinitions() => SensoryGaugeDefinitions.fromJson(
  readJsonAsset('catalog/sensory/gauge-definitions.json'),
);

/// The gauges a drink of [category] and [style] is asked.
GaugeSet gaugesFor(String? category, [String? style]) =>
    gaugeDefinitions().forDrink(category, style);

/// The registry built from the bundled aroma dictionary.
SensoryMeaningRegistry sensoryRegistry() =>
    SensoryMeaningRegistry(vocabulary: serviceVocabulary());

/// The aroma engine over the bundled files; [reference] swaps the rules.
DirectAromaChoiceEngine aromaEngine([Map<String, dynamic>? reference]) =>
    DirectAromaChoiceEngine(
      reference: reference ?? aromaChoiceReference(),
      vocabulary: serviceVocabulary(),
      sourceCatalog: sensoryCatalog(),
      alcoholTaxonomy: alcoholTaxonomy(),
    );

/// Rule coverage only: product-listed or rule-backed options, ignoring the
/// related-aroma fill that always pads the visible list.
extension RuledAromaResolution on DirectAromaResolution {
  List<DirectAromaOption> get ruled => [
    ...options,
    ...moreOptions,
  ].where((o) => o.productListed || o.ruleIds.isNotEmpty).toList();
  bool get hasEnoughOptions => ruled.length >= 8;
}
