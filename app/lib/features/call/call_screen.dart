import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/api.dart';
import '../../theme/app_theme.dart';
import '../coach/coaches.dart';
import '../report/report_screen.dart';
import '../../voice/audio_io.dart';
import '../../voice/audio_route.dart';
import '../../voice/gemini_live_session.dart';
import '../../voice/voice_session.dart';

enum CallState { connecting, listening, speaking, ended, error }

/// Active call (design/README.md §04): full-bleed ink, clay glow, waveform,
/// caption bubbles. All session logic (metering, transcript, barge-in,
/// routing) predates the redesign and is unchanged.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.coach,
    required this.scenario,
    this.scenarioContext = '',
    this.levelOverride = '',
    this.targetMinutes,
    this.initialCc = true,
  });

  final Coach coach;
  final Scenario scenario;

  /// Extra session context, e.g. a pasted job description for interviews.
  final String scenarioContext;

  /// Call-setup overrides (design §03): CEFR level and planned length.
  final String levelOverride;
  final int? targetMinutes;
  final bool initialCc;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  VoiceSession? _session;
  final PcmSink _player = createPcmSink();
  final _route = AudioRoute();
  StreamSubscription<VoiceEvent>? _sub;

  CallState _state = CallState.connecting;
  String _caption = '';
  String _turnBuffer = '';
  String _userCaption = '';
  String _userBuffer = '';
  String _errorMessage = '';
  bool _muted = false;
  late bool _ccOn = widget.initialCc;
  int _seconds = 0;
  Timer? _ticker;

  // Backend session + transcript accumulation for the post-call report.
  SessionGrant? _grant;
  final List<TranscriptTurn> _turns = [];
  String _fragRole = '';
  final StringBuffer _frag = StringBuffer();
  // Fragment arrival times approximate when each turn was actually spoken —
  // the backend turns them into talk-time and pace metrics.
  final Stopwatch _clock = Stopwatch()..start();
  int _fragStartMs = 0;
  int _fragEndMs = 0;

  @override
  void initState() {
    super.initState();
    _route.route.addListener(_syncDuplex);
    _start();
  }

  /// Natural conversation (barge-in) wherever there's no acoustic echo path;
  /// mic gating only on the loudspeaker.
  void _syncDuplex() {
    final half = _route.route.value == CallAudioRoute.speaker &&
        !Config.speakerFullDuplex;
    _session?.setHalfDuplex(half);
  }

  Future<void> _start() async {
    await _player.init();
    // After the player so the output stream exists before the session
    // switches the device into communication mode.
    await _route.initForCall();

    String model;
    String token;
    bool isEphemeral;
    var focusPoints = const <String>[];
    try {
      final grant = await Api.startSession(
        scenario: widget.scenario.id,
        persona: widget.coach.id,
      );
      _grant = grant;
      model = grant.model;
      token = grant.token;
      isEphemeral = grant.tokenKind == 'ephemeral';
      focusPoints = grant.focusPoints;
    } on OutOfMinutesException {
      setState(() {
        _state = CallState.error;
        _errorMessage =
            "You've used today's free minutes. Come back tomorrow!";
      });
      return;
    } catch (e) {
      // Backend unreachable — dev fallback to the raw key if configured.
      if (Config.geminiApiKey.isEmpty) {
        setState(() {
          _state = CallState.error;
          _errorMessage = 'Could not reach the server. Try again in a moment.';
        });
        return;
      }
      model = 'models/gemini-3.1-flash-live-preview';
      token = Config.geminiApiKey;
      isEphemeral = false;
    }

    final session = GeminiLiveSession(
      model: model,
      token: token,
      isEphemeral: isEphemeral,
      systemPrompt: buildSystemPrompt(
        widget.coach,
        widget.scenario,
        focusPoints,
        memory: _grant?.memory ?? '',
        lastCallDaysAgo: _grant?.lastCallDaysAgo,
        scenarioContext: widget.scenarioContext,
        levelOverride: widget.levelOverride,
        targetMinutes: widget.targetMinutes,
      ),
      voiceName: widget.coach.voice,
    );
    _session = session;
    _syncDuplex();
    _sub = session.events.listen(_onEvent);
    await session.start();
  }

  void _addFragment(String role, String text) {
    final now = _clock.elapsedMilliseconds;
    if (role != _fragRole && _frag.isNotEmpty) _flushFragment();
    if (_frag.isEmpty) _fragStartMs = now;
    _fragRole = role;
    _frag.write(text);
    _fragEndMs = now;
  }

  void _flushFragment() {
    if (_frag.isNotEmpty) {
      _turns.add(TranscriptTurn(
        role: _fragRole,
        text: _frag.toString().trim(),
        tStartMs: _fragStartMs,
        tEndMs: _fragEndMs,
      ));
      _frag.clear();
    }
  }

  Future<void> _reportCallEnd() async {
    final grant = _grant;
    if (grant == null) return;
    _flushFragment();
    // The transcript is the product — retry hard before giving up, the
    // network may be mid-blip (often the reason the call ended at all).
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        await Api.endCall(
          callId: grant.callId,
          durationS: _seconds,
          turns: _turns,
        );
        return;
      } catch (e) {
        debugPrint('call: end report attempt $attempt failed: $e');
        if (attempt < 4) await Future.delayed(Duration(seconds: 3 * attempt));
      }
    }
  }

  Future<void> _toggleSpeaker() => _route.setSpeakerphone(!_route.speakerOn);

  void _onEvent(VoiceEvent event) {
    if (!mounted) return;
    switch (event) {
      case SessionReady():
        _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _seconds++);
        });
        setState(() => _state = CallState.listening);
      case AssistantAudio(:final pcm16):
        _player.feed(pcm16);
        if (_state != CallState.speaking) {
          setState(() => _state = CallState.speaking);
        }
      case AssistantTranscript(:final text):
        _addFragment('assistant', text);
        _turnBuffer += text;
        setState(() => _caption = _turnBuffer);
      case UserTranscript(:final text):
        _addFragment('user', text);
        // Live caption of the learner's own recognized words.
        _userBuffer += text;
        setState(() => _userCaption = _userBuffer);
      case Interrupted():
        unawaited(_player.flush());
        _turnBuffer = '';
        _userBuffer = '';
        setState(() {
          _state = CallState.listening;
          _userCaption = '';
        });
      case TurnComplete():
        _turnBuffer = '';
        _userBuffer = '';
        setState(() {
          _state = CallState.listening;
          _userCaption = '';
        });
      case SessionError(:final message):
        // Mid-call failure with real material → wrap up like a hangup so
        // the transcript isn't lost. Failure at connect → show the error.
        if (_seconds > 5 && _turns.isNotEmpty) {
          unawaited(_endCall());
        } else {
          setState(() {
            _state = CallState.error;
            _errorMessage = message;
          });
        }
      case SessionClosed():
        // Remote end (network drop / provider session limit): treat exactly
        // like the user hanging up — upload transcript, go to the report.
        unawaited(_endCall());
    }
  }

  bool _ending = false;

  /// Reached from the End button, remote close, and mid-call errors —
  /// must run exactly once.
  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;
    _ticker?.cancel();
    await _sub?.cancel();
    await _session?.stop();
    await _player.dispose();
    await _route.dispose();
    final grant = _grant;
    _flushFragment();
    final learnerWords = _turns
        .where((t) => t.role == 'user')
        .fold(0, (n, t) => n + t.text.split(' ').length);
    // Ship duration + transcript; the backend starts analyzing immediately.
    unawaited(_reportCallEnd());
    if (!mounted) return;
    if (grant != null && learnerWords >= 15) {
      // Enough material for a report — go wait for it.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ReportScreen(callId: grant.callId),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    _session?.stop();
    _player.dispose();
    _route.dispose();
    super.dispose();
  }

  String get _timer {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.coach;
    return Scaffold(
      backgroundColor: Tokens.ink,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Tokens.cream12,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(c.name[0],
                        style: Type.display(20, color: Tokens.cream)),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            color: Tokens.cream,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.scenario.title} · live',
                          style: const TextStyle(
                              color: Tokens.cream45, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Tokens.cream08,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        const _BlinkDot(color: Tokens.clayHover),
                        const SizedBox(width: 6),
                        Text(_timer,
                            style: Type.mono(12,
                                color: Tokens.cream, ls: 0.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // ── Voice visual: clay glow + waveform ──────────
            SizedBox(
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 300,
                    height: 150,
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0x57C9502B), Colors.transparent],
                        stops: [0, 0.66],
                      ),
                    ),
                  ),
                  _Waveform(active: _state == CallState.speaking),
                ],
              ),
            ),
            const SizedBox(height: 22),
            // ── Status pill ─────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Tokens.cream07,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Tokens.cream10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: Tokens.mint, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    switch (_state) {
                      CallState.connecting => 'CONNECTING…',
                      CallState.speaking =>
                        '${c.name.toUpperCase()} IS SPEAKING',
                      CallState.listening => 'YOUR TURN — KEEP GOING',
                      CallState.ended => 'CALL ENDED',
                      CallState.error => 'SOMETHING WENT WRONG',
                    },
                    style: Type.mono(10, color: Tokens.cream45, ls: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // ── Captions / error ────────────────────────────
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 230),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _state == CallState.error
                    ? Text(
                        _errorMessage,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF2B8A5),
                          fontSize: 13.5,
                          height: 1.6,
                        ),
                      )
                    : !_ccOn
                        ? const SizedBox.shrink()
                        : SingleChildScrollView(
                            reverse: true,
                            child: Column(
                              children: [
                                if (_caption.isNotEmpty)
                                  _bubble(_caption, coach: true, name: c.name),
                                if (_userCaption.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _bubble(_userCaption,
                                      coach: false, name: 'You'),
                                ],
                              ],
                            ),
                          ),
              ),
            ),
            const Spacer(),
            // ── Controls ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
              child: Row(
                children: [
                  _ctl(
                    icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    filled: _muted,
                    onTap: () {
                      setState(() => _muted = !_muted);
                      _session?.setMuted(_muted);
                    },
                  ),
                  const SizedBox(width: 10),
                  ValueListenableBuilder<CallAudioRoute>(
                    valueListenable: _route.route,
                    builder: (context, r, _) => _ctl(
                      icon: switch (r) {
                        CallAudioRoute.speaker => Icons.volume_up_rounded,
                        CallAudioRoute.bluetooth =>
                          Icons.bluetooth_audio_rounded,
                        CallAudioRoute.wired => Icons.headset_rounded,
                        CallAudioRoute.earpiece => Icons.phone_in_talk_rounded,
                      },
                      active: r != CallAudioRoute.earpiece,
                      onTap: _toggleSpeaker,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ctl(
                    icon: Icons.closed_caption_rounded,
                    active: _ccOn,
                    onTap: () => setState(() => _ccOn = !_ccOn),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _endCall,
                      child: Container(
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Tokens.clay,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'End call',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(String text, {required bool coach, required String name}) {
    return Align(
      alignment: coach ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.86),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 10),
        decoration: BoxDecoration(
          color: coach ? Tokens.cream08 : const Color(0x29C9502B),
          border: Border.all(
              color: coach ? Tokens.cream12 : const Color(0x4DC9502B)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(coach ? 6 : 18),
            bottomRight: Radius.circular(coach ? 18 : 6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.toUpperCase(),
              style: Type.mono(
                9,
                color: coach ? Tokens.cream45 : const Color(0xD9F0C98C),
                ls: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: const TextStyle(
                color: Tokens.cream,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctl({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: filled
              ? Tokens.cream
              : active
                  ? Tokens.cream16
                  : Tokens.cream07,
          shape: BoxShape.circle,
          border: Border.all(color: Tokens.cream12),
        ),
        child: Icon(icon,
            color: filled ? Tokens.ink : Tokens.cream, size: 22),
      ),
    );
  }
}

/// 6px dot blinking at 1.4s — the "live" marker in the timer pill.
class _BlinkDot extends StatefulWidget {
  const _BlinkDot({required this.color});
  final Color color;

  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: 6,
        height: 6,
        decoration:
            BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// 18 clay bars (design §04 waveform variant): staggered scaleY animation
/// while the coach speaks, near-flat shimmer otherwise.
class _Waveform extends StatefulWidget {
  const _Waveform({required this.active});
  final bool active;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  static const _colors = [
    Color(0xFFC9502B),
    Color(0xFFD9633A),
    Color(0xFFE8A06F),
    Color(0xFFF0C9A8),
  ];

  // Height profile roughly matching the prototype's 34–132px silhouette.
  static const _profile = [
    .30, .45, .62, .80, .95, .78, .60, .88, 1.0, .92,
    .70, .84, .58, .74, .90, .64, .46, .32,
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _profile.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: _bar(i),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(int i) {
    final max = 34 + 98 * _profile[i];
    final phase = (_c.value + i * 0.08) % 1.0;
    // scaleY .18 → 1 → .18, eased.
    final t = math.sin(phase * math.pi);
    final scale = widget.active ? 0.18 + 0.82 * t : 0.14 + 0.06 * t;
    return Container(
      width: 5,
      height: max * scale,
      decoration: BoxDecoration(
        color: _colors[i % _colors.length],
        borderRadius: BorderRadius.circular(9),
      ),
    );
  }
}
