import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../call/call_setup_screen.dart';
import 'coaches.dart';

/// Coaches (design/README.md §02): filterable roster of monogram cards.
/// Tapping a coach makes them the default and opens call setup.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  String _selectedId = 'emma';
  String _filter = 'all';

  static const _filters = [
    ('all', 'All coaches'),
    ('ielts', 'IELTS & exams'),
    ('interview', 'Interview'),
    ('daily', 'Daily English'),
    ('gentle', 'Gentle start'),
  ];

  static const _coachFilter = {
    'asha': 'gentle',
    'emma': 'daily',
    'david': 'interview',
    'leo': 'ielts',
  };

  @override
  void initState() {
    super.initState();
    CoachPrefs.selected().then((c) {
      if (mounted) setState(() => _selectedId = c.id);
    });
  }

  void _open(Coach c) {
    setState(() => _selectedId = c.id);
    CoachPrefs.select(c.id);
    final scenario = switch (c.id) {
      'david' => scenarioById('interview'),
      'leo' => scenarioById('ielts'),
      _ => scenarios[0],
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallSetupScreen(coach: c, scenario: scenario),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = coaches
        .where((c) => _filter == 'all' || _coachFilter[c.id] == _filter)
        .toList();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Text('Coaches', style: Type.display(30)),
            const SizedBox(height: 5),
            const Text(
              'Each has a voice, a personality, and a specialty.',
              style: TextStyle(fontSize: 13, color: Tokens.ink60),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final (id, label) = _filters[i];
                  final on = _filter == id;
                  return GestureDetector(
                    onTap: () => setState(() => _filter = id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? Tokens.ink : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color:
                              on ? Tokens.ink : const Color(0x2414110F),
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: on ? Tokens.cream : Tokens.ink60,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            for (final c in visible) ...[
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
      onTap: () => _open(c),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tokens.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? const Color(0x47C9502B) : Tokens.hairline,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.tint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(c.name[0], style: Type.display(24, color: c.color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (selected)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text('YOURS',
                              style: Type.mono(8.5,
                                  color: Tokens.clay,
                                  weight: FontWeight.w700)),
                        ),
                      Text('★ ${c.rating}',
                          style: Type.mono(10.5,
                              color: Tokens.ink50, ls: 0.3)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    c.role,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.color,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    c.desc,
                    style: const TextStyle(
                        fontSize: 11.5, color: Tokens.ink60, height: 1.45),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _meta(c.accent),
                      const SizedBox(width: 7),
                      _meta(c.focus),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x0D14110F),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: Type.mono(9.5,
                color: Tokens.ink60, weight: FontWeight.w500, ls: 0.4)),
      );
}
