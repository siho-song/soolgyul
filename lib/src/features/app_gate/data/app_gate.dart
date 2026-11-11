import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether this app may go on.
enum AppGateDecision { open, updateRequired, maintenance }

/// What the server says about letting an app of one platform in: the oldest
/// version that still works with it, and a notice while it is paused.
class AppGate {
  const AppGate({this.minimumVersion = '0.0.0', this.maintenanceMessage});

  factory AppGate.fromRow(Map<String, dynamic> row) {
    final notice = row['maintenance_message'];
    final minimum = row['minimum_version'];
    return AppGate(
      minimumVersion: minimum is String ? minimum : '0.0.0',
      maintenanceMessage: notice is String && notice.trim().isNotEmpty
          ? notice.trim()
          : null,
    );
  }

  final String minimumVersion;
  final String? maintenanceMessage;

  /// A pause comes before an update: an update cannot be used during one.
  /// [installedVersion] is null where no version can be too old (the web,
  /// which is always the deployed one).
  AppGateDecision decide(String? installedVersion) {
    if (maintenanceMessage != null) return AppGateDecision.maintenance;
    if (installedVersion != null &&
        isOlderVersion(installedVersion, minimumVersion)) {
      return AppGateDecision.updateRequired;
    }
    return AppGateDecision.open;
  }
}

/// Whether [installed] comes before [minimum], comparing `major.minor.patch`
/// as numbers (1.10.0 is newer than 1.9.0). A build number or suffix is
/// ignored. A version that cannot be read is never "older": the gate must
/// not shut on something it does not understand.
bool isOlderVersion(String installed, String minimum) {
  final have = _numbers(installed);
  final need = _numbers(minimum);
  if (have == null || need == null) return false;
  for (var index = 0; index < 3; index++) {
    if (have[index] != need[index]) return have[index] < need[index];
  }
  return false;
}

List<int>? _numbers(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
  if (match == null) return null;
  return [for (var group = 1; group <= 3; group++) int.parse(match[group]!)];
}

/// Reads the gate of [platform] (`ios`, `android` or `web`); null when the
/// server has none for it.
Future<AppGate?> loadAppGate(SupabaseClient client, String platform) async {
  final row = await client
      .from('app_gates')
      .select('minimum_version, maintenance_message')
      .eq('platform', platform)
      .maybeSingle();
  return row == null ? null : AppGate.fromRow(row);
}
