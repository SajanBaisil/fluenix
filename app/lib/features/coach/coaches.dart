import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/profile.dart';
import '../../theme/app_theme.dart';

/// The coach roster (PLAN.md §3, design/README.md §02). Each coach is a
/// personality, a voice, and a signature color + tint that follows them
/// through the app (monogram tiles, role text, chips).
class Coach {
  const Coach({
    required this.id,
    required this.name,
    required this.tag,
    required this.role,
    required this.desc,
    required this.voice,
    required this.color,
    required this.tint,
    required this.accent,
    required this.focus,
    required this.rating,
    required this.persona,
  });

  final String id;
  final String name;
  final String tag;

  /// Short role line shown in the coach's color ("Interview Coach").
  final String role;
  final String desc;

  /// Gemini prebuilt voice name.
  final String voice;

  /// Signature color (monogram letter, role text) + soft tint (tile bg).
  final Color color;
  final Color tint;

  /// Meta chips: voice accent + specialty focus.
  final String accent;
  final String focus;
  final String rating;
  final String persona;

  // Legacy shims for widgets not yet migrated to color/tint.
  List<Color> get colors => [color, color];
  LinearGradient get gradient => LinearGradient(colors: [color, color]);
}

const coaches = [
  Coach(
    id: 'asha',
    name: 'Asha',
    tag: 'PATIENT',
    role: 'Gentle-Start Coach',
    desc: 'Speaks slowly, explains simply. The gentlest way to start.',
    voice: 'Kore',
    color: Tokens.ink,
    tint: Tokens.inkSoft,
    accent: 'Slow & clear',
    focus: 'Confidence',
    rating: '4.9',
    persona: 'You are Asha, a warm and endlessly patient English coach from '
        'Bengaluru. You understand exactly how Indian learners think because '
        'you learned English yourself. Speak a little slower than normal, use '
        'simple words, and never use idioms without explaining them. When the '
        'learner struggles, reassure them and offer the word they are '
        'looking for.',
  ),
  Coach(
    id: 'emma',
    name: 'Emma',
    tag: 'FRIENDLY',
    role: 'Daily English Partner',
    desc: 'Chatty American friend — interrupts, laughs, asks follow-ups.',
    voice: 'Aoede',
    color: Tokens.goldText,
    tint: Tokens.goldTint,
    accent: 'Warm American',
    focus: 'Small talk',
    rating: '4.9',
    persona: 'You are Emma, a cheerful American in your late twenties talking '
        'to a friend on the phone. Be genuinely curious, react naturally '
        '("oh really?", "no way!"), laugh sometimes, and ask playful '
        'follow-up questions. Keep the energy up.',
  ),
  Coach(
    id: 'david',
    name: 'David',
    tag: 'INTERVIEWER',
    role: 'Interview Coach',
    desc: 'Strict HR manager. Presses on weak answers — like the real thing.',
    voice: 'Charon',
    color: Tokens.clay,
    tint: Tokens.clayTint,
    accent: 'Neutral Indian',
    focus: 'HR + tech rounds',
    rating: '4.8',
    persona: 'You are David, a senior HR manager conducting a professional '
        'job interview. Be polite but businesslike. Ask one interview '
        'question at a time, press with follow-ups when answers are vague '
        '("Can you give me a specific example?"), and occasionally challenge '
        'the candidate the way a real interviewer would.',
  ),
  Coach(
    id: 'leo',
    name: 'Leo',
    tag: 'EXAMINER',
    role: 'IELTS Speaking Examiner',
    desc: 'Runs real IELTS speaking parts 1–3 with examiner-style questions.',
    voice: 'Orus',
    color: Tokens.teal,
    tint: Tokens.tealTint,
    accent: 'British RP',
    focus: 'Band 6.5 → 8.0',
    rating: '4.9',
    persona: 'You are Leo, an IELTS speaking examiner. Run the session like '
        'the real test: Part 1 (familiar topics), then Part 2 (give a cue '
        'card topic, let them speak for 1-2 minutes), then Part 3 (abstract '
        'discussion). Stay neutral and professional like a real examiner — '
        'no teaching during the test.',
  ),
];

Coach coachById(String id) =>
    coaches.firstWhere((c) => c.id == id, orElse: () => coaches[1]);

/// Conversation scenarios (mockup 01 quick-picks).
class Scenario {
  const Scenario({
    required this.id,
    required this.title,
    required this.icon,
    required this.brief,
  });

  final String id;
  final String title;
  final IconData icon;
  final String brief;
}

const scenarios = [
  Scenario(
    id: 'casual',
    title: 'Daily chat',
    icon: Icons.chat_bubble_outline_rounded,
    brief: 'This is a casual get-to-know-you phone call. Talk about their '
        'day, work, plans, and interests.',
  ),
  Scenario(
    id: 'interview',
    title: 'Job interview',
    icon: Icons.work_outline_rounded,
    brief: 'Simulate a realistic job interview for a software role. Cover '
        'introduction, experience, strengths, and one situational question.',
  ),
  Scenario(
    id: 'ielts',
    title: 'IELTS practice',
    icon: Icons.school_outlined,
    brief: 'Run an IELTS-style speaking practice with structured questions '
        'that push for longer, more detailed answers.',
  ),
  Scenario(
    id: 'debate',
    title: 'Debate me',
    icon: Icons.forum_outlined,
    brief: 'Pick a light debate topic and take the opposite side. Challenge '
        'their points and make them defend their opinion.',
  ),
];

Scenario scenarioById(String id) =>
    scenarios.firstWhere((s) => s.id == id, orElse: () => scenarios[0]);

/// Shared coaching rules + persona + scenario + the learner's current focus
/// points (from their last report) — the whole system prompt for a call.
String buildSystemPrompt(
  Coach coach,
  Scenario scenario,
  List<String> focusPoints, {
  String memory = '',
  int? lastCallDaysAgo,
  String scenarioContext = '',
  String levelOverride = '',
  int? targetMinutes,
}) {
  final focus = focusPoints.isEmpty
      ? ''
      : '\n\nThe learner is currently working on:\n'
          '${focusPoints.map((f) => '- $f').join('\n')}\n'
          'Naturally steer the conversation to give them chances to practice '
          'these. If they slip, sometimes gently recast their sentence in '
          'your reply — never lecture.';

  final p = ProfileService.current;
  final level = levelOverride.isNotEmpty ? levelOverride : p.level;
  final levelHint = switch (level) {
    'beginner' => 'Use short, simple sentences and everyday words. Speak a '
        'touch slower. Celebrate small wins.',
    'advanced' => 'Use rich, natural vocabulary and idioms. Push them with '
        'follow-ups that demand precision.',
    _ => 'Use natural everyday language; stretch their vocabulary gently.',
  };
  final goalLabel = switch (p.goal) {
    'interview' => 'preparing for job interviews',
    'ielts' => 'preparing for IELTS/PTE speaking',
    'business' => 'improving business and client communication',
    'abroad' => 'preparing to move abroad',
    _ => 'improving everyday conversation',
  };
  final learner = '\n\nAbout the learner: '
      '${p.name.isNotEmpty ? 'Their name is ${p.name} — use it naturally. ' : ''}'
      'Their level is $level. $levelHint '
      'Their overall goal is $goalLabel.'
      '${targetMinutes != null ? ' They planned roughly $targetMinutes '
          'minutes for this call — start wrapping up naturally as that '
          'approaches.' : ''}';

  var continuity = '';
  if (memory.isNotEmpty) {
    final when = switch (lastCallDaysAgo) {
      null => 'recently',
      0 => 'earlier today',
      1 => 'yesterday',
      final d => '$d days ago',
    };
    continuity = '\n\nYou have spoken with this learner before (last call '
        '$when). What you remember about them:\n$memory\n'
        'Open the call like a friend who remembers them: welcome them back '
        'warmly and follow up on something specific from what you remember '
        'before moving to new topics. Keep it brief and natural — one '
        'welcome-back line, one follow-up question. In interview or exam '
        'scenarios keep the welcome short and professional.';
  }

  final context = scenarioContext.trim().isEmpty
      ? ''
      : '\n\nSpecific context for this session (use it — reference the '
          'actual role/company/details naturally):\n${scenarioContext.trim()}';

  return '''${coach.persona}

Scenario: ${scenario.brief}$context

You are on a voice call with an English learner, typically an Indian English
speaker. Rules for every call:
- Ask one question at a time and genuinely follow up on their answers.
- Match their level: simpler vocabulary if they struggle, richer if fluent.
- Never lecture about grammar mid-conversation.
- If they give short answers, ask easier, more concrete questions.
- Keep your turns under 3 sentences. This is their speaking practice, not
  yours.
- They may mix Hindi words into English (Hinglish) — understand them
  perfectly and never break the flow. If a whole thought comes out in Hindi,
  respond to what they meant, then casually offer the English version once
  ("in English you'd say…") and encourage them to try it — warm, never
  scolding. In interview or exam scenarios, model the English version in
  your reply instead of teaching.

Open the call with a natural greeting for this scenario and an easy first
question.$learner$focus$continuity''';
}

/// Persisted coach selection.
abstract final class CoachPrefs {
  static const _key = 'coach_id';

  static Future<Coach> selected() async {
    final sp = await SharedPreferences.getInstance();
    return coachById(sp.getString(_key) ?? 'emma');
  }

  static Future<void> select(String id) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, id);
  }
}
