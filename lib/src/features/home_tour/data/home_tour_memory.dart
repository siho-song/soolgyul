import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, on this phone and per account, that the home tour was offered.
abstract interface class HomeTourMemory {
  /// Whether this account was offered the tour here; `true` when nobody is
  /// signed in, so nobody is shown it.
  Future<bool> offered();

  Future<void> rememberOffered();
}

class DeviceHomeTourMemory implements HomeTourMemory {
  DeviceHomeTourMemory({required this.accountId});

  /// The signed-in account, or `null`.
  final String? Function() accountId;

  String? get _key => switch (accountId()) {
    final id? => 'home-tour.$id.offered',
    null => null,
  };

  @override
  Future<bool> offered() async {
    final key = _key;
    if (key == null) return true;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(key) ?? false;
  }

  @override
  Future<void> rememberOffered() async {
    final key = _key;
    if (key == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, true);
  }
}
