import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'audio_io.dart';
import 'voice_session.dart';

/// [VoiceSession] backed by the Gemini Live API (native audio, speech-to-speech)
/// over its BidiGenerateContent WebSocket.
///
/// Protocol: https://ai.google.dev/api/live
///  - client → server: `setup`, then `realtimeInput.audio` chunks
///    (base64 PCM16 @16 kHz mono)
///  - server → client: `setupComplete`, `serverContent` with
///    `modelTurn.parts[].inlineData` (base64 PCM16 @24 kHz),
///    `interrupted`, `turnComplete`, input/output transcriptions.
class GeminiLiveSession implements VoiceSession {
  /// Ephemeral backend tokens use the v1alpha `Constrained` endpoint with an
  /// `Authorization: Token …` header; a raw dev key uses v1beta `?key=`.
  GeminiLiveSession({
    required this.model,
    required this.token,
    required this.isEphemeral,
    required this.systemPrompt,
    required this.voiceName,
    MicStream? mic,
  }) : _mic = mic ?? MicStream();

  static const _keyEndpoint =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';
  static const _tokenEndpoint =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained';

  final String model;
  final String token;
  final bool isEphemeral;
  final String systemPrompt;
  final String voiceName;
  final MicStream _mic;
  final _events = StreamController<VoiceEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _micSub;
  bool _muted = false;
  bool _stopped = false;
  bool _halfDuplex = true; // safe default until the route is known

  /// True while the coach's audio is streaming (plus a short tail while the
  /// playback buffer drains). Used for half-duplex mic gating.
  bool _assistantSpeaking = false;
  Timer? _speakingTail;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  void _emit(VoiceEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<void> start() async {
    final channel = isEphemeral
        ? IOWebSocketChannel.connect(
            Uri.parse(_tokenEndpoint),
            headers: {'Authorization': 'Token $token'},
          )
        : WebSocketChannel.connect(Uri.parse('$_keyEndpoint?key=$token'));
    _channel = channel;

    channel.stream.listen(
      _onServerMessage,
      onError: (Object e) {
        debugPrint('live: ws error: $e');
        _emit(SessionError(e.toString()));
      },
      onDone: () {
        debugPrint(
          'live: ws closed (code=${channel.closeCode} '
          'reason=${channel.closeReason})',
        );
        if (!_stopped) _emit(const SessionClosed());
      },
    );

    channel.sink.add(
      jsonEncode({
        'setup': {
          'model': model,
          'generationConfig': {
            'responseModalities': ['AUDIO'],
            'speechConfig': {
              'voiceConfig': {
                'prebuiltVoiceConfig': {'voiceName': voiceName},
              },
            },
          },
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          // Transcripts of both sides — persisted later for the post-call
          // analysis pipeline (PLAN.md §6).
          'inputAudioTranscription': <String, Object>{},
          'outputAudioTranscription': <String, Object>{},
          // Make voice activity detection less trigger-happy: a learner's
          // thinking pauses shouldn't end their turn, and background noise
          // shouldn't start one.
          'realtimeInputConfig': {
            'automaticActivityDetection': {
              'startOfSpeechSensitivity': 'START_SENSITIVITY_LOW',
              'endOfSpeechSensitivity': 'END_SENSITIVITY_LOW',
              'silenceDurationMs': 900,
            },
          },
        },
      }),
    );
  }

  Future<void> _startMic() async {
    final micStream = await _mic.start();
    if (micStream == null) {
      _emit(const SessionError('Microphone permission denied.'));
      return;
    }
    _micSub = micStream.listen((chunk) {
      final channel = _channel;
      if (_muted || channel == null) return;
      // Half-duplex: never let the speaker's output loop back into the model.
      if (_halfDuplex && _assistantSpeaking) return;
      channel.sink.add(
        jsonEncode({
          'realtimeInput': {
            'audio': {
              'mimeType': 'audio/pcm;rate=16000',
              'data': base64Encode(chunk),
            },
          },
        }),
      );
    });
  }

  void _onServerMessage(dynamic raw) {
    final String text;
    if (raw is String) {
      text = raw;
    } else if (raw is List<int>) {
      text = utf8.decode(raw);
    } else {
      return;
    }

    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      return;
    }

    if (msg.containsKey('setupComplete')) {
      debugPrint('live: setup complete ($model)');
      _emit(const SessionReady());
      // Only open the mic once the session is accepted.
      unawaited(_startMic());
      // Nudge the model to open the conversation.
      _channel?.sink.add(
        jsonEncode({
          'clientContent': {
            'turns': [
              {
                'role': 'user',
                'parts': [
                  {'text': 'Hi!'},
                ],
              },
            ],
            'turnComplete': true,
          },
        }),
      );
      return;
    }

    if (msg.containsKey('goAway')) {
      // Server will close soon (session limit). Distinguishes provider
      // limits from network drops in the logs.
      debugPrint('live: goAway received: ${msg['goAway']}');
      return;
    }

    final serverContent = msg['serverContent'] as Map<String, dynamic>?;
    if (serverContent == null) return;

    if (serverContent['interrupted'] == true) {
      _speakingTail?.cancel();
      _assistantSpeaking = false;
      _emit(const Interrupted());
      return;
    }

    final inTr = serverContent['inputTranscription'] as Map<String, dynamic>?;
    if (inTr?['text'] is String) {
      _emit(UserTranscript(inTr!['text'] as String));
    }
    final outTr = serverContent['outputTranscription'] as Map<String, dynamic>?;
    if (outTr?['text'] is String) {
      _emit(AssistantTranscript(outTr!['text'] as String));
    }

    final modelTurn = serverContent['modelTurn'] as Map<String, dynamic>?;
    final parts = modelTurn?['parts'] as List<dynamic>?;
    if (parts != null) {
      for (final part in parts.whereType<Map<String, dynamic>>()) {
        final inline = part['inlineData'] as Map<String, dynamic>?;
        final data = inline?['data'];
        if (data is String) {
          _assistantSpeaking = true;
          _speakingTail?.cancel();
          _emit(AssistantAudio(base64Decode(data)));
        }
      }
    }

    if (serverContent['turnComplete'] == true) {
      // Generation finishes before playback does — keep the mic gated while
      // the buffered tail of the coach's audio is still coming out of the
      // speaker, then reopen.
      _speakingTail?.cancel();
      _speakingTail = Timer(const Duration(milliseconds: 1500), () {
        _assistantSpeaking = false;
      });
      _emit(const TurnComplete());
    }
  }

  @override
  void setMuted(bool muted) => _muted = muted;

  @override
  void setHalfDuplex(bool halfDuplex) => _halfDuplex = halfDuplex;

  /// Idempotent — the call screen may reach this from both "End call" and
  /// widget dispose.
  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _speakingTail?.cancel();
    await _micSub?.cancel();
    _micSub = null;
    await _mic.dispose();
    await _channel?.sink.close();
    _channel = null;
    if (!_events.isClosed) await _events.close();
  }
}
