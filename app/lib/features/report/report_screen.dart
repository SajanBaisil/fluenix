import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../theme/app_theme.dart';

/// Post-call report (mockup 03). Shown right after the call ends; polls for
/// the analysis the backend is producing and renders it when it lands.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.callId});
  final String callId;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  Map<String, dynamic>? _report;
  bool _timedOut = false;
  Timer? _poll;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final row = await Supabase.instance.client
          .from('reports')
          .select()
          .eq('call_id', widget.callId)
          .maybeSingle();
      if (!mounted) return;
      if (row != null) {
        setState(() => _report = row);
        return;
      }
    } catch (_) {
      // Transient — keep polling.
    }
    _attempts += 1;
    if (_attempts >= 30) {
      // ~75 s — analysis failed or the call was too short.
      if (mounted) setState(() => _timedOut = true);
      return;
    }
    _poll = Timer(const Duration(milliseconds: 2500), _check);
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      body: SafeArea(
        child: report == null ? _waiting() : _reportView(report),
      ),
    );
  }

  // ── Waiting / timeout ─────────────────────────────────────
  Widget _waiting() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Spacer(),
          if (!_timedOut) ...[
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Tokens.indigoSoft,
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Analyzing your call…',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your coach is going through everything you said.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Tokens.muted, fontSize: 13.5),
            ),
          ] else ...[
            const Icon(Icons.schedule_rounded,
                color: Tokens.faint, size: 44),
            const SizedBox(height: 18),
            const Text(
              'No report this time',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'The call may have been too short to analyze.\n'
              'Try a longer conversation next time!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Tokens.muted, fontSize: 13.5),
            ),
          ],
          const Spacer(),
          _doneButton(),
        ],
      ),
    );
  }

  // ── Report ────────────────────────────────────────────────
  Widget _reportView(Map<String, dynamic> r) {
    final overall = (r['overall'] as num?)?.toInt() ?? 0;
    final scores = (r['scores'] as Map?)?.cast<String, dynamic>() ?? {};
    final headline = (scores['headline'] as String?) ?? '';
    final issues = (r['grammar_issues'] as List?) ?? [];
    final vocab = (r['vocab_suggestions'] as List?) ?? [];
    final fillers = (r['filler_words'] as Map?)?.cast<String, dynamic>() ?? {};
    final focus = (r['focus_points'] as List?) ?? [];
    final metrics = (r['metrics'] as Map?)?.cast<String, dynamic>() ?? {};
    final hinglish =
        ((r['hinglish'] as Map?)?.cast<String, dynamic>() ?? {})['examples']
                as List? ??
            [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
      children: [
        const Text(
          'CALL REPORT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: Tokens.faint,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _scoreRing(overall),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                headline.isEmpty ? _labelFor(overall) : headline,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _statTile('Grammar', scores['grammar']),
            const SizedBox(width: 8),
            _statTile('Fluency', scores['fluency']),
            const SizedBox(width: 8),
            _statTile('Vocab', scores['vocabulary']),
            const SizedBox(width: 8),
            _statTile('Fillers', fillers['count'], isScore: false),
          ],
        ),
        if (metrics['talk_share_pct'] != null) ...[
          _section('AIRTIME'),
          _card(_airtime(metrics)),
        ],
        if (issues.isNotEmpty) ...[
          _section('FIX THESE FIRST'),
          _card(
            Column(
              children: [
                for (final (i, issue) in issues.indexed) ...[
                  if (i > 0) const Divider(height: 22, color: Tokens.line),
                  _fix((issue as Map).cast<String, dynamic>()),
                ],
              ],
            ),
          ),
        ],
        if (vocab.isNotEmpty) ...[
          _section('SAY IT BETTER'),
          _card(
            Column(
              children: [
                for (final (i, v) in vocab.indexed) ...[
                  if (i > 0) const Divider(height: 18, color: Tokens.line),
                  _vocabRow((v as Map).cast<String, dynamic>()),
                ],
              ],
            ),
          ),
        ],
        if (hinglish.isNotEmpty) ...[
          _section('SAY IT IN ENGLISH'),
          _card(
            Column(
              children: [
                for (final (i, h) in hinglish.indexed) ...[
                  if (i > 0) const Divider(height: 20, color: Tokens.line),
                  _hinglishRow((h as Map).cast<String, dynamic>()),
                ],
              ],
            ),
          ),
        ],
        if (focus.isNotEmpty) ...[
          _section('NEXT CALL, WORK ON'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in focus)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Tokens.indigo.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Tokens.indigo.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    f.toString(),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFDDE1FF),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        if (Config.supabaseUrl.isNotEmpty) ...[
          GestureDetector(
            onTap: () => _share(r),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: Tokens.indigo.withValues(alpha: 0.55)),
              ),
              child: const Text(
                'Share to community',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Tokens.indigoSoft,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _doneButton(),
      ],
    );
  }

  /// Post this report as a mini score card into one of the user's
  /// communities ("Wins & Reports" is the natural home).
  Future<void> _share(Map<String, dynamic> r) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    List<Map<String, dynamic>> joined;
    try {
      final rows = await client
          .from('community_members')
          .select('communities(id, name, emoji)')
          .eq('user_id', uid);
      joined = rows
          .map((row) => (row['communities'] as Map).cast<String, dynamic>())
          .toList();
    } catch (e) {
      debugPrint('report: share lookup failed: $e');
      return;
    }
    if (!mounted) return;
    if (joined.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Join a community first — see the Community tab')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Tokens.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 18, 22, 6),
              child: Text(
                'Share your report to…',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            for (final c in joined)
              ListTile(
                leading: Text(
                  (c['emoji'] as String?) ?? '💬',
                  style: const TextStyle(fontSize: 22),
                ),
                title: Text((c['name'] as String?) ?? ''),
                onTap: () => Navigator.pop(sheet, c),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final overall = (r['overall'] as num?)?.toInt() ?? 0;
    final scores = (r['scores'] as Map?)?.cast<String, dynamic>() ?? {};
    final headline = (scores['headline'] as String?) ?? '';
    try {
      await client.from('community_messages').insert({
        'community_id': picked['id'],
        'user_id': uid,
        'kind': 'report_share',
        'body': headline.isEmpty ? 'Shared a call report' : headline,
        'payload': {'overall': overall, 'headline': headline},
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Shared to ${picked['name']}')),
        );
      }
    } catch (e) {
      debugPrint('report: share failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't share — try again")),
        );
      }
    }
  }

  String _labelFor(int overall) => switch (overall) {
        >= 85 => 'Outstanding call!',
        >= 75 => 'Great call — keep it up!',
        >= 60 => 'Good call — clear progress.',
        _ => 'Good effort — every call counts.',
      };

  Widget _scoreRing(int overall) {
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: overall / 100,
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              color: Tokens.indigo,
              backgroundColor: const Color(0x1F94A3FF),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$overall',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                switch (overall) {
                  >= 85 => 'Excellent',
                  >= 75 => 'Great',
                  >= 60 => 'Good',
                  _ => 'Keep going',
                },
                style: const TextStyle(fontSize: 11, color: Tokens.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, dynamic value, {bool isScore = true}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Tokens.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Tokens.line),
        ),
        child: Column(
          children: [
            Text(
              '${(value as num?)?.toInt() ?? '—'}',
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Tokens.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: Tokens.faint,
          ),
        ),
      );

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tokens.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Tokens.line),
        ),
        child: child,
      );

  Widget _fix(Map<String, dynamic> issue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('✕ ',
                style: TextStyle(
                    color: Tokens.rose,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            Expanded(
              child: Text(
                issue['said'] ?? '',
                style: const TextStyle(
                  color: Tokens.muted,
                  fontSize: 13.5,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: Color(0x8CF87171),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('✓ ',
                style: TextStyle(
                    color: Tokens.mint,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            Expanded(
              child: Text(
                issue['better'] ?? '',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Text(
            issue['why'] ?? '',
            style: const TextStyle(
                fontSize: 11.5, color: Tokens.faint, height: 1.5),
          ),
        ),
      ],
    );
  }

  /// Talk-share bar + pace line, from the deterministic call metrics.
  Widget _airtime(Map<String, dynamic> m) {
    final share =
        ((m['talk_share_pct'] as num?)?.toInt() ?? 0).clamp(0, 100);
    final wpm = (m['wpm'] as num?)?.toInt();
    final pace = wpm == null
        ? ''
        : switch (wpm) {
            < 90 => 'steady pace',
            <= 150 => 'natural pace',
            _ => 'quick — slow down a touch',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                Expanded(
                  flex: share.clamp(3, 97),
                  child: const ColoredBox(color: Tokens.indigo),
                ),
                Expanded(
                  flex: (100 - share).clamp(3, 97),
                  child: const ColoredBox(color: Color(0x1F94A3FF)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'You spoke $share% of the call',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (wpm != null)
              Text(
                '$wpm wpm · $pace',
                style:
                    const TextStyle(fontSize: 12, color: Tokens.muted),
              ),
          ],
        ),
        if (share < 40) ...[
          const SizedBox(height: 6),
          const Text(
            'Try longer answers — aim for about half the airtime.',
            style: TextStyle(fontSize: 11.5, color: Tokens.faint),
          ),
        ],
      ],
    );
  }

  /// A Hinglish moment → the natural English version.
  Widget _hinglishRow(Map<String, dynamic> h) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '"${h['said'] ?? ''}"',
          style: const TextStyle(
            color: Tokens.muted,
            fontSize: 13.5,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('→ ',
                style: TextStyle(color: Tokens.faint, fontSize: 13.5)),
            Expanded(
              child: Text(
                h['english'] ?? '',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _vocabRow(Map<String, dynamic> v) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '"${v['used'] ?? ''}"',
                  style: const TextStyle(color: Tokens.muted, fontSize: 13.5),
                ),
                const TextSpan(
                  text: '  →  ',
                  style: TextStyle(color: Tokens.faint, fontSize: 13.5),
                ),
                TextSpan(
                  text: '"${v['better'] ?? ''}"',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _doneButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: Tokens.ctaGradient,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Done',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
