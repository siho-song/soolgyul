import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kept_first.dart';
import 'preference_history_content.dart';

/// Reads the reader's records; `null` (signed out, or no backend) shows
/// every month empty.
final preferenceHistoryGatewayProvider = Provider<PreferenceHistoryGateway?>(
  (ref) => null,
);

/// One month's records, kept for the session. They change only when a card
/// is saved, claimed or deleted or a note is written, which reloads them. On
/// the first load what the phone kept from last time shows until they come.
final historyMonthProvider =
    AsyncNotifierProvider.family<
      HistoryMonthNotifier,
      List<HistoryRecord>,
      DateTime
    >(HistoryMonthNotifier.new);

class HistoryMonthNotifier extends KeptFirstNotifier<List<HistoryRecord>> {
  HistoryMonthNotifier(this.month);
  final DateTime month;

  @override
  Future<List<HistoryRecord>?> kept() async =>
      switch (ref.read(preferenceHistoryGatewayProvider)) {
        final KeepsHistory keeper => keeper.keptMonth(month),
        _ => null,
      };

  @override
  Future<List<HistoryRecord>> load() =>
      ref.read(preferenceHistoryGatewayProvider)!.loadMonth(month);
}

/// When the newest record was made; the tab opens on its month.
final historyLatestProvider =
    AsyncNotifierProvider<HistoryLatestNotifier, DateTime?>(
      HistoryLatestNotifier.new,
    );

class HistoryLatestNotifier extends KeptFirstNotifier<DateTime?> {
  @override
  Future<DateTime?> kept() async =>
      switch (ref.read(preferenceHistoryGatewayProvider)) {
        final KeepsHistory keeper => keeper.keptLatest(),
        _ => null,
      };

  @override
  Future<DateTime?> load() =>
      ref.read(preferenceHistoryGatewayProvider)!.latestRecordedAt();
}
