import 'dart:typed_data';

/// Provider-agnostic voice session (PLAN.md §2: provider abstraction).
///
/// Implementations: [GeminiLiveSession] today, OpenAI Realtime later.
/// The call screen only ever talks to this interface.
abstract interface class VoiceSession {
  /// Connect, start streaming the mic, and begin the conversation.
  Future<void> start();

  /// End the session and release audio resources.
  Future<void> stop();

  void setMuted(bool muted);

  /// Half-duplex gates the mic while the assistant speaks (no barge-in).
  /// The call screen sets this per audio route: loudspeaker → true,
  /// earpiece/wired/Bluetooth → false.
  void setHalfDuplex(bool halfDuplex);

  Stream<VoiceEvent> get events;
}

sealed class VoiceEvent {
  const VoiceEvent();
}

/// Connection established; the coach is about to speak.
class SessionReady extends VoiceEvent {
  const SessionReady();
}

/// A chunk of the assistant's speech (PCM16 mono, [sampleRate] Hz).
class AssistantAudio extends VoiceEvent {
  const AssistantAudio(this.pcm16, {this.sampleRate = 24000});
  final Uint8List pcm16;
  final int sampleRate;
}

/// Rolling transcript of what the assistant is saying.
class AssistantTranscript extends VoiceEvent {
  const AssistantTranscript(this.text);
  final String text;
}

/// Rolling transcript of what the user said (feeds the post-call report).
class UserTranscript extends VoiceEvent {
  const UserTranscript(this.text);
  final String text;
}

/// User spoke over the assistant — discard any buffered assistant audio.
class Interrupted extends VoiceEvent {
  const Interrupted();
}

/// The assistant finished its turn and is listening.
class TurnComplete extends VoiceEvent {
  const TurnComplete();
}

class SessionError extends VoiceEvent {
  const SessionError(this.message);
  final String message;
}

class SessionClosed extends VoiceEvent {
  const SessionClosed();
}
