import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/profile.dart';
import '../../theme/app_theme.dart';
import '../coach/coaches.dart';
import 'call_screen.dart';

/// Call setup (design/README.md §03): pick a topic, level, and length before
/// dialing. Interview scenario swaps topic chips for a role/JD field.
class CallSetupScreen extends StatefulWidget {
  const CallSetupScreen({
    super.key,
    required this.coach,
    required this.scenario,
  });

  final Coach coach;
  final Scenario scenario;

  @override
  State<CallSetupScreen> createState() => _CallSetupScreenState();
}

class _CallSetupScreenState extends State<CallSetupScreen> {
  int _topic = 0;
  late String _level = switch (ProfileService.current.level) {
    'beginner' => 'B1',
    'advanced' => 'C1',
    _ => 'B2',
  };
  int _dur = 10;
  bool _captions = true;
  final _jd = TextEditingController();

  bool get _isInterview => widget.scenario.id == 'interview';

  List<String> get _topics => switch (widget.scenario.id) {
        'interview' => const [
            'HR round',
            'Technical round',
            'Salary talk',
            'Surprise me',
          ],
        'ielts' => const [
            'Part 1 · familiar topics',
            'Part 2 · cue card',
            'Part 3 · discussion',
            'Full mock',
          ],
        'debate' => const [
            'Technology',
            'Work culture',
            'City life',
            'Surprise me',
          ],
        _ => const [
            'Hometown & family',
            'Work & career',
            'Weekend plans',
            'Surprise me',
          ],
      };

  @override
  void initState() {
    super.initState();
    if (_isInterview) {
      SharedPreferences.getInstance().then((sp) {
        final saved = sp.getString('last_jd') ?? '';
        if (mounted && saved.isNotEmpty) setState(() => _jd.text = saved);
      });
    }
  }

  @override
  void dispose() {
    _jd.dispose();
    super.dispose();
  }

  Future<void> _startCall() async {
    final topic = _topics[_topic];
    final parts = <String>[];
    if (!topic.toLowerCase().contains('surprise')) {
      parts.add("Today's chosen topic: $topic.");
    }
    if (_isInterview && _jd.text.trim().isNotEmpty) {
      parts.add('The role/job description:\n${_jd.text.trim()}');
      final sp = await SharedPreferences.getInstance();
      await sp.setString('last_jd', _jd.text.trim());
    }
    final levelName = switch (_level) {
      'B1' => 'beginner',
      'C1' => 'advanced',
      _ => 'intermediate',
    };
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          coach: widget.coach,
          scenario: widget.scenario,
          scenarioContext: parts.join('\n\n'),
          levelOverride: levelName,
          targetMinutes: _dur,
          initialCc: _captions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.coach;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('← BACK',
                          style: Type.mono(11, color: Tokens.ink50)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Coach block, centered
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.tint,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(c.name[0],
                              style: Type.display(42, color: c.color)),
                        ),
                        const SizedBox(height: 14),
                        Text(c.name, style: Type.display(28)),
                        const SizedBox(height: 4),
                        Text(
                          c.role,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: c.color,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 270),
                          child: Text(
                            c.desc,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Tokens.ink60,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isInterview ? 'YOUR INTERVIEW' : "TODAY'S TOPIC",
                    style: Type.mono(10, color: Tokens.ink50),
                  ),
                  const SizedBox(height: 11),
                  if (_isInterview) ...[
                    TextField(
                      controller: _jd,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 1500,
                      style: const TextStyle(fontSize: 13.5, height: 1.5),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Role, company, or paste the JD — '
                            'the interviewer will use it. Optional.',
                        hintStyle: const TextStyle(
                            color: Tokens.ink35, fontSize: 12.5),
                        filled: true,
                        fillColor: Tokens.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: Tokens.hairline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: Tokens.hairline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: Tokens.clay, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (i, t) in _topics.indexed)
                        GestureDetector(
                          onTap: () => setState(() => _topic = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            decoration: BoxDecoration(
                              color: _topic == i
                                  ? Tokens.clayTint
                                  : Tokens.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _topic == i
                                    ? const Color(0x59C9502B)
                                    : const Color(0x1A14110F),
                              ),
                            ),
                            child: Text(
                              t,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color:
                                    _topic == i ? Tokens.clay : Tokens.ink60,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _segmented(
                          'LEVEL',
                          const ['B1', 'B2', 'C1'],
                          _level,
                          (v) => setState(() => _level = v),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: _segmented(
                          'LENGTH',
                          const ['5m', '10m', '20m'],
                          '${_dur}m',
                          (v) => setState(
                              () => _dur = int.parse(v.replaceAll('m', ''))),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Live captions row
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Tokens.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Tokens.hairline),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Live captions',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'See what you both said, as you speak',
                                style: TextStyle(
                                    fontSize: 11.5, color: Tokens.ink50),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _captions = !_captions),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 48,
                            height: 28,
                            padding: const EdgeInsets.all(3),
                            alignment: _captions
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            decoration: BoxDecoration(
                              color: _captions
                                  ? Tokens.clay
                                  : const Color(0x2E14110F),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox(width: 22, height: 22),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // CTA + metering note
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _startCall,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: Tokens.clay,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Call ${c.name} now',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'USES ~$_dur MIN OF YOUR DAILY FREE MINUTES',
                    style: Type.mono(9.5, color: Tokens.ink35, ls: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmented(String label, List<String> options, String value,
      ValueChanged<String> onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Type.mono(10, color: Tokens.ink50)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0x0E14110F),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              for (final o in options)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onPick(o),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: o == value ? Tokens.white : null,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        o,
                        textAlign: TextAlign.center,
                        style: Type.mono(
                          12,
                          color: o == value
                              ? Tokens.ink
                              : const Color(0x7314110F),
                          weight: FontWeight.w700,
                          ls: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
