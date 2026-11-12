import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_report.dart';
import '../../../core/kept_first.dart';
import '../../../core/saved_views.dart';
import '../../../core/supabase/signed_in.dart';
import 'next_drink_guides.dart';

class SupabaseNextDrinkGuidesGateway
    implements NextDrinkGuidesGateway, KeepsLast<List<NextDrinkGuide>> {
  const SupabaseNextDrinkGuidesGateway(this._client, {this.saved});
  final SupabaseClient _client;

  /// Where the last answer is kept for the next launch; `null` keeps none.
  final SavedViews? saved;
  static const _savedName = 'guides';
  static const slideCount = 3;

  @override
  Future<List<NextDrinkGuide>> load() async {
    signedInUserId(_client);
    final rows = await _client.rpc(
      'soolgyul_my_recent_card_guides',
      params: {'p_limit': slideCount},
    );
    if (rows is! List) throw StateError('the guides are not a list');
    final guides = _guides(rows);
    unawaited(saved?.write(_savedName, rows));
    return guides;
  }

  @override
  Future<List<NextDrinkGuide>?> kept() async {
    final copy = await saved?.read(_savedName);
    return copy is List ? _guides(copy) : null;
  }

  /// A row this app cannot read is reported and left out; the other
  /// guides still show.
  static List<NextDrinkGuide> _guides(List<Object?> rows) => [
    for (final (index, row) in rows.indexed) ?_guide(row, index),
  ];

  static NextDrinkGuide? _guide(Object? row, int index) {
    try {
      return NextDrinkGuide.fromRow(
        row,
        r'$guides'
        '[$index]',
      );
    } catch (error, stack) {
      reportError(error, stack, where: 'guides');
      return null;
    }
  }
}
