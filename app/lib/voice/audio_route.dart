import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Call-style audio routing: start on the earpiece like a real phone call,
/// toggle to loudspeaker on demand, follow wired and Bluetooth headsets.
///
/// iOS: `playAndRecord` + `voiceChat` routes to the receiver/Bluetooth
/// automatically; the speaker toggle uses `overrideOutputAudioPort`.
///
/// Android: the app plays the coach on a VOICE_COMMUNICATION stream (see
/// MainActivity.kt), which follows the *communication device* — so like a real
/// dialer we must pick one: wired > Bluetooth > earpiece, or the speaker when
/// toggled. Re-applied automatically when devices change (buds connecting
/// mid-call).
///
/// Every platform call is wrapped: routing is quality-of-life, and a failure
/// (e.g. a stale binary without the plugin after hot restart) must never take
/// down the call itself.
/// Where the call audio is currently going — drives the route button's icon.
enum CallAudioRoute { earpiece, speaker, bluetooth, wired }

class AudioRoute {
  bool _speakerOn = false;
  bool get speakerOn => _speakerOn;

  /// Live route for the UI. Updated on every (re)apply, including automatic
  /// ones when devices connect/disconnect.
  final route = ValueNotifier<CallAudioRoute>(CallAudioRoute.earpiece);
  StreamSubscription<AudioDevicesChangedEvent>? _devicesSub;
  bool _disposed = false;

  void _setRoute(CallAudioRoute value) {
    if (!_disposed) route.value = value;
  }

  Future<void> _safe(String what, Future<void> Function() action) async {
    try {
      await action();
    } on MissingPluginException {
      debugPrint(
        'route: $what skipped — audio_session native side not registered. '
        'Full stop + flutter run (hot restart cannot add plugins).',
      );
    } on Exception catch (e) {
      debugPrint('route: $what failed: $e');
    }
  }

  Future<void> initForCall() async {
    await _safe('configure', () async {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);
      // Headset plugged / buds connected mid-call → re-pick the route.
      _devicesSub ??=
          session.devicesChangedEventStream.listen((_) => _applyRoute());
    });
    if (Platform.isAndroid) {
      await _safe(
        'communication mode',
        () => AndroidAudioManager()
            .setMode(AndroidAudioHardwareMode.inCommunication),
      );
    }
    await _applyRoute();
  }

  Future<void> setSpeakerphone(bool on) async {
    _speakerOn = on;
    await _applyRoute();
  }

  Future<void> _applyRoute() async {
    if (Platform.isIOS) {
      await _safe('port override', () async {
        final session = AVAudioSession();
        await session.overrideOutputAudioPort(
          _speakerOn
              ? AVAudioSessionPortOverride.speaker
              : AVAudioSessionPortOverride.none,
        );
        if (_speakerOn) {
          _setRoute(CallAudioRoute.speaker);
          return;
        }
        final outputs = (await session.currentRoute).outputs;
        _setRoute(outputs.any(
          (o) =>
              o.portType == AVAudioSessionPort.bluetoothHfp ||
              o.portType == AVAudioSessionPort.bluetoothA2dp ||
              o.portType == AVAudioSessionPort.bluetoothLe,
        )
            ? CallAudioRoute.bluetooth
            : outputs.any(
                (o) =>
                    o.portType == AVAudioSessionPort.headphones ||
                    o.portType == AVAudioSessionPort.usbAudio,
              )
                ? CallAudioRoute.wired
                : CallAudioRoute.earpiece);
      });
      return;
    }
    if (!Platform.isAndroid) return;
    await _safe('pick communication device', () async {
      final manager = AndroidAudioManager();
      List<AndroidAudioDeviceInfo> devices;
      try {
        devices = await manager.getAvailableCommunicationDevices();
      } on PlatformException {
        // Pre-Android-12 fallback.
        await manager.setSpeakerphoneOn(_speakerOn);
        return;
      }

      AndroidAudioDeviceInfo? byType(AndroidAudioDeviceType type) {
        for (final d in devices) {
          if (d.type == type) return d;
        }
        return null;
      }

      // Same priority as the system dialer.
      final target = _speakerOn
          ? byType(AndroidAudioDeviceType.builtInSpeaker)
          : byType(AndroidAudioDeviceType.wiredHeadset) ??
              byType(AndroidAudioDeviceType.wiredHeadphones) ??
              byType(AndroidAudioDeviceType.usbHeadset) ??
              byType(AndroidAudioDeviceType.bluetoothSco) ??
              byType(AndroidAudioDeviceType.builtInEarpiece);

      if (target != null) {
        final ok = await manager.setCommunicationDevice(target);
        debugPrint(
          'route: → ${target.type.name} (${target.productName}) ok=$ok',
        );
        _setRoute(switch (target.type) {
          AndroidAudioDeviceType.builtInSpeaker => CallAudioRoute.speaker,
          AndroidAudioDeviceType.bluetoothSco => CallAudioRoute.bluetooth,
          AndroidAudioDeviceType.wiredHeadset ||
          AndroidAudioDeviceType.wiredHeadphones ||
          AndroidAudioDeviceType.usbHeadset =>
            CallAudioRoute.wired,
          _ => CallAudioRoute.earpiece,
        });
      } else {
        await manager.setSpeakerphoneOn(_speakerOn);
        _setRoute(
          _speakerOn ? CallAudioRoute.speaker : CallAudioRoute.earpiece,
        );
      }
    });
  }

  /// Idempotent — reached from both "End call" and widget dispose.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _devicesSub?.cancel();
    _devicesSub = null;
    route.dispose();
    if (Platform.isAndroid) {
      await _safe('route reset', () async {
        final manager = AndroidAudioManager();
        try {
          await manager.clearCommunicationDevice();
        } on PlatformException {
          await manager.setSpeakerphoneOn(false);
        }
        await manager.setMode(AndroidAudioHardwareMode.normal);
      });
    }
    await _safe('deactivate', () async {
      final session = await AudioSession.instance;
      await session.setActive(false);
    });
  }
}
