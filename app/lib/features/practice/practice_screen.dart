import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../theme/app_theme.dart';

/// Practice tab: drills generated from the learner's own recent mistakes,
/// plus review material — study between calls, then apply it live.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => PracticeScreenState();
}

class PracticeScreenState extends State<PracticeScreen> {
  PracticePack? _pack;
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
    final pack = _pack;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Tokens.indigoSoft),
                    SizedBox(height: 18),
                    Text(
                      'Building drills from your mistakes…',
                      style: TextStyle(color: Tokens.muted, fontSize: 13),
                    ),
                  ],
                ),
              )
            : _failed
                ? _message(
                    Icons.cloud_off_rounded,
                    "Couldn't load practice",
                    'Check your connection and pull to retry.',
                    retry: true,
                  )
                : (pack == null || pack.isEmpty)
                    ? _message(
                        Icons.fitness_center_rounded,
                        'Nothing to practice yet',
                        'Finish a call and your mistakes become drills here.',
                      )
                    : _content(pack),
      ),
    );
  }

  Widget _message(IconData icon, String title, String sub,
      {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Tokens.faint),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(sub,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Tokens.muted, fontSize: 13)),
            if (retry) ...[
              const SizedBox(height: 18),
              TextButton(
                onPressed: _regenerate,
                child: const Text('Retry',
                    style: TextStyle(color: Tokens.indigoSoft)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _content(PracticePack pack) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Practice',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'New drills',
              onPressed: _regenerate,
              icon: const Icon(Icons.refresh_rounded,
                  color: Tokens.faint, size: 20),
            ),
          ],
        ),
        const Text(
          'Made from your own mistakes — clear these before your next call.',
          style: TextStyle(fontSize: 13, color: Tokens.muted),
        ),
        if (pack.exercises.isNotEmpty) ...[
          _label('DRILLS · ${_done.length}/${pack.exercises.length} DONE'),
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
                          TextSpan(children: [
                            TextSpan(
                              text: '"${v['used'] ?? ''}"',
                              style: const TextStyle(
                                  color: Tokens.muted, fontSize: 13.5),
                            ),
                            const TextSpan(
                                text: '  →  ',
                                style: TextStyle(color: Tokens.faint)),
                            TextSpan(
                              text: '"${v['better'] ?? ''}"',
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _drill(int i, PracticeExercise ex) {
    final revealed = _revealed.contains(i);
    final done = _done.contains(i);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Tokens.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: done ? Tokens.mint.withValues(alpha: 0.45) : Tokens.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Tokens.indigo.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  switch (ex.kind) {
                    'fix' => 'FIX IT',
                    'choose' => 'PICK ONE',
                    _ => 'UPGRADE',
                  },
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: Tokens.indigoSoft,
                  ),
                ),
              ),
              const Spacer(),
              if (done)
                const Icon(Icons.check_circle_rounded,
                    color: Tokens.mint, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ex.prompt,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (!revealed)
            GestureDetector(
              onTap: () => setState(() => _revealed.add(i)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Tokens.cardHi,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tokens.line),
                ),
                child: const Text(
                  'Say it out loud, then reveal the answer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Tokens.indigoSoft,
                  ),
                ),
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('✓ ',
                    style: TextStyle(
                        color: Tokens.mint,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                Expanded(
                  child: Text(
                    ex.answer,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.45),
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
                    fontSize: 11.5, color: Tokens.faint, height: 1.5),
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
                    color: Tokens.mint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Got it',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Tokens.mint,
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
            decorationColor: Color(0x8CF87171),
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
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: Tokens.faint,
          ),
        ),
      );
}
