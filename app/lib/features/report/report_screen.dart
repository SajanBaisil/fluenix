import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../services/profile.dart';
import '../../theme/app_theme.dart';

/// Call report (design/README.md §05). Shown right after the call ends;
/// polls for the analysis the backend is producing and renders it when it
/// lands.
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
      body: SafeArea(child: report == null ? _waiting() : _reportView(report)),
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
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Tokens.clay,
              ),
            ),
            const SizedBox(height: 26),
            Text('Analyzing your call…', style: Type.display(24)),
            const SizedBox(height: 8),
            const Text(
              'Your coach is going through everything you said.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Tokens.ink60, fontSize: 13.5),
            ),
          ] else ...[
            const Icon(Icons.schedule_rounded, color: Tokens.ink35, size: 44),
            const SizedBox(height: 18),
            Text('No report this time', style: Type.display(24)),
            const SizedBox(height: 8),
            const Text(
              'The call may have been too short to analyze.\n'
              'Try a longer conversation next time!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Tokens.ink60, fontSize: 13.5),
            ),
          ],
          const Spacer(),
          _doneButton(filled: true),
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

    final cefr = switch (ProfileService.current.level) {
      'beginner' => 'A2 · ELEMENTARY',
      'advanced' => 'C1 · ADVANCED',
      _ => 'B2 · UPPER INT.',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'CALL REPORT',
                style: Type.mono(10, color: Tokens.ink50, ls: 1.6),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Text('CLOSE ✕', style: Type.mono(10, color: Tokens.ink50)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // ── Score hero (ink, teal glow) ─────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(26)),
            // Teal glow bottom-right as the card's own radial gradient.
            gradient: RadialGradient(
              center: Alignment(1.2, 1.45),
              radius: 1.5,
              colors: [Color(0xFF122B26), Tokens.ink],
              stops: [0, 0.55],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$overall',
                    style: Type.display(74, color: Tokens.cream, height: 0.9),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'OVERALL / 100',
                    style: Type.mono(9.5, color: Tokens.cream45, ls: 1.4),
                  ),
                ],
              ),
              const Spacer(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Tokens.mint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        cefr,
                        style: Type.mono(
                          10,
                          color: Tokens.tealInk,
                          weight: FontWeight.w700,
                          ls: 0.6,
                        ),
                      ),
                    ),
                    if (headline.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        headline,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Tokens.cream45,
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Breakdown ───────────────────────────────────────
        _card(
          Column(
            children: [
              _skillRow('Fluency & coherence', scores['fluency'], Tokens.teal),
              const SizedBox(height: 15),
              _skillRow('Grammar range', scores['grammar'], Tokens.clay),
              const SizedBox(height: 15),
              _skillRow('Vocabulary', scores['vocabulary'], Tokens.teal),
              const SizedBox(height: 15),
              _skillRow('Confidence', scores['confidence'], Tokens.goldText),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Stats grid ──────────────────────────────────────
        Row(
          children: [
            _stat(
              '${(fillers['count'] as num?)?.toInt() ?? 0}',
              'FILLER\nWORDS',
              Tokens.ink,
            ),
            const SizedBox(width: 8),
            _stat(
              metrics['wpm'] != null ? '${metrics['wpm']}' : '—',
              'WORDS\nPER MIN',
              Tokens.goldText,
            ),
            const SizedBox(width: 8),
            _stat(
              metrics['talk_share_pct'] != null
                  ? '${metrics['talk_share_pct']}%'
                  : '—',
              'YOUR\nTALK TIME',
              Tokens.teal,
            ),
          ],
        ),
        if ((metrics['talk_share_pct'] as num? ?? 100) < 40)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Try longer answers — aim for about half the airtime.',
              style: const TextStyle(fontSize: 11, color: Tokens.ink50),
            ),
          ),
        // ── Fix these first ─────────────────────────────────
        if (issues.isNotEmpty) ...[
          _section('THREE THINGS TO FIX'),
          for (final issue in issues)
            _fixCard((issue as Map).cast<String, dynamic>()),
        ],
        // ── Say it better ───────────────────────────────────
        if (vocab.isNotEmpty) ...[
          _section('SAY IT BETTER'),
          _card(
            Column(
              children: [
                for (final (i, v) in vocab.indexed) ...[
                  if (i > 0) const Divider(height: 18, color: Tokens.hairline),
                  _vocabRow((v as Map).cast<String, dynamic>()),
                ],
              ],
            ),
          ),
        ],
        // ── Hinglish ────────────────────────────────────────
        if (hinglish.isNotEmpty) ...[
          _section('SAY IT IN ENGLISH'),
          for (final h in hinglish)
            _hinglishCard((h as Map).cast<String, dynamic>()),
        ],
        // ── Focus chips ─────────────────────────────────────
        if (focus.isNotEmpty) ...[
          _section('NEXT CALL, WORK ON'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in focus)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Tokens.clayTint,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0x40C9502B)),
                  ),
                  child: Text(
                    f.toString(),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Tokens.clay,
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        // ── Footer ──────────────────────────────────────────
        Row(
          children: [
            if (Config.supabaseUrl.isNotEmpty) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => _share(r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x2E14110F)),
                    ),
                    child: const Text(
                      'Share to group',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Tokens.ink,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(child: _doneButton(filled: true)),
          ],
        ),
      ],
    );
  }

  Widget _skillRow(String label, dynamic value, Color color) {
    final v = ((value as num?)?.toInt() ?? 0).clamp(0, 100);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text('$v', style: Type.mono(12, color: color, ls: 0.3)),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: v / 100,
              backgroundColor: Tokens.track,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Tokens.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Tokens.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Type.display(26, color: color)),
            const SizedBox(height: 5),
            Text(
              label,
              style: Type.mono(
                9.5,
                color: Tokens.ink35,
                weight: FontWeight.w500,
                ls: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fixCard(Map<String, dynamic> issue) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Tokens.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GRAMMAR',
            style: Type.mono(
              9,
              color: Tokens.clay,
              weight: FontWeight.w700,
              ls: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            issue['said'] ?? '',
            style: const TextStyle(
              color: Tokens.ink45,
              fontSize: 13,
              decoration: TextDecoration.lineThrough,
              decorationColor: Color(0x8CC9502B),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            issue['better'] ?? '',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Tokens.hairline)),
            ),
            child: Text(
              issue['why'] ?? '',
              style: const TextStyle(
                fontSize: 11.5,
                color: Tokens.ink50,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hinglishCard(Map<String, dynamic> h) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Tokens.goldTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HINGLISH → ENGLISH',
            style: Type.mono(
              9,
              color: Tokens.goldText,
              weight: FontWeight.w700,
              ls: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '"${h['said'] ?? ''}"',
            style: const TextStyle(
              color: Tokens.ink60,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            h['english'] ?? '',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
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
                  style: const TextStyle(color: Tokens.ink60, fontSize: 13.5),
                ),
                const TextSpan(
                  text: '  →  ',
                  style: TextStyle(color: Tokens.ink35, fontSize: 13.5),
                ),
                TextSpan(
                  text: '"${v['better'] ?? ''}"',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Text(title, style: Type.mono(10, color: Tokens.ink50, ls: 1.4)),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Tokens.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Tokens.hairline),
    ),
    child: child,
  );

  Widget _doneButton({bool filled = false}) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: filled ? Tokens.ink : null,
          borderRadius: BorderRadius.circular(999),
          border: filled ? null : Border.all(color: const Color(0x2E14110F)),
        ),
        child: Text(
          'Done',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: filled ? Tokens.cream : Tokens.ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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
          content: Text('Join a community first — see the Community tab'),
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Tokens.white,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Shared to ${picked['name']}')));
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
}
