import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/kept_first.dart';
import '../../../core/saved_views.dart';
import 'account_completion_draft.dart';
import 'profile_setup_draft.dart';
import 'profile_preferences_gateway.dart';
import '../../../core/ids.dart';

typedef ProfilePreferencesRpcInvoker =
    Future<dynamic> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );
typedef ProfileIdempotencyKeyFactory = String Function();

class SupabaseProfilePreferencesGateway
    implements ProfilePreferencesGateway, KeepsLast<ProfilePreferences> {
  SupabaseProfilePreferencesGateway(
    SupabaseClient client, {
    ProfilePreferencesRpcInvoker? rpcInvoker,
    ProfileIdempotencyKeyFactory? idempotencyKeyFactory,
    this.saved,
  }) : _rpcInvoker =
           rpcInvoker ??
           ((functionName, parameters) async {
             return await client.rpc(functionName, params: parameters);
           }),
       _idempotencyKeyFactory = idempotencyKeyFactory ?? createUuidV4;

  final ProfilePreferencesRpcInvoker _rpcInvoker;
  final ProfileIdempotencyKeyFactory _idempotencyKeyFactory;

  /// Where the last profile is kept for the next launch; `null` keeps none.
  final SavedViews? saved;
  static const _savedName = 'profile';

  @override
  Future<ProfilePreferences?> kept() async {
    final copy = await saved?.read(_savedName);
    if (copy is! Map) return null;
    try {
      return _preferences(Map<String, dynamic>.from(copy));
    } catch (_) {
      return null;
    }
  }

  static ProfilePreferences _preferences(Map<String, dynamic> response) {
    final displayName = response['display_name'];
    if (displayName != null && displayName is! String) {
      throw const FormatException('display_name');
    }
    return ProfilePreferences(
      displayName: displayName as String?,
      interests: _interestSet(
        response['interest_group_keys'],
        ignoreUnknown: true,
      ),
      gender: _gender(response['gender']),
    );
  }

  @override
  Future<ProfilePreferences> fetchProfilePreferences() async {
    try {
      final response = _responseMap(
        await _rpcInvoker(
          'soolgyul_get_my_profile_preferences',
          const <String, dynamic>{},
        ),
      );
      final preferences = _preferences(response);
      unawaited(saved?.write(_savedName, response));
      return preferences;
    } catch (_) {
      throw const ProfilePreferencesException(
        ProfilePreferencesOperation.fetch,
      );
    }
  }

  @override
  Future<String> updateDisplayName(String displayName) async {
    try {
      final response = _responseMap(
        await _rpcInvoker('soolgyul_update_my_display_name', <String, dynamic>{
          'p_display_name': displayName,
          'p_idempotency_key': _idempotencyKeyFactory(),
        }),
      );
      final storedDisplayName = response['display_name'];
      if (storedDisplayName is! String || storedDisplayName.isEmpty) {
        throw const FormatException('display_name');
      }
      return storedDisplayName;
    } catch (_) {
      throw const ProfilePreferencesException(
        ProfilePreferencesOperation.updateDisplayName,
      );
    }
  }

  @override
  Future<Set<DrinkInterest>> replaceDrinkInterests(
    Set<DrinkInterest> interests,
  ) async {
    if (interests.isEmpty) {
      throw const ProfilePreferencesException(
        ProfilePreferencesOperation.replaceDrinkInterests,
      );
    }

    try {
      final orderedWireKeys = <String>[
        for (final interest in DrinkInterest.values)
          if (interests.contains(interest)) interest.wireKey,
      ];
      final response = _responseMap(
        await _rpcInvoker(
          'soolgyul_replace_my_drink_interests',
          <String, dynamic>{
            'p_interest_group_keys': orderedWireKeys,
            'p_idempotency_key': _idempotencyKeyFactory(),
          },
        ),
      );
      final storedInterests = _interestSet(response['interest_group_keys']);
      if (storedInterests.isEmpty) {
        throw const FormatException('interest_group_keys');
      }
      return storedInterests;
    } catch (_) {
      throw const ProfilePreferencesException(
        ProfilePreferencesOperation.replaceDrinkInterests,
      );
    }
  }

  static Map<String, dynamic> _responseMap(dynamic response) {
    if (response is! Map) {
      throw const FormatException('response');
    }
    return Map<String, dynamic>.from(response);
  }

  static ProfileGender? _gender(dynamic value) {
    if (value == null) return null;
    for (final gender in ProfileGender.values) {
      if (gender.name == value) return gender;
    }
    throw const FormatException('gender');
  }

  /// A read passes [ignoreUnknown]: an interest added on the server after
  /// this app shipped is left out instead of failing the whole profile. The
  /// answer to a write names only what this app sent, so it stays strict.
  static Set<DrinkInterest> _interestSet(
    dynamic value, {
    bool ignoreUnknown = false,
  }) {
    if (value is! List) {
      throw const FormatException('interest_group_keys');
    }

    final interestByWireKey = <String, DrinkInterest>{
      for (final interest in DrinkInterest.values) interest.wireKey: interest,
    };
    final parsed = <DrinkInterest>{};
    for (final wireKey in value) {
      final interest = wireKey is String ? interestByWireKey[wireKey] : null;
      if (interest == null && ignoreUnknown && wireKey is String) continue;
      if (interest == null || !parsed.add(interest)) {
        throw const FormatException('interest_group_keys');
      }
    }
    return Set<DrinkInterest>.unmodifiable(parsed);
  }
}
