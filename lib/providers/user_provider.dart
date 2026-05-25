import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/user_profile.dart';
import 'theme_provider.dart';

const _nameKey = 'profile_name';
const _avatarKey = 'profile_avatar';
const _idKey = 'profile_id';

/// Holds the local [UserProfile]. Null until onboarding completes.
class UserProfileNotifier extends StateNotifier<UserProfile?> {
  UserProfileNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static UserProfile? _load(SharedPreferences prefs) {
    final name = prefs.getString(_nameKey);
    if (name == null || name.isEmpty) return null;
    return UserProfile(
      id: prefs.getString(_idKey) ?? const Uuid().v4(),
      displayName: name,
      avatarIndex: prefs.getInt(_avatarKey) ?? 0,
    );
  }

  Future<void> save({required String displayName, required int avatarIndex}) async {
    final id = state?.id ?? _prefs.getString(_idKey) ?? const Uuid().v4();
    await _prefs.setString(_idKey, id);
    await _prefs.setString(_nameKey, displayName);
    await _prefs.setInt(_avatarKey, avatarIndex);
    state = UserProfile(id: id, displayName: displayName, avatarIndex: avatarIndex);
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile?>((ref) {
  return UserProfileNotifier(ref.watch(sharedPreferencesProvider));
});

/// True once the user has set up a profile (used for splash routing).
final hasOnboardedProvider = Provider<bool>((ref) {
  return ref.watch(userProfileProvider) != null;
});
