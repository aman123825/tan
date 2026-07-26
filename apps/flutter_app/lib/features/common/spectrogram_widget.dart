import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';

/// Computes a simple magnitude spectrogram from mono [samples].
///
/// The signal is split into overlapping frames of [fftSize] samples (default
/// 32) stepped by [hop]; each frame is Hann-windowed and its magnitude spectrum
/// is evaluated at the `fftSize/2` non-negative-frequency bins by *direct DFT
/// summation* (no FFT library — small N keeps it cheap). The result is
/// `frames × bins` intensities normalized to `[0, 1]` with a mild square-root
/// (perceptual) compression.
///
/// Returns an empty list when there are fewer than [fftSize] samples.
List<List<double>> computeSpectrogram(
  List<double> samples, {
  int fftSize = 32,
  int? hop,
  int sampleRate = 48000,
}) {
  if (samples.length < fftSize || fftSize < 2) return const <List<double>>[];
  final step = hop ?? (fftSize ~/ 2);
  final bins = fftSize ~/ 2;
  // Precompute the Hann window.
  final window = List<double>.generate(
      fftSize, (n) => 0.5 * (1 - cos(2 * pi * n / (fftSize - 1))));
  final frames = <List<double>>[];
  var maxMag = 0.0;
  for (var start = 0; start + fftSize <= samples.length; start += step) {
    final mags = List<double>.filled(bins, 0.0);
    for (var k = 0; k < bins; k++) {
      var re = 0.0;
      var im = 0.0;
      for (var n = 0; n < fftSize; n++) {
        final x = samples[start + n] * window[n];
        final angle = 2 * pi * k * n / fftSize;
        re += x * cos(angle);
        im -= x * sin(angle);
      }
      final mag = sqrt(re * re + im * im);
      mags[k] = mag;
      if (mag > maxMag) maxMag = mag;
    }
    frames.add(mags);
  }
  // Normalize + perceptual (sqrt) compression.
  if (maxMag > 0) {
    for (final f in frames) {
      for (var k = 0; k < f.length; k++) {
        f[k] = sqrt((f[k] / maxMag).clamp(0.0, 1.0));
      }
    }
  }
  return frames;
}

/// Maps an intensity in [0, 1] to a spectrogram colour (dark navy → blue →
/// cyan → yellow → white).
Color spectrogramColor(double t) {
  final v = t.clamp(0.0, 1.0);
  const stops = <Color>[
    Color(0xff0b1026),
    Color(0xff2b3a8f),
    Color(0xff1e9fd0),
    Color(0xff36d17a),
    Color(0xfff2e14a),
    Color(0xfffdfdfd),
  ];
  if (v <= 0) return stops.first;
  if (v >= 1) return stops.last;
  final scaled = v * (stops.length - 1);
  final i = scaled.floor();
  final frac = scaled - i;
  return Color.lerp(stops[i], stops[i + 1], frac) ?? stops[i];
}

/// Visualizes precomputed [samples] as a spectrogram (time → x, frequency → y,
/// magnitude → colour). Frequency increases upward.
class SpectrogramWidget extends StatelessWidget {
  const SpectrogramWidget({
    super.key,
    required this.samples,
    this.sampleRate = 48000,
    this.fftSize = 32,
    this.height = 120,
  });

  final List<double> samples;
  final int sampleRate;
  final int fftSize;
  final double height;

  @override
  Widget build(BuildContext context) {
    final frames = computeSpectrogram(samples,
        fftSize: fftSize, sampleRate: sampleRate);
    return Semantics(
      label: 'Spectrogram of the last sound',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: frames.isEmpty
              ? Container(
                  color: const Color(0xff0b1026),
                  alignment: Alignment.center,
                  child: const Text('No audio to display yet',
                      style:
                          TextStyle(color: Color(0xff94a3b8), fontSize: 12)),
                )
              : CustomPaint(painter: _SpectrogramPainter(frames)),
        ),
      ),
    );
  }
}

class _SpectrogramPainter extends CustomPainter {
  _SpectrogramPainter(this.frames);

  /// frames × bins, each intensity in [0, 1].
  final List<List<double>> frames;

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;
    final cols = frames.length;
    final rows = frames.first.length;
    if (rows == 0) return;
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var c = 0; c < cols; c++) {
      final frame = frames[c];
      for (var r = 0; r < rows; r++) {
        // Frequency increases upward → flip the row index.
        final intensity = frame[r];
        paint.color = spectrogramColor(intensity);
        final rect = Rect.fromLTWH(
          c * cellW,
          size.height - (r + 1) * cellH,
          cellW + 0.5, // slight overlap to avoid seams
          cellH + 0.5,
        );
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SpectrogramPainter old) =>
      !identical(old.frames, frames);
}

/// An optional, collapsible spectrogram panel intended to sit below the audio
/// wave animation. It renders only when the "Show spectrogram" preference is
/// on (via [appSettings]); otherwise it takes no space.
class SpectrogramPanel extends StatelessWidget {
  const SpectrogramPanel({
    super.key,
    required this.samples,
    this.sampleRate = 48000,
    this.title = 'Spectrogram',
  });

  final List<double> samples;
  final int sampleRate;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: appSettings,
      builder: (context, settings, _) {
        if (!settings.showSpectrogram) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x1affffff), Color(0x0dffffff)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x33ffffff)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.gradient, size: 15, color: Color(0xff94a3b8)),
                  const SizedBox(width: 6),
                  Text(title,
                      style: const TextStyle(
                          color: Color(0xffe2e8f0),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              SpectrogramWidget(samples: samples, sampleRate: sampleRate),
            ],
          ),
        );
      },
    );
  }
}
