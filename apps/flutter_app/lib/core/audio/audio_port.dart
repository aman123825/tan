/// Audio output abstraction (pure Dart).
///
/// The renderers depend only on [AudioPort] so they can be unit/widget-tested
/// with [SilentAudioPort]. The real implementation ([JustAudioPort] in
/// `data/just_audio_player.dart`) wraps `just_audio` and is kept out of the
/// logic layer.
library;

import 'dart:typed_data';

abstract class AudioPort {
  /// Plays a complete WAV byte buffer (see `core/audio/pcm_synth.dart`).
  Future<void> playWav(Uint8List wavBytes);

  /// Stops any current playback.
  Future<void> stop();
}

/// No-op port for tests/headless use. Records how many buffers were played and
/// the last one, so tests can assert playback was requested without any audio
/// device.
class SilentAudioPort implements AudioPort {
  int playCount = 0;
  Uint8List? lastPlayed;

  @override
  Future<void> playWav(Uint8List wavBytes) async {
    playCount++;
    lastPlayed = wavBytes;
  }

  @override
  Future<void> stop() async {}
}
