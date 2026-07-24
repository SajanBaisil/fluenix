import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The learner's profile (public.profiles) — read/written directly through
/// RLS; cached for the session so prompts can use it synchronously.
class Profile {
  const Profile({
    required this.name,
    required this.level,
    required this.goal,
    required this.dailyTargetMin,
    required this.onboarded,
  });

  final String name;
  final String level; // beginner | intermediate | advanced
  final String goal; // interview | ielts | daily | business | abroad
  final int dailyTargetMin;
  final bool onboarded;

  static const fallback = Profile(
    name: '',
    level: 'intermediate',
    goal: 'daily',
    dailyTargetMin: 15,
    onboarded: true,
  );
}

abstract final class ProfileService {
  /// Session cache — call screens read this synchronously.
  static Profile current = Profile.fallback;

  static Future<Profile> load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return current;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row != null) {
        current = Profile(
          name: (row['name'] as String?) ?? '',
          level: (row['level'] as String?) ?? 'intermediate',
          goal: (row['goal'] as String?) ?? 'daily',
          dailyTargetMin: (row['daily_target_min'] as num?)?.toInt() ?? 15,
          onboarded: (row['onboarded'] as bool?) ?? false,
        );
      }
    } catch (e) {
      debugPrint('profile: load failed: $e');
    }
    return current;
  }

  static Future<void> save({
    required String name,
    required String level,
    required String goal,
    required int dailyTargetMin,
  }) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    await Supabase.instance.client.from('profiles').update({
      'name': name,
      'level': level,
      'goal': goal,
      'daily_target_min': dailyTargetMin,
      'onboarded': true,
    }).eq('id', uid);
    current = Profile(
      name: name,
      level: level,
      goal: goal,
      dailyTargetMin: dailyTargetMin,
      onboarded: true,
    );
  }
}
