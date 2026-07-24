import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'features/auth/auth_screen.dart';
import 'features/coach/coach_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/practice/practice_screen.dart';
import 'features/progress/progress_screen.dart';
import 'services/profile.dart';
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
      home: Config.supabaseUrl.isEmpty ? const HomeShell() : const _AuthGate(),
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
        return signedIn ? const _ProfileGate() : const AuthScreen();
      },
    );
  }
}

/// After sign-in: first-run users get onboarding, everyone else the app.
class _ProfileGate extends StatefulWidget {
  const _ProfileGate();

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  Profile? _profile;

  @override
  void initState() {
    super.initState();
    ProfileService.load().then((p) {
      if (mounted) setState(() => _profile = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (profile == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Tokens.indigoSoft),
        ),
      );
    }
    if (!profile.onboarded) {
      return OnboardingScreen(
        onDone: () => setState(() => _profile = ProfileService.current),
      );
    }
    return const HomeShell();
  }
}

/// Bottom-nav shell: Home / Coaches / Progress (mockup navbar).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _homeKey = GlobalKey<HomeScreenState>();
  final _practiceKey = GlobalKey<PracticeScreenState>();
  final _progressKey = GlobalKey<ProgressScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(key: _homeKey),
          const CoachScreen(),
          PracticeScreen(key: _practiceKey),
          ProgressScreen(key: _progressKey),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: const Color(0xF20B0E1A),
          indicatorColor: Tokens.indigo.withValues(alpha: 0.22),
          labelTextStyle: WidgetStatePropertyAll(
            const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Tokens.muted,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? Tokens.indigoSoft
                  : Tokens.faint,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          height: 64,
          onDestinationSelected: (i) {
            setState(() => _tab = i);
            // Coming back to a tab → refresh its data.
            if (i == 0) _homeKey.currentState?.refresh();
            if (i == 2) _practiceKey.currentState?.refresh();
            if (i == 3) _progressKey.currentState?.refresh();
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_rounded),
              label: 'Coaches',
            ),
            NavigationDestination(
              icon: Icon(Icons.fitness_center_rounded),
              label: 'Practice',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_rounded),
              label: 'Progress',
            ),
          ],
        ),
      ),
    );
  }
}
