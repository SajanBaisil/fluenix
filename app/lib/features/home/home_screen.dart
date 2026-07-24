import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../services/api.dart';
import '../../services/profile.dart';
import '../../services/reminders.dart';
import '../../theme/app_theme.dart';
import '../call/call_screen.dart';
import '../coach/coaches.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Limits? _limits;
  bool _limitsFailed = false;
  bool _offline = false;
  Timer? _retry;
  List<String> _workingOn = const [];
  Coach _coach = coaches[1];
  TimeOfDay? _reminderTime;

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
    unawaited(_loadFocus());
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
        _offline = e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup');
      });
      _retry = Timer(const Duration(seconds: 5), _loadLimits);
    }
  }

  Future<void> _loadFocus() async {
    if (Config.supabaseUrl.isEmpty) return;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await Supabase.instance.client
          .from('reports')
          .select('focus_points, created_at, calls!inner(user_id)')
          .eq('calls.user_id', uid)
          .order('created_at', ascending: false)
          .limit(1);
      if (mounted && rows.isNotEmpty) {
        setState(() {
          _workingOn = ((rows.first['focus_points'] as List?) ?? [])
              .map((e) => e.toString())
              .toList();
        });
      }
    } catch (_) {
      // Chips are progressive enhancement — fail silently.
    }
  }

  void _startCall(Scenario scenario, {String scenarioContext = ''}) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => CallScreen(
              coach: _coach,
              scenario: scenario,
              scenarioContext: scenarioContext,
            ),
          ),
        )
        .then((_) => refresh());
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
      // "Turn off" / dismiss: only clear if one was set.
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
      _toast('${_coach.name} will call you daily at '
          '${picked.format(context)}');
    } else {
      _toast('Notifications are blocked — allow them in Settings');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Interview calls can be tailored: role, company, or a pasted JD.
  Future<void> _startInterview(Scenario scenario) async {
    final sp = await SharedPreferences.getInstance();
    final controller =
        TextEditingController(text: sp.getString('last_jd') ?? '');
    if (!mounted) return;
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            22, 20, 22, 22 + MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Make it your interview',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Role, company, or paste the job description — the '
              'interviewer will use it. Optional.',
              style: TextStyle(fontSize: 12.5, color: Tokens.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 5,
              minLines: 2,
              maxLength: 1500,
              style: const TextStyle(fontSize: 13.5, height: 1.5),
              decoration: InputDecoration(
                counterText: '',
                hintText:
                    'e.g. Senior Flutter Developer at TCS…\nor paste the JD',
                hintStyle:
                    const TextStyle(color: Tokens.faint, fontSize: 13),
                filled: true,
                fillColor: Tokens.phone,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Tokens.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Tokens.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Tokens.indigo, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext, ''),
                    child: const Text('Skip',
                        style: TextStyle(color: Tokens.muted)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () =>
                        Navigator.pop(sheetContext, controller.text),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        gradient: Tokens.ctaGradient,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Start interview',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result == null) return; // dismissed entirely
    if (result.trim().isNotEmpty) await sp.setString('last_jd', result.trim());
    if (mounted) _startCall(scenario, scenarioContext: result.trim());
  }

  @override
  Widget build(BuildContext context) {
    final limits = _limits;
    final usedFraction = limits == null
        ? 0.0
        : (limits.allowanceSeconds - limits.remainingSeconds) /
            limits.allowanceSeconds;
    final subtitle = switch ((limits, _limitsFailed, _hasBackend)) {
      (final Limits l, _, _) =>
        '${(l.remainingSeconds / 60).ceil()} of ${l.allowanceSeconds ~/ 60} '
            'min left today',
      (null, true, _) => _offline
          ? 'No internet connection — check WiFi or mobile data'
          : "Can't reach the server — calls may not start",
      (null, _, false) => 'Dev mode — no metering',
      _ => 'Checking your minutes…',
    };

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ProfileService.current.name.isEmpty
                        ? 'Good morning 👋'
                        : 'Hi, ${ProfileService.current.name} 👋',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Daily call time',
                  onPressed: _pickReminderTime,
                  icon: Icon(
                    _reminderTime == null
                        ? Icons.notifications_none_rounded
                        : Icons.notifications_active_rounded,
                    color: _reminderTime == null
                        ? Tokens.faint
                        : Tokens.indigoSoft,
                    size: 20,
                  ),
                ),
                if (Config.supabaseUrl.isNotEmpty)
                  IconButton(
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    icon: const Icon(Icons.logout_rounded,
                        color: Tokens.faint, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              "Ready for today's call?",
              style: TextStyle(fontSize: 13, color: Tokens.muted),
            ),
            const SizedBox(height: 26),
            Center(
              child: GestureDetector(
                onTap: () => _startCall(scenarios[0]),
                child: SizedBox(
                  width: 196,
                  height: 196,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CustomPaint(
                          painter: _GoalRingPainter(
                            usedFraction.clamp(0.0, 1.0),
                          ),
                        ),
                      ),
                      Container(
                        width: 118,
                        height: 118,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _coach.gradient,
                          boxShadow: [
                            BoxShadow(
                              color: _coach.colors.first
                                  .withValues(alpha: 0.45),
                              blurRadius: 40,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.call_rounded,
                                color: Colors.white, size: 28),
                            const SizedBox(height: 5),
                            Text(
                              'Call ${_coach.name}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: Tokens.muted),
              ),
            ),
            if (_workingOn.isNotEmpty) ...[
              _sectionLabel('WORKING ON · FROM YOUR LAST REPORT'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in _workingOn)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Tokens.indigo.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Tokens.indigo.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        f,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFDDE1FF),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            _sectionLabel('JUMP INTO A SCENARIO'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.9,
              children: [
                for (final s in scenarios)
                  GestureDetector(
                    onTap: () =>
                        s.id == 'interview' ? _startInterview(s) : _startCall(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      decoration: BoxDecoration(
                        color: Tokens.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Tokens.line),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Tokens.cardHi,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(s.icon,
                                size: 17, color: Tokens.indigoSoft),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.title,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
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

class _GoalRingPainter extends CustomPainter {
  _GoalRingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = const Color(0x1F94A3FF);
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: -1.5708,
        endAngle: 4.7124,
        colors: [Tokens.indigo, Tokens.violet],
      ).createShader(rect);
    canvas.drawArc(rect, -1.5708, 6.2832 * progress, false, arc);
  }

  @override
  bool shouldRepaint(_GoalRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
