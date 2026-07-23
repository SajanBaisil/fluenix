import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/api.dart';
import '../../theme/app_theme.dart';
import '../report/report_screen.dart';
import '../../voice/audio_io.dart';
import '../../voice/audio_route.dart';
import '../../voice/gemini_live_session.dart';
import '../../voice/voice_session.dart';

enum CallState { connecting, listening, speaking, ended, error }

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

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
  String _errorMessage = '';
  bool _muted = false;
  int _seconds = 0;
  Timer? _ticker;

  // Backend session + transcript accumulation for the post-call report.
  SessionGrant? _grant;
  final List<TranscriptTurn> _turns = [];
  String _fragRole = '';
  final StringBuffer _frag = StringBuffer();

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
    try {
      final grant = await Api.startSession();
      _grant = grant;
      model = grant.model;
      token = grant.token;
      isEphemeral = grant.tokenKind == 'ephemeral';
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
    );
    _session = session;
    _syncDuplex();
    _sub = session.events.listen(_onEvent);
    await session.start();
  }

  void _addFragment(String role, String text) {
    if (role != _fragRole && _frag.isNotEmpty) {
      _turns.add(TranscriptTurn(role: _fragRole, text: _frag.toString().trim()));
      _frag.clear();
    }
    _fragRole = role;
    _frag.write(text);
  }

  void _flushFragment() {
    if (_frag.isNotEmpty) {
      _turns.add(TranscriptTurn(role: _fragRole, text: _frag.toString().trim()));
      _frag.clear();
    }
  }

  Future<void> _reportCallEnd() async {
    final grant = _grant;
    if (grant == null) return;
    _flushFragment();
    try {
      await Api.endCall(
        callId: grant.callId,
        durationS: _seconds,
        turns: _turns,
      );
    } catch (e) {
      debugPrint('call: end report failed: $e');
    }
  }

  Future<void> _toggleSpeaker() =>
      _route.setSpeakerphone(!_route.speakerOn);

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
      case Interrupted():
        unawaited(_player.flush());
        _turnBuffer = '';
        setState(() => _state = CallState.listening);
      case TurnComplete():
        _turnBuffer = '';
        setState(() => _state = CallState.listening);
      case SessionError(:final message):
        setState(() {
          _state = CallState.error;
          _errorMessage = message;
        });
      case SessionClosed():
        setState(() => _state = CallState.ended);
    }
  }

  Future<void> _endCall() async {
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

  String get _statusLabel => switch (_state) {
        CallState.connecting => 'CONNECTING',
        CallState.listening => 'LISTENING',
        CallState.speaking => 'SPEAKING',
        CallState.ended => 'CALL ENDED',
        CallState.error => 'ERROR',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.1,
            colors: [Color(0x296366F1), Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              Text(
                _timer,
                style: const TextStyle(
                  color: Tokens.muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 26),
              _CoachHalo(active: _state == CallState.speaking),
              const SizedBox(height: 26),
              const Text(
                'Emma',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Waveform(active: _state == CallState.speaking),
                  const SizedBox(width: 8),
                  Text(
                    _statusLabel,
                    style: const TextStyle(
                      color: Tokens.indigoSoft,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  _state == CallState.error ? _errorMessage : _caption,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        _state == CallState.error ? Tokens.rose : Tokens.muted,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CtlButton(
                    icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    active: _muted,
                    onTap: () {
                      setState(() => _muted = !_muted);
                      _session?.setMuted(_muted);
                    },
                  ),
                  const SizedBox(width: 16),
                  // Shows where the audio actually is: earpiece, speaker,
                  // Bluetooth, or wired — updates live as devices connect.
                  ValueListenableBuilder<CallAudioRoute>(
                    valueListenable: _route.route,
                    builder: (context, r, _) => _CtlButton(
                      icon: switch (r) {
                        CallAudioRoute.speaker => Icons.volume_up_rounded,
                        CallAudioRoute.bluetooth =>
                          Icons.bluetooth_audio_rounded,
                        CallAudioRoute.wired => Icons.headset_rounded,
                        CallAudioRoute.earpiece =>
                          Icons.phone_in_talk_rounded,
                      },
                      // Highlighted whenever audio is anywhere but the
                      // default earpiece.
                      active: r != CallAudioRoute.earpiece,
                      onTap: _toggleSpeaker,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(34, 0, 34, 34),
                child: GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      gradient: Tokens.coralGradient,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Tokens.coralDeep.withValues(alpha: 0.3),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Text(
                      'End call',
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Breathing halo around the coach avatar (mockup 02).
class _CoachHalo extends StatefulWidget {
  const _CoachHalo({required this.active});
  final bool active;

  @override
  State<_CoachHalo> createState() => _CoachHaloState();
}

class _CoachHaloState extends State<_CoachHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 210,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + 0.06 * t,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Tokens.indigoSoft.withValues(
                        alpha: 0.35 - 0.2 * t,
                      ),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          width: 140,
          height: 140,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Tokens.indigo, Tokens.violet],
            ),
            boxShadow: [
              BoxShadow(
                color: Tokens.indigo.withValues(
                  alpha: widget.active ? 0.55 : 0.35,
                ),
                blurRadius: 70,
              ),
            ],
          ),
          child: const Text(
            'E',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Five animated bars, active while the coach is speaking.
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

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(5, (i) {
              final phase = (_c.value + i * 0.15) % 1.0;
              final h = widget.active
                  ? 5 + 13 * (0.5 - (phase - 0.5).abs()) * 2
                  : 5.0;
              return Container(
                width: 3.5,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Tokens.indigoSoft,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _CtlButton extends StatelessWidget {
  const _CtlButton({required this.icon, required this.onTap, this.active = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: active ? Tokens.indigo : Tokens.cardHi,
          shape: BoxShape.circle,
          border: Border.all(color: Tokens.line),
        ),
        child: Icon(icon, color: Tokens.ink, size: 22),
      ),
    );
  }
}
