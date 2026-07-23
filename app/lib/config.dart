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

  /// Duplex is decided per audio route: earpiece/wired/Bluetooth get full
  /// barge-in (no acoustic echo path), loudspeaker gates the mic while the
  /// coach speaks (half-duplex) unless this flag says otherwise.
  ///
  /// Set true to trust the hardware echo canceller on loudspeaker too —
  /// works on many phones now that playback uses the voice-call path.
  static const speakerFullDuplex = false;
}
