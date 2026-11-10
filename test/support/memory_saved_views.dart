import 'dart:convert';

import 'package:soolgyul/src/core/saved_views.dart';

/// [SavedViews] held in memory, a set of copies per account, for tests that
/// cannot wait on real files.
class MemorySavedViews implements SavedViews {
  MemorySavedViews({this.account = 'member-a'});

  /// The signed-in account; `null` is signed out.
  String? account;
  final Map<String, Map<String, String>> copies =
      <String, Map<String, String>>{};

  @override
  Future<Object?> read(String name) async {
    final copy = copies[account]?[name];
    return copy == null ? null : jsonDecode(copy);
  }

  @override
  Future<void> write(String name, Object? json, {int? keepNewest}) async {
    final account = this.account;
    if (account == null) return;
    (copies[account] ??= <String, String>{})[name] = jsonEncode(json);
  }

  @override
  Future<void> remove(String name) async => copies[account]?.remove(name);

  @override
  Future<void> clear() async => copies.clear();
}
