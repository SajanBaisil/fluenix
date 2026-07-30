import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../theme/app_theme.dart';
import 'drill_runner_screen.dart';

/// Practice tab: drills generated from the learner's own recent mistakes,
/// plus review material — study between calls, then apply it live.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => PracticeScreenState();
}

class PracticeScreenState extends State<PracticeScreen> {
  PracticePack? _pack;
  DailyPack? _daily;
  bool _dailyLoading = true;
  bool _loading = true;
  bool _failed = false;
  final Set<int> _revealed = {};
  final Set<int> _done = {};

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    unawaited(_loadDaily());
    if (_pack != null) return; // keep the generated pack for the session
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final pack = await Api.practice();
      if (mounted) {
        setState(() {
          _pack = pack;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _loadDaily() async {
    try {
      final daily = await Api.daily();
      if (mounted) {
        setState(() {
          _daily = daily;
          _dailyLoading = false;
        });
      }
    } catch (e) {
      debugPrint('practice: daily load failed: $e');
      if (mounted) setState(() => _dailyLoading = false);
    }
  }

  void _startRunner() {
    final daily = _daily;
    if (daily == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => DrillRunnerScreen(pack: daily),
          ),
        )
        .then((_) {
          Api.invalidateWeek(); // streak may have changed
          _loadDaily();
        });
  }

  Future<void> _regenerate() async {
    setState(() {
      _pack = null;
      _revealed.clear();
      _done.clear();
    });
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Text('Practice', style: Type.display(30)),
            const SizedBox(height: 5),
            const Text(
              'A little every day beats a lot once a week.',
              style: TextStyle(fontSize: 13, color: Tokens.ink60),
            ),
            const SizedBox(height: 16),
            _dailyHero(),
            ..._callsSections(),
          ],
        ),
      ),
    );
  }

  /// The "Today's 5" hero (teal, mint glow): state-aware CTA + streak.
  Widget _dailyHero() {
    final daily = _daily;
    final done = daily?.done.length ?? 0;
    final total = daily?.items.length ?? 5;
    final streak = daily?.streak ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(26)),
        gradient: RadialGradient(
          center: Alignment(1.2, -1.4),
          radius: 1.5,
          colors: [Color(0xFF327D6D), Tokens.teal],
          stops: [0, 0.55],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            streak > 0 ? "TODAY'S 5 · DAY $streak" : "TODAY'S 5",
            style: Type.mono(9.5, color: const Color(0xB8F6F1E8), ls: 1.6),
          ),
          const SizedBox(height: 7),
          Text(
            _dailyLoading
                ? 'Preparing your five…'
                : daily == null
                ? "Couldn't load today's five"
                : daily.completed
                ? 'All five, done. See you tomorrow.'
                : 'Your daily five is ready',
            style: Type.display(24, color: Tokens.cream),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (_dailyLoading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Tokens.cream,
                  ),
                )
              else
                GestureDetector(
                  onTap: daily == null
                      ? () {
                          setState(() => _dailyLoading = true);
                          _loadDaily();
                        }
                      : _startRunner,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Tokens.cream,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      daily == null
                          ? 'Retry'
                          : daily.completed
                          ? 'Review'
                          : done > 0
                          ? 'Continue'
                          : 'Start — 4 min',
                      style: const TextStyle(
                        color: Tokens.teal,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              if (daily != null)
                Text(
                  '$done / $total DONE',
                  style: Type.mono(10, color: const Color(0xB8F6F1E8), ls: 1),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The "from your calls" material below the daily hero.
  List<Widget> _callsSections() {
    final pack = _pack;
    if (_loading) {
      return [
        _label('FROM YOUR CALLS'),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: CircularProgressIndicator(color: Tokens.clay)),
        ),
      ];
    }
    if (_failed) {
      return [
        _label('FROM YOUR CALLS'),
        _card(
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Couldn't load your call drills.",
                  style: TextStyle(fontSize: 13, color: Tokens.ink60),
                ),
              ),
              TextButton(
                onPressed: _regenerate,
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Tokens.clay),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    if (pack == null || pack.isEmpty) {
      return [
        _label('FROM YOUR CALLS'),
        _card(
          const Text(
            'Finish a call and your own mistakes become extra drills here.',
            style: TextStyle(fontSize: 13, color: Tokens.ink60, height: 1.5),
          ),
        ),
      ];
    }
    return [
      if (pack.exercises.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'MORE DRILLS · FROM YOUR CALLS',
                  style: Type.mono(10, color: Tokens.ink50, ls: 1.4),
                ),
              ),
              GestureDetector(
                onTap: _regenerate,
                child: const Icon(
                  Icons.refresh_rounded,
                  size: 17,
                  color: Tokens.ink35,
                ),
              ),
            ],
          ),
        ),
        for (final (i, ex) in pack.exercises.indexed) _drill(i, ex),
      ],
      if (pack.mistakes.isNotEmpty) ...[
        _label('FROM YOUR RECENT CALLS'),
        _card(
          Column(
            children: [
              for (final (i, m) in pack.mistakes.indexed) ...[
                if (i > 0) const Divider(height: 20, color: Tokens.line),
                _mistakeRow(m),
              ],
            ],
          ),
        ),
      ],
      if (pack.vocab.isNotEmpty) ...[
        _label('WORDS TO UPGRADE'),
        _card(
          Column(
            children: [
              for (final (i, v) in pack.vocab.indexed) ...[
                if (i > 0) const Divider(height: 16, color: Tokens.line),
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '"${v['used'] ?? ''}"',
                              style: const TextStyle(
                                color: Tokens.muted,
                                fontSize: 13.5,
                              ),
                            ),
                            const TextSpan(
                              text: '  →  ',
                              style: TextStyle(color: Tokens.faint),
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
                ),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  Widget _drill(int i, PracticeExercise ex) {
    final revealed = _revealed.contains(i);
    final done = _done.contains(i);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Tokens.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: done ? const Color(0x730F5951) : Tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Tokens.clayTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  switch (ex.kind) {
                    'fix' => 'FIX IT',
                    'choose' => 'PICK ONE',
                    _ => 'UPGRADE',
                  },
                  style: Type.mono(
                    8.5,
                    color: Tokens.clay,
                    weight: FontWeight.w700,
                    ls: 0.7,
                  ),
                ),
              ),
              const Spacer(),
              if (done)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Tokens.teal,
                  size: 18,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ex.prompt,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          if (!revealed)
            GestureDetector(
              onTap: () => setState(() => _revealed.add(i)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Tokens.inkSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Say it out loud, then reveal the answer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Tokens.clay,
                  ),
                ),
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '✓ ',
                  style: TextStyle(
                    color: Tokens.teal,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Expanded(
                  child: Text(
                    ex.answer,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Text(
                ex.why,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Tokens.faint,
                  height: 1.5,
                ),
              ),
            ),
            if (!done) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _done.add(i)),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Tokens.tealTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Got it',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Tokens.teal,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _mistakeRow(Map<String, dynamic> m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          m['said'] ?? '',
          style: const TextStyle(
            color: Tokens.muted,
            fontSize: 13,
            decoration: TextDecoration.lineThrough,
            decorationColor: Color(0x8CC9502B),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          m['better'] ?? '',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Tokens.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Tokens.line),
    ),
    child: child,
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Text(text, style: Type.mono(10, color: Tokens.ink50, ls: 1.4)),
  );
}
