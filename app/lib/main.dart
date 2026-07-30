import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'features/auth/auth_screen.dart';
import 'features/call/call_screen.dart';
import 'features/coach/coach_screen.dart';
import 'features/coach/coaches.dart';
import 'features/community/community_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/practice/practice_screen.dart';
import 'features/progress/progress_screen.dart';
import 'features/splash/splash_screen.dart';
import 'services/profile.dart';
import 'services/reminders.dart';
import 'theme/app_theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Config.supabaseUrl.isNotEmpty) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseAnonKey,
    );
  }
  // Answering the daily "coach is calling" notification goes straight into
  // a call with the selected coach.
  Reminders.onAnswer = () async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    final coach = await CoachPrefs.selected();
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(coach: coach, scenario: scenarios[0]),
      ),
    );
  };
  await Reminders.init();
  runApp(const FluenixApp());
}

class FluenixApp extends StatelessWidget {
  const FluenixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluenix',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildFluenixTheme(),
      // Without Supabase config the app still runs in pure-dev mode
      // (direct Gemini key, no auth, no metering). Boot happens under the
      // animated splash, which fades out when its loader completes.
      home: SplashGate(
        child:
            Config.supabaseUrl.isEmpty ? const HomeShell() : const _AuthGate(),
      ),
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

  void _goToTab(int i) {
    setState(() => _tab = i);
    // Coming back to a tab → refresh its data.
    if (i == 0) _homeKey.currentState?.refresh();
    if (i == 2) _practiceKey.currentState?.refresh();
    if (i == 3) _communityKey.currentState?.refresh();
    if (i == 4) _progressKey.currentState?.refresh();
  }

  final _homeKey = GlobalKey<HomeScreenState>();
  final _practiceKey = GlobalKey<PracticeScreenState>();
  final _communityKey = GlobalKey<CommunityScreenState>();
  final _progressKey = GlobalKey<ProgressScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(key: _homeKey, onGoToTab: _goToTab),
          const CoachScreen(),
          PracticeScreen(key: _practiceKey),
          CommunityScreen(key: _communityKey),
          ProgressScreen(key: _progressKey),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: const Color(0xEBF6F1E8),
          indicatorColor: Colors.transparent,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? Tokens.ink
                  : Tokens.ink35,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 20,
              color: states.contains(WidgetState.selected)
                  ? Tokens.ink
                  : Tokens.ink35,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          height: 68,
          onDestinationSelected: _goToTab,
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
              icon: Icon(Icons.forum_rounded),
              label: 'Community',
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
