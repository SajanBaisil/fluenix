import 'package:flutter/material.dart';

import '../../services/profile.dart';
import '../../theme/app_theme.dart';

/// First-run setup (mockup 04): name → level → goal → daily target.
/// Everything lands in the profile and calibrates every future call.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final _name = TextEditingController();
  String _level = '';
  String _goal = '';
  int _target = 15;
  bool _saving = false;

  static const _levels = [
    ('beginner', 'Just starting', 'I know words but freeze in sentences'),
    ('intermediate', 'Getting there', 'I can talk, but I make mistakes'),
    ('advanced', 'Nearly fluent', 'I want polish, precision, confidence'),
  ];

  static const _goals = [
    ('interview', Icons.work_outline_rounded, 'Job interviews',
        'HR rounds, tech interviews, salary talk'),
    ('ielts', Icons.school_outlined, 'IELTS / PTE',
        'Speaking bands 6.5 and up'),
    ('daily', Icons.chat_bubble_outline_rounded, 'Daily conversation',
        'Small talk without freezing'),
    ('business', Icons.badge_outlined, 'Business & clients',
        'Meetings, standups, presentations'),
    ('abroad', Icons.flight_takeoff_rounded, 'Moving abroad',
        'Airports, banks, making friends'),
  ];

  static const _targets = [10, 15, 20, 30];

  bool get _canContinue => switch (_step) {
        0 => _name.text.trim().isNotEmpty,
        1 => _level.isNotEmpty,
        2 => _goal.isNotEmpty,
        _ => true,
      };

  Future<void> _next() async {
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    setState(() => _saving = true);
    try {
      await ProfileService.save(
        name: _name.text.trim(),
        level: _level,
        goal: _goal,
        dailyTargetMin: _target,
      );
      widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save — check connection")),
        );
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 24,
                      height: 4,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i <= _step
                            ? Tokens.indigo
                            : Tokens.line,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 26),
              Expanded(
                child: SingleChildScrollView(child: _stepContent()),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 22, top: 10),
                child: GestureDetector(
                  onTap: _canContinue && !_saving ? _next : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _canContinue ? 1 : 0.4,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: Tokens.ctaGradient,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: _saving
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white),
                              ),
                            )
                          : Text(
                              _step < 3 ? 'Continue' : "Let's talk!",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepContent() {
    return switch (_step) {
      0 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title("What should your\ncoach call you?"),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Your name',
                hintStyle: const TextStyle(color: Tokens.faint),
                filled: true,
                fillColor: Tokens.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Tokens.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Tokens.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Tokens.indigo, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      1 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('How is your English\nright now?'),
            _sub('Be honest — your coach adjusts to you.'),
            const SizedBox(height: 18),
            for (final (id, t, d) in _levels)
              _option(
                selected: _level == id,
                title: t,
                desc: d,
                onTap: () => setState(() => _level = id),
              ),
          ],
        ),
      2 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('What are you\nimproving it for?'),
            _sub('Your coach shapes every call around this.'),
            const SizedBox(height: 18),
            for (final (id, icon, t, d) in _goals)
              _option(
                selected: _goal == id,
                title: t,
                desc: d,
                icon: icon,
                onTap: () => setState(() => _goal = id),
              ),
          ],
        ),
      _ => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Daily speaking goal?'),
            _sub('Consistency beats length — small daily calls work.'),
            const SizedBox(height: 18),
            Row(
              children: [
                for (final t in _targets) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _target = t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: _target == t
                              ? Tokens.indigo.withValues(alpha: 0.16)
                              : Tokens.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _target == t
                                ? Tokens.indigo
                                : Tokens.line,
                            width: _target == t ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$t',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800),
                            ),
                            const Text(
                              'min',
                              style: TextStyle(
                                  fontSize: 11, color: Tokens.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (t != _targets.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ),
    };
  }

  Widget _title(String t) => Text(t, style: Type.display(30, height: 1.15));

  Widget _sub(String t) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          t,
          style: const TextStyle(fontSize: 13, color: Tokens.muted),
        ),
      );

  Widget _option({
    required bool selected,
    required String title,
    required String desc,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected
              ? Tokens.indigo.withValues(alpha: 0.12)
              : Tokens.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? Tokens.indigo : Tokens.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? Tokens.indigo.withValues(alpha: 0.25)
                      : Tokens.cardHi,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: Tokens.indigoSoft),
              ),
              const SizedBox(width: 13),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 12, color: Tokens.muted)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: Tokens.indigo),
          ],
        ),
      ),
    );
  }
}
