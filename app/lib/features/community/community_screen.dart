import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../theme/app_theme.dart';
import 'community_room_screen.dart';

/// A curated category room (rows are seeded server-side, never user-created).
class Community {
  const Community({
    required this.id,
    required this.slug,
    required this.name,
    required this.emoji,
    required this.description,
  });

  final String id;
  final String slug;
  final String name;
  final String emoji;
  final String description;

  static Community fromMap(Map<String, dynamic> m) => Community(
        id: m['id'] as String,
        slug: (m['slug'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        emoji: (m['emoji'] as String?) ?? '💬',
        description: (m['description'] as String?) ?? '',
      );
}

/// Each room keeps a signature gradient through the app, like coaches do.
LinearGradient communityGradient(String slug) {
  const map = {
    'interview-prep': [Color(0xFF0EA5E9), Color(0xFF6366F1)],
    'ielts-exams': [Color(0xFF34D399), Color(0xFF0EA5E9)],
    'daily-english': [Color(0xFFFBBF24), Color(0xFFF97316)],
    'debate-club': [Color(0xFFF472B6), Color(0xFFA855F7)],
    'wins-reports': [Color(0xFF6366F1), Color(0xFFA855F7)],
  };
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: map[slug] ?? const [Color(0xFF6366F1), Color(0xFFA855F7)],
  );
}

/// The Community tab: category rooms to join and chat in (Phase 1 of the
/// community platform — text spaces; group calls come later).
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => CommunityScreenState();
}

class CommunityScreenState extends State<CommunityScreen> {
  List<Community> _rooms = const [];
  Map<String, int> _counts = const {};
  Set<String> _joined = const {};
  bool _loading = true;

  // Seeded order, not alphabetical: easiest rooms first.
  static const _slugOrder = [
    'daily-english',
    'interview-prep',
    'ielts-exams',
    'debate-club',
    'wins-reports',
  ];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Public so the shell can refresh on tab switches.
  Future<void> refresh() async {
    if (Config.supabaseUrl.isEmpty) return;
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      final rooms = await client.from('communities').select();
      final members =
          await client.from('community_members').select('community_id,user_id');

      final counts = <String, int>{};
      final joined = <String>{};
      for (final m in members) {
        final cid = m['community_id'] as String;
        counts[cid] = (counts[cid] ?? 0) + 1;
        if (m['user_id'] == uid) joined.add(cid);
      }
      final parsed = rooms.map(Community.fromMap).toList()
        ..sort((a, b) {
          final ia = _slugOrder.indexOf(a.slug);
          final ib = _slugOrder.indexOf(b.slug);
          return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
        });
      if (mounted) {
        setState(() {
          _rooms = parsed;
          _counts = counts;
          _joined = joined;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('community: refresh failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join(Community c) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await client.from('community_members').insert({
        'community_id': c.id,
        'user_id': uid,
      });
    } catch (e) {
      debugPrint('community: join failed: $e'); // already joined → fine
    }
    await refresh();
  }

  void _open(Community c) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => CommunityRoomScreen(
              community: c,
              joined: _joined.contains(c.id),
            ),
          ),
        )
        .then((_) => refresh());
  }

  @override
  Widget build(BuildContext context) {
    if (Config.supabaseUrl.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Communities need an account —\nrun with the backend configured.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Tokens.muted, fontSize: 13.5),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: Tokens.indigoSoft,
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            children: [
              const Text(
                'Community',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              const Text(
                'Learners like you, practicing out loud.',
                style: TextStyle(fontSize: 13, color: Tokens.muted),
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 120),
                  child: Center(
                    child: CircularProgressIndicator(color: Tokens.indigoSoft),
                  ),
                )
              else
                for (final c in _rooms) _roomCard(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roomCard(Community c) {
    final joined = _joined.contains(c.id);
    final count = _counts[c.id] ?? 0;
    return GestureDetector(
      onTap: () => _open(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Tokens.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Tokens.line),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: communityGradient(c.slug),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(c.emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    c.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: Tokens.muted, height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    count == 1 ? '1 member' : '$count members',
                    style:
                        const TextStyle(fontSize: 10.5, color: Tokens.faint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            joined
                ? const Icon(Icons.chevron_right_rounded,
                    color: Tokens.faint, size: 22)
                : GestureDetector(
                    onTap: () => _join(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: Tokens.ctaGradient,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Join',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
