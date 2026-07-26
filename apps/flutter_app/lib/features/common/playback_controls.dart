import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/pcm_synth.dart';

/// Output-channel routing for manual monaural testing.
enum PlaybackChannel { both, left, right }

extension PlaybackChannelInfo on PlaybackChannel {
  String get label => switch (this) {
        PlaybackChannel.both => 'Both',
        PlaybackChannel.left => 'Left only',
        PlaybackChannel.right => 'Right only',
      };

  String get storageKey => name;

  static PlaybackChannel fromStorage(String? v) {
    for (final c in PlaybackChannel.values) {
      if (c.name == v) return c;
    }
    return PlaybackChannel.both;
  }
}

/// The selectable playback speeds (relative playback rate).
const List<double> kPlaybackSpeeds = <double>[0.8, 1.0, 1.2, 1.5];

/// Manual playback preferences: relative [speed] and channel [routing].
///
/// These affect *presentation only* (how a stimulus is played back) — they
/// never change the master volume or the adaptive parameter.
@immutable
class PlaybackPrefs {
  const PlaybackPrefs({
    this.speed = 1.0,
    this.channel = PlaybackChannel.both,
  });

  final double speed;
  final PlaybackChannel channel;

  /// True when nothing needs transforming (default 1.0x, both ears).
  bool get isIdentity => speed == 1.0 && channel == PlaybackChannel.both;

  PlaybackPrefs copyWith({double? speed, PlaybackChannel? channel}) =>
      PlaybackPrefs(
        speed: speed ?? this.speed,
        channel: channel ?? this.channel,
      );

  @override
  bool operator ==(Object other) =>
      other is PlaybackPrefs &&
      other.speed == speed &&
      other.channel == channel;

  @override
  int get hashCode => Object.hash(speed, channel);
}

/// Global, listenable playback preferences. The audio port reads this before
/// each play; the control widget writes to it.
final ValueNotifier<PlaybackPrefs> playbackPrefs =
    ValueNotifier<PlaybackPrefs>(const PlaybackPrefs());

/// Loads persisted playback prefs. Call once at startup; failures fall back to
/// defaults.
Future<void> loadPlaybackPrefs([PlaybackPrefsStore? store]) async {
  try {
    playbackPrefs.value = await (store ?? PlaybackPrefsStore()).load();
  } catch (_) {
    playbackPrefs.value = const PlaybackPrefs();
  }
}

/// SharedPreferences-backed persistence for [PlaybackPrefs].
class PlaybackPrefsStore {
  PlaybackPrefsStore({this.prefix = 'hearbloom.playback.v1'});

  final String prefix;

  String get _speedKey => '$prefix.speed';
  String get _channelKey => '$prefix.channel';

  Future<PlaybackPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PlaybackPrefs(
      speed: prefs.getDouble(_speedKey) ?? 1.0,
      channel: PlaybackChannelInfo.fromStorage(prefs.getString(_channelKey)),
    );
  }

  Future<void> setSpeed(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speedKey, value);
    playbackPrefs.value = playbackPrefs.value.copyWith(speed: value);
  }

  Future<void> setChannel(PlaybackChannel value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_channelKey, value.storageKey);
    playbackPrefs.value = playbackPrefs.value.copyWith(channel: value);
  }
}

/// Resamples mono [samples] for a relative playback [speed] (>1 = faster/shorter,
/// <1 = slower/longer) using linear interpolation. Speed also shifts pitch —
/// this is a literal playback-rate change, matching a tape-style speed control.
List<double> resampleForSpeed(List<double> samples, double speed) {
  if (samples.isEmpty || speed <= 0 || speed == 1.0) {
    return List<double>.of(samples);
  }
  final outLen = (samples.length / speed).round();
  if (outLen <= 0) return <double>[];
  final out = List<double>.filled(outLen, 0.0);
  for (var i = 0; i < outLen; i++) {
    final src = i * speed;
    final i0 = src.floor();
    final i1 = i0 + 1;
    final frac = src - i0;
    final a = i0 < samples.length ? samples[i0] : 0.0;
    final b = i1 < samples.length ? samples[i1] : a;
    out[i] = a + (b - a) * frac;
  }
  return out;
}

/// Applies [prefs] (speed + channel routing) to a mono 16-bit WAV [wavBytes],
/// returning a new WAV buffer. Speed resamples; channel routing produces a
/// stereo buffer with the unused ear silenced (or the original mono when
/// [PlaybackChannel.both]). A passthrough when [PlaybackPrefs.isIdentity].
Uint8List transformPlayback(Uint8List wavBytes, PlaybackPrefs prefs) {
  if (prefs.isIdentity) return wavBytes;
  final DecodedPcm decoded;
  try {
    decoded = decodeWav16(wavBytes);
  } catch (_) {
    return wavBytes; // not decodable → leave untouched
  }
  var samples = decoded.samples;
  final sr = decoded.sampleRate;
  if (prefs.speed != 1.0) samples = resampleForSpeed(samples, prefs.speed);
  switch (prefs.channel) {
    case PlaybackChannel.both:
      return encodeWav16(samples, sampleRate: sr);
    case PlaybackChannel.left:
      return encodeWavStereo16(samples, silence(0, sr), sampleRate: sr);
    case PlaybackChannel.right:
      return encodeWavStereo16(silence(0, sr), samples, sampleRate: sr);
  }
}

/// An app-bar "tune" button that opens a compact panel of manual playback
/// controls (speed + output channel). Preferences are persisted and applied by
/// the audio port before the next play. Presentation only.
class PlaybackControlsButton extends StatelessWidget {
  const PlaybackControlsButton({super.key, this.store});

  final PlaybackPrefsStore? store;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackPrefs>(
      valueListenable: playbackPrefs,
      builder: (context, prefs, _) {
        final active = !prefs.isIdentity;
        return IconButton(
          key: const Key('playback-controls-button'),
          tooltip: 'Playback speed & channel',
          isSelected: active,
          icon: Icon(active ? Icons.tune : Icons.tune_outlined),
          onPressed: () => _openPanel(context),
        );
      },
    );
  }

  Future<void> _openPanel(BuildContext context) {
    final s = store ?? PlaybackPrefsStore();
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Playback controls'),
        content: ValueListenableBuilder<PlaybackPrefs>(
          valueListenable: playbackPrefs,
          builder: (context, prefs, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Speed', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SegmentedButton<double>(
                key: const Key('playback-speed'),
                segments: [
                  for (final sp in kPlaybackSpeeds)
                    ButtonSegment<double>(
                      value: sp,
                      label: Text('${sp}x'),
                    ),
                ],
                selected: <double>{prefs.speed},
                showSelectedIcon: false,
                onSelectionChanged: (set) => s.setSpeed(set.first),
              ),
              const SizedBox(height: 16),
              const Text('Channel',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SegmentedButton<PlaybackChannel>(
                key: const Key('playback-channel'),
                segments: [
                  for (final c in PlaybackChannel.values)
                    ButtonSegment<PlaybackChannel>(
                      value: c,
                      label: Text(c.label),
                    ),
                ],
                selected: <PlaybackChannel>{prefs.channel},
                showSelectedIcon: false,
                onSelectionChanged: (set) => s.setChannel(set.first),
              ),
              const SizedBox(height: 12),
              const Text(
                'Presentation only — never changes master volume or scoring.',
                style: TextStyle(fontSize: 11.5, color: Color(0xff94a3b8)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              s.setSpeed(1.0);
              s.setChannel(PlaybackChannel.both);
            },
            child: const Text('Reset'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
