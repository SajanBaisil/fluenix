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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        Text('Practice', style: Type.display(30)),
        const SizedBox(height: 5),
        const Text(
          'Made from your own mistakes — clear these before your next call.',
          style: TextStyle(fontSize: 13, color: Tokens.ink60),
        ),
        const SizedBox(height: 16),
        // Teal hero (design §06)
        ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Container(
            padding: const EdgeInsets.all(20),
            color: Tokens.teal,
            child: Stack(
              children: [
                Positioned(
                  top: -60,
                  right: -40,
                  child: Container(
                    width: 170,
                    height: 170,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x527BC9A8), Colors.transparent],
                        stops: [0, 0.9],
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TODAY\'S DRILLS',
                        style: Type.mono(9.5,
                            color: const Color(0xB8F6F1E8), ls: 1.6)),
                    const SizedBox(height: 7),
                    Text('Fix it before the next call',
                        style: Type.display(24, color: Tokens.cream)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _regenerate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 11),
                            decoration: BoxDecoration(
                              color: Tokens.cream,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'New drills',
                              style: TextStyle(
                                color: Tokens.teal,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_done.length} / ${pack.exercises.length} DONE',
                          style: Type.mono(10,
                              color: const Color(0xB8F6F1E8), ls: 1),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (pack.exercises.isNotEmpty) ...[
          _label('DRILLS'),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: done ? const Color(0x730F5951) : Tokens.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  style: Type.mono(8.5,
                      color: Tokens.clay, weight: FontWeight.w700, ls: 0.7),
                ),
              ),
              const Spacer(),
              if (done)
                const Icon(Icons.check_circle_rounded,
                    color: Tokens.teal, size: 18),
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
                const Text('✓ ',
                    style: TextStyle(
                        color: Tokens.teal,
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
