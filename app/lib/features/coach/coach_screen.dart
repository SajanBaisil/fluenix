import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'coaches.dart';

/// Coach picker (mockup 05). Selection persists and applies to every call.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  String _selectedId = 'emma';

  @override
  void initState() {
    super.initState();
    CoachPrefs.selected().then((c) {
      if (mounted) setState(() => _selectedId = c.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          children: [
            const Text(
              'Choose your coach',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Each has a voice, a personality, and a specialty.',
              style: TextStyle(fontSize: 13, color: Tokens.muted),
            ),
            const SizedBox(height: 18),
            for (final c in coaches) ...[
              _coachCard(c),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _coachCard(Coach c) {
    final selected = c.id == _selectedId;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedId = c.id);
        CoachPrefs.select(c.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Tokens.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Tokens.indigo.withValues(alpha: 0.55)
                : Tokens.line,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Tokens.indigo.withValues(alpha: 0.12),
                    blurRadius: 0,
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: c.gradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                c.name[0],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.colors.first.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          c.tag,
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: Color.lerp(
                                c.colors.first, Colors.white, 0.45),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.desc,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Tokens.muted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_rounded, color: Tokens.indigo),
            ],
          ],
        ),
      ),
    );
  }
}
