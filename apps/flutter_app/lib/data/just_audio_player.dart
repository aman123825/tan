// just_audio marks its in-memory streaming source API as experimental; we use
// it deliberately to stream synthesized WAV buffers without touching disk.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import '../core/audio/audio_port.dart';
import '../features/common/playback_controls.dart';

/// [AudioPort] backed by `just_audio`. Plays an in-memory WAV buffer through a
/// [StreamAudioSource] so synthesized stimuli need never touch disk.
class JustAudioPort implements AudioPort {
  JustAudioPort() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> playWav(Uint8List wavBytes) async {
    // Apply the user's manual playback controls (speed + channel) if any.
    // Presentation only — this never changes the master volume or scoring.
    final bytes = transformPlayback(wavBytes, playbackPrefs.value);
    // Stop any current playback first so sounds never overlap; awaiting play()
    // returns when this buffer finishes, so callers can chain plays back-to-back.
    await _player.stop();
    await _player.setAudioSource(_WavBytesSource(bytes));
    await _player.seek(Duration.zero);
    await _player.play();
  }

  @override
  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}

class _WavBytesSource extends StreamAudioSource {
  _WavBytesSource(this._bytes);

  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream<List<int>>.value(_bytes.sublist(s, e)),
      contentType: 'audio/wav',
    );
  }
}
