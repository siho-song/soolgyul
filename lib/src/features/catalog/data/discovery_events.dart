import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// What a reader did while looking for a drink. The misses tell the catalog
/// what to add; the picks, matches and views count interest by drink.
enum DiscoveryEvent {
  /// A drink chosen on a search screen, with the words typed for it.
  searchPick('search_pick'),

  /// Words whose search found nothing.
  searchEmpty('search_empty'),

  /// A label read whose likeliest bottle is the drink, with the words read.
  labelMatch('label_match'),

  /// A label read that matched nothing, with the words read.
  labelMiss('label_miss'),

  /// A drink chosen among a label's candidates, with the words read.
  labelPick('label_pick'),

  /// A drink whose taste fit was opened.
  fitView('fit_view');

  const DiscoveryEvent(this.key);

  final String key;
}

/// The screen the reader looked from.
enum DiscoverySurface {
  record('record'),
  tasteFit('taste_fit');

  const DiscoverySurface(this.key);

  final String key;
}

abstract interface class DiscoveryEventGateway {
  /// Sends one event in the background and never fails: the events are a
  /// signal nobody waits for, so a lost one is dropped.
  void record(
    DiscoveryEvent event,
    DiscoverySurface surface, {
    String? drinkId,
    String? query,
  });
}

class SupabaseDiscoveryEventGateway implements DiscoveryEventGateway {
  const SupabaseDiscoveryEventGateway(this._client);

  final SupabaseClient _client;

  @override
  void record(
    DiscoveryEvent event,
    DiscoverySurface surface, {
    String? drinkId,
    String? query,
  }) {
    unawaited(
      Future<void>(() async {
        try {
          await _client.rpc<void>(
            'soolgyul_record_discovery_event',
            params: <String, dynamic>{
              'event_kind': event.key,
              'event_surface': surface.key,
              'target_alcohol_item_id': drinkId,
              'event_query': query,
            },
          );
        } catch (_) {
          // Dropped; see [DiscoveryEventGateway.record].
        }
      }),
    );
  }
}
