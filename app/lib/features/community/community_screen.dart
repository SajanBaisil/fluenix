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

/// Each room keeps a signature color + tint through the app (design §07:
/// tinted tiles with display letters), like coaches do.
(Color, Color) communityStyle(String slug) => switch (slug) {
      'daily-english' => (Tokens.goldText, Tokens.goldTint),
      'interview-prep' => (Tokens.clay, Tokens.clayTint),
      'ielts-exams' => (Tokens.teal, Tokens.tealTint),
      'debate-club' => (Tokens.ink, Tokens.inkSoft),
      'wins-reports' => (Tokens.teal, Tokens.tealTint),
      _ => (Tokens.clay, Tokens.clayTint),
    };

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
              Text('Community', style: Type.display(30)),
              const SizedBox(height: 5),
              const Text(
                'Learners like you, practicing out loud.',
                style: TextStyle(fontSize: 13, color: Tokens.ink60),
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
    final (color, tint) = communityStyle(c.slug);
    return GestureDetector(
      onTap: () => _open(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Tokens.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Tokens.line),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(c.name[0], style: Type.display(20, color: color)),
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
