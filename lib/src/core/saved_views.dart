import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// What the app last showed of the signed-in account, kept on the phone so
/// the next launch can show it at once while the server is asked again.
///
/// A copy is the server's own answer as JSON; whoever reads it parses it as
/// it parses the answer. Each account has its own copies, so one account
/// never sees another's, and signing out forgets everything. A copy that
/// cannot be read or written is treated as no copy: keeping never fails the
/// screen that asked.
abstract interface class SavedViews {
  /// The copy kept under [name] for the signed-in account, decoded, or
  /// `null` when there is none or it is too old.
  Future<Object?> read(String name);

  /// Keeps [json] under [name] for the signed-in account. With [keepNewest]
  /// only that many copies whose name starts with [name]'s prefix (up to the
  /// first `-`) stay, the newest ones.
  Future<void> write(String name, Object? json, {int? keepNewest});

  /// Forgets the copy kept under [name].
  Future<void> remove(String name);

  /// Forgets everything, of every account that used this phone.
  Future<void> clear();
}

/// [SavedViews] as files in the app's cache folder, one folder per account.
/// A copy older than [keptFor] is not used. A browser keeps nothing.
class SavedViewFiles implements SavedViews {
  SavedViewFiles({
    required this.accountId,
    this.folder = _appFolder,
    this.keptFor = const Duration(days: 30),
    this.now = DateTime.now,
  });

  /// The signed-in account, `null` when nobody is signed in.
  final String? Function() accountId;

  /// Where the copies live; `null` keeps nothing.
  final Future<Directory?> Function() folder;
  final Duration keptFor;
  final DateTime Function() now;

  static Future<Directory?> _appFolder() async {
    if (kIsWeb) return null;
    // The cache folder: the system leaves it out of device backups and may
    // empty it when storage runs low, which only means asking the server.
    final cache = await getApplicationCacheDirectory();
    return Directory('${cache.path}/saved_views');
  }

  static final RegExp _plainName = RegExp(r'^[a-z0-9_-]+$');

  Future<File?> _file(String name) async {
    assert(_plainName.hasMatch(name), 'a saved view is named in a-z0-9_-');
    final account = accountId();
    final root = await folder();
    if (account == null || root == null || !_plainName.hasMatch(name)) {
      return null;
    }
    final safeAccount = account.replaceAll(RegExp('[^A-Za-z0-9-]'), '_');
    return File('${root.path}/$safeAccount/$name.json');
  }

  @override
  Future<Object?> read(String name) async {
    try {
      final file = await _file(name);
      if (file == null || !file.existsSync()) return null;
      if (now().difference(file.lastModifiedSync()) > keptFor) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String name, Object? json, {int? keepNewest}) async {
    try {
      final file = await _file(name);
      if (file == null) return;
      file.parent.createSync(recursive: true);
      // Written beside the copy and moved over it, so a copy is whole or
      // absent, never half written.
      final draft = File('${file.path}.new');
      await draft.writeAsString(jsonEncode(json), flush: true);
      draft.renameSync(file.path);
      if (keepNewest != null) _prune(file.parent, name, keepNewest);
    } catch (_) {
      // Not kept this time; the next load tries again.
    }
  }

  void _prune(Directory folder, String name, int keepNewest) {
    final prefix = '${name.split('-').first}-';
    final copies =
        folder
            .listSync()
            .whereType<File>()
            .where((file) => file.uri.pathSegments.last.startsWith(prefix))
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
    for (final old in copies.skip(keepNewest)) {
      old.deleteSync();
    }
  }

  @override
  Future<void> remove(String name) async {
    try {
      final file = await _file(name);
      if (file != null && file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      final root = await folder();
      if (root != null && root.existsSync()) root.deleteSync(recursive: true);
    } catch (_) {}
  }
}
