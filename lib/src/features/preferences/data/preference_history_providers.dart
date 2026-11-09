import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preference_history_content.dart';

/// Reads the reader's records; `null` (signed out, or no backend) shows
/// every month empty.
final preferenceHistoryGatewayProvider = Provider<PreferenceHistoryGateway?>(
  (ref) => null,
);

/// One month's records, kept for the session. They change only when a card
/// is saved, claimed or deleted or a note is written, which reloads them.
final historyMonthProvider =
    FutureProvider.family<List<HistoryRecord>, DateTime>(
      (ref, month) =>
          ref.watch(preferenceHistoryGatewayProvider)!.loadMonth(month),
    );

/// When the newest record was made; the tab opens on its month.
final historyLatestProvider = FutureProvider<DateTime?>(
  (ref) => ref.watch(preferenceHistoryGatewayProvider)!.latestRecordedAt(),
);
