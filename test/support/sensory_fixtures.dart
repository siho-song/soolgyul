import 'dart:convert';
import 'dart:io';

import 'package:soolgyul/src/core/sensory/sensory_gauges.dart';
import 'package:soolgyul/src/core/sensory/sensory_meanings.dart';
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
