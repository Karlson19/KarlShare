import 'package:flutter/foundation.dart';

/// The local user's identity, set during onboarding (Section 6.2 screen 4).
@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.avatarIndex,
  });

  final String id;
  final String displayName;

  /// Index into the preset avatar set (0–11).
  final int avatarIndex;

  UserProfile copyWith({String? displayName, int? avatarIndex}) => UserProfile(
        id: id,
        displayName: displayName ?? this.displayName,
        avatarIndex: avatarIndex ?? this.avatarIndex,
      );
}
