import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a screen may show of [value]: the loaded data, kept while it loads
/// again after a change, but not across a sign-out (a reload), where the
/// next account must not see the last one's data.
T? shownValue<T>(AsyncValue<T> value) => value.isReloading ? null : value.value;
