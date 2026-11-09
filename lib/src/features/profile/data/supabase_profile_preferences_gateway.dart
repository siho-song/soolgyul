import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_setup_draft.dart';
import 'profile_preferences_gateway.dart';
import '../../../core/ids.dart';

typedef ProfilePreferencesRpcInvoker =
    Future<dynamic> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );
typedef ProfileIdempotencyKeyFactory = String Function();

class SupabaseProfilePreferencesGateway implements ProfilePreferencesGateway {
  SupabaseProfilePreferencesGateway(
    SupabaseClient client, {
    ProfilePreferencesRpcInvoker? rpcInvoker,
    ProfileIdempotencyKeyFactory? idempotencyKeyFactory,
  }) : _rpcInvoker =
           rpcInvoker ??
           ((functionName, parameters) async {
             return await client.rpc(functionName, params: parameters);
           }),
       _idempotencyKeyFactory = idempotencyKeyFactory ?? createUuidV4;

  final ProfilePreferencesRpcInvoker _rpcInvoker;
  final ProfileIdempotencyKeyFactory _idempotencyKeyFactory;

  @override
  Future<ProfilePreferences> fetchProfilePreferences() async {
    try {
      final response = _responseMap(
        await _rpcInvoker(
          'soolgyul_get_my_profile_preferences',
          const <String, dynamic>{},
        ),
      );
      final displayName = response['display_name'];
      if (displayName != null && displayName is! String) {
        throw const FormatException('display_name');
      }
      return ProfilePreferences(
        displayName: displayName as String?,
        interests: _interestSet(response['interest_group_keys']),
      );
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

  static Set<DrinkInterest> _interestSet(dynamic value) {
    if (value is! List) {
      throw const FormatException('interest_group_keys');
    }

    final interestByWireKey = <String, DrinkInterest>{
      for (final interest in DrinkInterest.values) interest.wireKey: interest,
    };
    final parsed = <DrinkInterest>{};
    for (final wireKey in value) {
      final interest = wireKey is String ? interestByWireKey[wireKey] : null;
      if (interest == null || !parsed.add(interest)) {
        throw const FormatException('interest_group_keys');
      }
    }
    return Set<DrinkInterest>.unmodifiable(parsed);
  }
}
