import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../services/api.dart';
import '../../services/profile.dart';
import '../../services/reminders.dart';
import '../../theme/app_theme.dart';
import '../call/call_setup_screen.dart';
import '../coach/coaches.dart';
import '../report/report_screen.dart';

/// Home (design/README.md §01): resume practice in one tap.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onGoToTab});

  /// Lets hero shortcuts jump to another shell tab (Coaches, Progress).
  final void Function(int index)? onGoToTab;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Limits? _limits;
  bool _limitsFailed = false;
  bool _offline = false;
  Timer? _retry;
  Map<String, dynamic>? _lastReport;
  Coach _coach = coaches[1];
  TimeOfDay? _reminderTime;
  WeekSummary? _week;

  bool get _hasBackend =>
      Config.supabaseUrl.isNotEmpty && Config.backendUrl.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// Public so the shell can refresh after tab switches / calls.
  Future<void> refresh() async {
    _coach = await CoachPrefs.selected();
    await ProfileService.load();
    _reminderTime = await Reminders.scheduledTime();
    if (mounted) setState(() {});
    unawaited(_loadLimits());
    unawaited(_loadLastReport());
    unawaited(_loadWeek());
  }

  Future<void> _loadWeek() async {
    if (!_hasBackend) return;
    try {
      final week = await Api.week();
      if (mounted) setState(() => _week = week);
    } catch (_) {
      // The card is progressive enhancement — fail silently.
    }
  }

  Future<void> _loadLimits() async {
    if (!_hasBackend) return;
    _retry?.cancel();
    try {
      final limits = await Api.limits();
      if (mounted) {
        setState(() {
          _limits = limits;
          _limitsFailed = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _limitsFailed = true;
        // DNS/socket failures mean the phone has no internet at all —
        // that's a different message than "our server is down".
        _offline =
            e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup');
      });
      _retry = Timer(const Duration(seconds: 5), _loadLimits);
    }
  }

  Future<void> _loadLastReport() async {
    if (Config.supabaseUrl.isEmpty) return;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await Supabase.instance.client
          .from('reports')
          .select(
            'call_id, overall, scores, grammar_issues, focus_points, '
            'created_at, calls!inner(user_id)',
          )
          .eq('calls.user_id', uid)
          .order('created_at', ascending: false)
          .limit(1);
      if (mounted && rows.isNotEmpty) {
        setState(() => _lastReport = rows.first);
      }
    } catch (_) {
      // Progressive enhancement — fail silently.
    }
  }

  void _openSetup(Scenario scenario) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => CallSetupScreen(coach: _coach, scenario: scenario),
          ),
        )
        .then((_) {
          // A finished call changes the week's numbers — bypass the cache.
          Api.invalidateWeek();
          refresh();
        });
  }

  /// Pick (or clear) the daily "coach calls you" time.
  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? const TimeOfDay(hour: 19, minute: 0),
      helpText: 'When should ${_coach.name} call you?',
      cancelText: _reminderTime == null ? 'Cancel' : 'Turn off',
    );
    if (!mounted) return;
    if (picked == null) {
      if (_reminderTime != null) {
        await Reminders.cancel();
        setState(() => _reminderTime = null);
        _toast('Daily call turned off');
      }
      return;
    }
    final ok = await Reminders.schedule(picked, _coach.name);
    if (!mounted) return;
    if (ok) {
      setState(() => _reminderTime = picked);
      _toast(
        '${_coach.name} will call you daily at '
        '${picked.format(context)}',
      );
    } else {
      _toast('Notifications are blocked — allow them in Settings');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _profileSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                _reminderTime == null
                    ? Icons.notifications_none_rounded
                    : Icons.notifications_active_rounded,
                color: Tokens.clay,
              ),
              title: Text(
                _reminderTime == null
                    ? 'Set a daily call time'
                    : 'Daily call: ${_reminderTime!.format(context)}',
              ),
              onTap: () {
                Navigator.pop(sheet);
                _pickReminderTime();
              },
            ),
            if (Config.supabaseUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Tokens.ink50),
                title: const Text('Sign out'),
                onTap: () {
                  Navigator.pop(sheet);
                  Supabase.instance.client.auth.signOut();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Scenario get _suggestedScenario => switch (ProfileService.current.goal) {
    'interview' => scenarioById('interview'),
    'ielts' => scenarioById('ielts'),
    _ => scenarios[0],
  };

  String get _cefr => switch (ProfileService.current.level) {
    'beginner' => 'A2',
    'advanced' => 'C1',
    _ => 'B2',
  };

  String get _eyebrow {
    final now = DateTime.now();
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    final part = switch (now.hour) {
      < 12 => 'MORNING',
      < 17 => 'AFTERNOON',
      _ => 'EVENING',
    };
    return '${days[now.weekday - 1]} · $part';
  }

  @override
  Widget build(BuildContext context) {
    final name = ProfileService.current.name;
    final limits = _limits;
    final scenario = _suggestedScenario;
    final focus = ((_lastReport?['focus_points'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();

    final heroMeta = [
      if (limits != null)
        '${(limits.remainingSeconds / 60).ceil()} min left today'
      else
        '≈10 min',
      if (focus.isNotEmpty) focus.first else scenario.title,
      _cefr,
    ].join(' · ');

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            // ── Header ──────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_eyebrow, style: Type.mono(10, color: Tokens.ink50)),
                      const SizedBox(height: 6),
                      Text(
                        name.isEmpty ? 'Hello' : 'Hello, $name',
                        style: Type.display(30),
                      ),
                    ],
                  ),
                ),
                if (_reminderTime != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Tokens.clayTint,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0x2EC9502B)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Tokens.clay,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _reminderTime!.format(context),
                            style: Type.mono(
                              10,
                              color: Tokens.clay,
                              weight: FontWeight.w700,
                              ls: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: _profileSheet,
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Tokens.ink,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      name.isEmpty ? 'F' : name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Tokens.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // ── Next-up hero (ink card, clay glow top-right) ─
            Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(26)),
                // The prototype's blurred clay orb, expressed as the card's
                // own off-center radial gradient (fades back to ink).
                gradient: RadialGradient(
                  center: Alignment(1.15, -1.35),
                  radius: 1.5,
                  colors: [Color(0xFF5C2A1A), Tokens.ink],
                  stops: [0, 0.55],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEXT UP',
                    style: Type.mono(9.5, color: Tokens.cream45, ls: 1.6),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 230),
                    child: Text(
                      '${scenario.title} with ${_coach.name}',
                      style: Type.display(26, color: Tokens.cream),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    heroMeta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Tokens.cream45, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _openSetup(scenario),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              color: Tokens.clay,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Start call',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => widget.onGoToTab?.call(1),
                        child: Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Tokens.cream16),
                          ),
                          child: Text(
                            'All',
                            style: TextStyle(
                              color: Tokens.cream,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_limitsFailed) ...[
              const SizedBox(height: 10),
              Text(
                _offline
                    ? 'No internet connection — check WiFi or mobile data'
                    : "Can't reach the server — calls may not start",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Tokens.clay, fontSize: 12),
              ),
            ],
            // ── This week ───────────────────────────────────
            _sectionRow(
              'This week',
              link: 'DETAILS',
              onLink: () => widget.onGoToTab?.call(4),
            ),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Tokens.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Tokens.hairline),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${_week?.minutes ?? 0}',
                                style: Type.display(34),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '/ ${ProfileService.current.dailyTargetMin * 7} min',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Tokens.ink50,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: SizedBox(
                              height: 7,
                              child: LinearProgressIndicator(
                                value:
                                    ((_week?.minutes ?? 0) /
                                            (ProfileService
                                                    .current
                                                    .dailyTargetMin *
                                                7))
                                        .clamp(0.0, 1.0),
                                backgroundColor: Tokens.track,
                                color: Tokens.clay,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (_week?.line.isNotEmpty ?? false)
                                ? _week!.line
                                : 'Minutes spoken across '
                                      '${_week?.activeDays ?? 0} active days',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Tokens.ink50,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: Tokens.hairline,
                    ),
                    SizedBox(
                      width: 78,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _cefr,
                            style: Type.display(30, color: Tokens.teal),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'CEFR LEVEL',
                            style: Type.mono(8.5, color: Tokens.ink35, ls: 1.2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Pick a goal (2×2) ───────────────────────────
            _sectionRow('Pick a goal'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 11,
              crossAxisSpacing: 11,
              childAspectRatio: 1.62,
              children: [
                _goalCard(
                  '5m',
                  Tokens.goldTint,
                  Tokens.goldText,
                  scenarios[0],
                  'Small talk without freezing',
                ),
                _goalCard(
                  'HR',
                  Tokens.clayTint,
                  Tokens.clay,
                  scenarioById('interview'),
                  'HR + tech rounds, your JD',
                ),
                _goalCard(
                  '7+',
                  Tokens.tealTint,
                  Tokens.teal,
                  scenarioById('ielts'),
                  'Examiner-style parts 1–3',
                ),
                _goalCard(
                  'VS',
                  Tokens.inkSoft,
                  Tokens.ink,
                  scenarioById('debate'),
                  'Defend your opinion, live',
                ),
              ],
            ),
            // ── Last report ─────────────────────────────────
            if (_lastReport != null) ...[
              const SizedBox(height: 22),
              _lastReportRow(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _lastReportRow() {
    final r = _lastReport!;
    final overall = (r['overall'] as num?)?.toInt() ?? 0;
    final fixes = ((r['grammar_issues'] as List?) ?? []).length;
    final headline = ((r['scores'] as Map?)?['headline'] as String?) ?? '';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportScreen(callId: r['call_id'] as String),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tokens.inkSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Text('$overall', style: Type.display(26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your last report is ready',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    headline.isNotEmpty
                        ? headline
                        : '$fixes grammar fixes inside',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Tokens.ink50),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'OPEN',
              style: Type.mono(10, color: Tokens.clay, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goalCard(
    String code,
    Color tint,
    Color color,
    Scenario s,
    String caption,
  ) {
    return GestureDetector(
      onTap: () => _openSetup(s),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Tokens.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Tokens.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                code,
                style: Type.mono(
                  12,
                  color: color,
                  weight: FontWeight.w700,
                  ls: 0,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Tokens.ink50),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionRow(String title, {String? link, VoidCallback? onLink}) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (link != null)
            GestureDetector(
              onTap: onLink,
              child: Text(
                link,
                style: Type.mono(
                  10,
                  color: Tokens.clay,
                  weight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
