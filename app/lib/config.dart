/// Build-time configuration for the Week-1 spike.
///
/// Run with:
///   flutter run --dart-define=GEMINI_API_KEY=your_key_here
///
/// SPIKE ONLY: the key ships in the binary. Production replaces this with
/// ephemeral tokens minted by the backend /session endpoint (see PLAN.md §2).
abstract final class Config {
  /// Dev-only fallback: used directly if the backend is unreachable, so the
  /// app still works while iterating on UI. Production builds omit it.
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// FastAPI service. In dev this is 127.0.0.1:8000 through `adb reverse
  /// tcp:8000 tcp:8000` — the phone reaches the Mac over the USB cable.
  static const backendUrl = String.fromEnvironment('BACKEND_URL');

  /// Gemini Live model with native audio (speech-to-speech).
  /// Verified available on this key (2026-07-23):
  ///   models/gemini-3.1-flash-live-preview          ← newest gen (default)
  ///   models/gemini-2.5-flash-native-audio-latest   ← stable fallback if the
  ///     preview goes silent, rejects setup, or gets renamed
  /// Check https://ai.google.dev/gemini-api/docs/live-api for current names.
  static const liveModel = 'models/gemini-3.1-flash-live-preview';

  /// Voice for the coach persona.
  static const voiceName = 'Aoede';

  /// Duplex is decided per audio route: earpiece/wired/Bluetooth get full
  /// barge-in (no acoustic echo path), loudspeaker gates the mic while the
  /// coach speaks (half-duplex) unless this flag says otherwise.
  ///
  /// Set true to trust the hardware echo canceller on loudspeaker too —
  /// works on many phones now that playback uses the voice-call path.
  static const speakerFullDuplex = false;

  /// Emma — the friendly coach from the persona pack (PLAN.md §3).
  static const systemPrompt = '''
You are Emma, a warm and friendly English conversation coach on a phone call
with a learner from India. This is a casual get-to-know-you call.

How you behave on the call:
- Speak naturally, like a friend on the phone: short turns, contractions,
  occasional "oh really?", "no way!", light laughter.
- Ask one question at a time and genuinely follow up on their answers.
- Match their level: keep your vocabulary simple if they struggle, richer if
  they are fluent.
- Never lecture about grammar mid-conversation. If they make a mistake, just
  continue naturally — sometimes you may gently recast their sentence in your
  reply ("Oh, you've been working there for two years? Nice!").
- Keep the conversation going: if they give short answers, ask easier, more
  concrete questions.
- Keep your turns under 3 sentences. This is their speaking practice, not yours.

Open the call by greeting them by name if known, otherwise warmly, and ask an
easy first question about their day.''';
}
