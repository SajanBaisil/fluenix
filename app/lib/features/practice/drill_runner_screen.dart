import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../theme/app_theme.dart';

/// "Today's 5" runner: one drill card at a time with progress dots and a
/// streak finish screen (BUSINESS.md §5, Sprint 1 — text drills).
class DrillRunnerScreen extends StatefulWidget {
  const DrillRunnerScreen({super.key, required this.pack});
  final DailyPack pack;

  @override
  State<DrillRunnerScreen> createState() => _DrillRunnerScreenState();
}

class _DrillRunnerScreenState extends State<DrillRunnerScreen> {
  late int _index = () {
    // Resume where they left off.
    for (var i = 0; i < widget.pack.items.length; i++) {
      if (!widget.pack.done.contains(i)) return i;
    }
    return 0;
  }();
  late final Set<int> _done = {...widget.pack.done};
  int? _picked; // mcq: chosen option index
  bool _revealed = false; // rewrite/speak: answer shown
  int _correct = 0;
  bool _finished = false;
  int _streak = 0;

  DailyItem get _item => widget.pack.items[_index];
  bool get _isLast => _index >= widget.pack.items.length - 1;

  Future<void> _completeCurrent() async {
    if (_done.add(_index)) {
      try {
        final res = await Api.dailyComplete(_index);
        _streak = (res['streak'] as num?)?.toInt() ?? _streak;
      } catch (e) {
        debugPrint('daily: complete failed: $e'); // retried on next open
      }
    }
    if (!mounted) return;
    if (_isLast) {
      setState(() => _finished = true);
    } else {
      setState(() {
        _index += 1;
        _picked = null;
        _revealed = false;
      });
    }
  }

  void _pick(int i) {
    if (_picked != null) return; // locked in
    final correct = _item.options[i] == _item.answer;
    setState(() => _picked = i);
    if (correct) _correct += 1;
    // Show the why for a beat, then advance.
    Timer(Duration(milliseconds: correct ? 900 : 1800), () {
      if (mounted) _completeCurrent();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _finished ? _finishView() : _drillView()),
    );
  }

  // ── Drill card ────────────────────────────────────────────
  Widget _drillView() {
    final item = _item;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Text(
                  'CLOSE ✕',
                  style: Type.mono(10, color: Tokens.ink50),
                ),
              ),
              const Spacer(),
              for (var i = 0; i < widget.pack.items.length; i++)
                Container(
                  width: 22,
                  height: 4,
                  margin: const EdgeInsets.only(left: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _done.contains(i) || i < _index
                        ? Tokens.clay
                        : i == _index
                        ? Tokens.claySoft
                        : Tokens.track,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            switch (item.kind) {
              'rewrite' => 'FIX IT',
              'speak' => 'SAY IT OUT LOUD',
              _ => 'PICK ONE',
            },
            style: Type.mono(
              10,
              color: Tokens.clay,
              weight: FontWeight.w700,
              ls: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.prompt,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: SingleChildScrollView(
              child: switch (item.kind) {
                'mcq' => _mcqBody(item),
                _ => _revealBody(item),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _mcqBody(DailyItem item) {
    return Column(
      children: [
        for (final (i, opt) in item.options.indexed)
          GestureDetector(
            onTap: () => _pick(i),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: _picked == null
                    ? Tokens.white
                    : opt == item.answer
                    ? Tokens.tealTint
                    : _picked == i
                    ? Tokens.clayTint
                    : Tokens.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _picked == null
                      ? Tokens.hairline
                      : opt == item.answer
                      ? Tokens.teal
                      : _picked == i
                      ? Tokens.clay
                      : Tokens.hairline,
                ),
              ),
              child: Text(
                opt,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ),
        if (_picked != null) ...[const SizedBox(height: 6), _whyCard(item.why)],
      ],
    );
  }

  Widget _revealBody(DailyItem item) {
    final isSpeak = item.kind == 'speak';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_revealed)
          GestureDetector(
            onTap: () => setState(() => _revealed = true),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Tokens.inkSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                isSpeak
                    ? 'Say your answer out loud, then compare'
                    : 'Say the fix out loud, then reveal',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Tokens.clay,
                ),
              ),
            ),
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Tokens.tealTint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSpeak ? 'A STRONG ANSWER' : 'THE FIX',
                  style: Type.mono(
                    9,
                    color: Tokens.teal,
                    weight: FontWeight.w700,
                    ls: 1.2,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  item.answer,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _whyCard(item.why),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _completeCurrent,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: Tokens.clay,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _isLast ? 'Finish' : 'Next',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _whyCard(String why) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Tokens.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tokens.hairline),
      ),
      child: Text(
        why,
        style: const TextStyle(
          fontSize: 12.5,
          color: Tokens.ink60,
          height: 1.5,
        ),
      ),
    );
  }

  // ── Finish ────────────────────────────────────────────────
  Widget _finishView() {
    final scored = widget.pack.items.where((i) => i.kind == 'mcq').length;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 110,
              height: 110,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFF5C2A1A), Tokens.ink],
                  stops: [0, 0.9],
                ),
              ),
              child: Text(
                '$_streak',
                style: Type.display(44, color: Tokens.cream),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              _streak == 1 ? 'DAY 1 — STREAK STARTED' : 'DAY $_streak STREAK',
              style: Type.mono(
                11,
                color: Tokens.clay,
                weight: FontWeight.w700,
                ls: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(child: Text("Today's 5, done.", style: Type.display(28))),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '$_correct of $scored scored drills right on the first try. '
              'A call keeps tomorrow easy.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Tokens.ink60,
                height: 1.5,
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: Tokens.ink,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Done',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Tokens.cream,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
