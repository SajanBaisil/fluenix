import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../services/api.dart';
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

  void _startCall(Scenario scenario) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => CallScreen(coach: _coach, scenario: scenario),
          ),
        )
        .then((_) => refresh());
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
                const Expanded(
                  child: Text(
                    'Good morning 👋',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
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
                    onTap: () => _startCall(s),
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
