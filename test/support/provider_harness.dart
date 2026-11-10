import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soolgyul/src/features/home/data/home_providers.dart';
import 'package:soolgyul/src/features/home/data/next_drink_guides.dart';
import 'package:soolgyul/src/features/home/data/taste_letters.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_providers.dart';

/// [child] under a fresh provider scope that reads through the given
/// gateways, as App hands them over; a failed read is not retried.
Widget withProviders({
  required Widget child,
  TasteLettersGateway? letters,
  NextDrinkGuidesGateway? guides,
  PreferenceHistoryGateway? history,
}) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    tasteLettersGatewayProvider.overrideWithValue(letters),
    nextDrinkGuidesGatewayProvider.overrideWithValue(guides),
    preferenceHistoryGatewayProvider.overrideWithValue(history),
  ],
  child: child,
);
