import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

/// Microphone capture: 16 kHz PCM16 mono — what Gemini Live expects as input.
class MicStream {
  final _recorder = AudioRecorder();
  bool _started = false;
  bool _disposed = false;

  /// Returns the PCM stream, or null if mic permission was denied.
  Future<Stream<Uint8List>?> start() async {
    if (_disposed) return null;
    if (!await _recorder.hasPermission()) return null;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // Echo cancellation is essential: without it the AI hears itself
        // through the speaker and interrupts constantly.
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceCommunication,
        ),
      ),
    );
    _started = true;
    return stream;
  }

  /// Safe to call multiple times, and before [start] — the recorder throws a
  /// PlatformException if stopped when never started or already disposed.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      if (_started) await _recorder.stop();
    } on Exception {
      // Already stopped by the platform — nothing to release.
    }
    try {
      await _recorder.dispose();
    } on Exception {
      // Already disposed.
    }
  }
}

/// Playback sink for the assistant's 24 kHz PCM16 stream.
abstract interface class PcmSink {
  Future<void> init();
  void feed(Uint8List pcm16);

  /// Drop everything queued (the user interrupted the assistant).
  Future<void> flush();
  Future<void> dispose();
}

/// Android must play the coach through the voice-call path so earpiece/speaker
/// routing and the hardware echo canceller work; iOS's AVAudioSession handles
/// routing regardless of engine, so SoLoud is fine there.
PcmSink createPcmSink() =>
    Platform.isAndroid ? AndroidVoicePlayer() : SoLoudPcmPlayer();

/// Native AudioTrack tagged USAGE_VOICE_COMMUNICATION — see MainActivity.kt.
class AndroidVoicePlayer implements PcmSink {
  static const _channel = MethodChannel('fluenix/voice_out');
  bool _disposed = false;

  @override
  Future<void> init() =>
      _channel.invokeMethod<void>('init', {'sampleRate': 24000});

  @override
  void feed(Uint8List pcm16) {
    if (_disposed) return;
    _channel.invokeMethod<void>('write', pcm16);
  }

  @override
  Future<void> flush() async {
    if (_disposed) return;
    await _channel.invokeMethod<void>('flush');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _channel.invokeMethod<void>('dispose');
  }
}

/// SoLoud buffer-stream playback (iOS and any other platform).
class SoLoudPcmPlayer implements PcmSink {
  AudioSource? _source;
  SoundHandle? _handle;
  bool _disposed = false;

  @override
  Future<void> init() async {
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init(sampleRate: 24000, channels: Channels.mono);
    }
    _openStream();
  }

  void _openStream() {
    final source = SoLoud.instance.setBufferStream(
      maxBufferSizeDuration: const Duration(minutes: 30),
      bufferingType: BufferingType.released,
      // Wait for 500 ms of audio before (re)starting playback. Lower values
      // stutter on mobile networks: the buffer drains between network bursts
      // and playback pauses mid-sentence.
      bufferingTimeNeeds: 0.5,
      sampleRate: 24000,
      channels: Channels.mono,
      format: BufferType.s16le,
    );
    _source = source;
    _handle = SoLoud.instance.play(source);
  }

  @override
  void feed(Uint8List pcm16) {
    final source = _source;
    if (source == null || _disposed) return;
    SoLoud.instance.addAudioDataStream(source, pcm16);
  }

  @override
  Future<void> flush() async {
    final source = _source;
    final handle = _handle;
    _source = null;
    _handle = null;
    if (handle != null) await SoLoud.instance.stop(handle);
    if (source != null) await SoLoud.instance.disposeSource(source);
    if (!_disposed) _openStream();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final source = _source;
    final handle = _handle;
    _source = null;
    _handle = null;
    if (handle != null) await SoLoud.instance.stop(handle);
    if (source != null) await SoLoud.instance.disposeSource(source);
  }
}
