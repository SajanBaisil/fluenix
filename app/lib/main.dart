import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'features/auth/auth_screen.dart';
import 'features/call/call_screen.dart';
import 'services/api.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Config.supabaseUrl.isNotEmpty) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseAnonKey,
    );
  }
  runApp(const FluenixApp());
}

class FluenixApp extends StatelessWidget {
  const FluenixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluenix',
      debugShowCheckedModeBanner: false,
      theme: buildFluenixTheme(),
      // Without Supabase config the app still runs in pure-dev mode
      // (direct Gemini key, no auth, no metering).
      home: Config.supabaseUrl.isEmpty ? const HomeScreen() : const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        final signedIn = Supabase.instance.client.auth.currentSession != null;
        return signedIn ? const HomeScreen() : const AuthScreen();
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  Limits? _limits;
  bool _limitsFailed = false;
  Timer? _retry;

  bool get _hasBackend =>
      Config.supabaseUrl.isNotEmpty && Config.backendUrl.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLimits();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground — the server may be reachable again.
    if (state == AppLifecycleState.resumed) _loadLimits();
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _limitsFailed = true);
      // Keep trying quietly — adb reverse / the backend often come back.
      _retry = Timer(const Duration(seconds: 5), _loadLimits);
    }
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
      (null, true, _) => "Can't reach the server — calls may not start",
      (null, _, false) => 'Dev mode — no metering',
      _ => 'Checking your minutes…',
    };

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 18),
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
                      onPressed: () =>
                          Supabase.instance.client.auth.signOut(),
                      icon: const Icon(Icons.logout_rounded,
                          color: Tokens.faint, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                "Ready for today's call?",
                style: TextStyle(fontSize: 13, color: Tokens.muted),
              ),
              const Spacer(),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context)
                      .push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CallScreen(),
                        ),
                      )
                      .then((_) => _loadLimits()),
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
                            gradient: Tokens.ctaGradient,
                            boxShadow: [
                              BoxShadow(
                                color: Tokens.indigo.withValues(alpha: 0.45),
                                blurRadius: 40,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.call_rounded,
                                  color: Colors.white, size: 30),
                              SizedBox(height: 6),
                              Text(
                                'Start call',
                                style: TextStyle(
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
              const SizedBox(height: 16),
              Center(
                child: Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: Tokens.muted),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
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
