/// Headless checks for the 26-27 Jul 2026 diagnostic additions:
/// screening audiogram (modified Hughson-Westlake), ITD/ILD lateralization
/// JND synthesis, fixed-SNR figure-ground scoring, hummed pattern responses,
/// adaptive sentence-closure response sets, confusion-pair persistence and
/// the pure-Dart PDF writer.
library;

import 'dart:io';
import 'dart:math' as math;

import '../../lib/core/audiogram.dart';
import '../../lib/core/audio/pcm_synth.dart';
import '../../lib/core/audio/voice_variants.dart';
import '../../lib/core/binaural_jnd.dart';
import '../../lib/core/figure_ground.dart';
import '../../lib/core/pattern_test.dart';
import '../../lib/core/pdf_writer.dart';
import '../../lib/core/protocol_engine.dart';
import '../../lib/core/session_summary.dart';
import '../../lib/core/speech_in_noise.dart';
import '../../lib/core/training/sentence_closure.dart';

int _failures = 0;

void check(String name, bool condition) {
  if (condition) {
    stdout.writeln('PASS $name');
  } else {
    _failures++;
    stdout.writeln('FAIL $name');
  }
}

void main() {
  // --- Hughson-Westlake track: down-10/up-5, 2-of-ascending threshold ---
  {
    final t = HughsonWestlakeTrack(start: -40);
    // Heard at -40 (first presentation counts as an ascent) → -50.
    t.submit(true);
    check('HW descends 10 after heard', t.level == -50);
    t.submit(false); // -50 not heard → -45
    check('HW ascends 5 after not heard', t.level == -45);
    t.submit(true); // heard on ascent at -45 (1st) → -55
    check('HW no threshold after one ascending yes', t.threshold == null);
    t.submit(false); // -55 no → -50
    t.submit(false); // -50 no → -45
    t.submit(true); // heard on ascent at -45 (2nd) → threshold!
    check('HW threshold = level with 2 ascending responses',
        t.threshold == -45 && t.isComplete);
  }
  {
    // Never hearing pins the level at the cap and ends as no-response.
    final t = HughsonWestlakeTrack(start: -40);
    for (var i = 0; i < 12 && !t.isComplete; i++) {
      t.submit(false);
    }
    check('HW no-response at cap', t.noResponse && t.threshold == null);
    check('HW level never exceeds cap', t.level <= kMaxLevelDbfs);
  }

  // --- Audiogram session: sequencing, catch trials, PTA ---
  {
    final s = AudiogramSession(seed: 1);
    check('audiogram starts right ear at 1 kHz',
        s.currentEar == 'right' && s.currentFreqHz == 1000);
    var guard = 0;
    while (!s.isComplete && guard < 2000) {
      final p = s.next()!;
      // Simulated listener: hears tones at/above −55 dBFS, rejects catches.
      s.submit(!p.isCatch && p.levelDbfs >= -55);
      guard++;
    }
    check('audiogram completes', s.isComplete);
    check('audiogram covers both ears × 6 freqs', () {
      for (final ear in const ['right', 'left']) {
        for (final f in kAudiogramFrequencies) {
          if (s.thresholdFor(ear, f) == null && !s.noResponseFor(ear, f)) {
            return false;
          }
        }
      }
      return true;
    }());
    final pta = s.ptaFor('right');
    check('audiogram PTA near simulated -55 threshold',
        pta != null && (pta - -52.5).abs() <= 5);
    check('audiogram catch trials presented and rejected',
        s.catchTrials > 0 && s.falseAlarms == 0);
    final metric = summarizeSession(s);
    check('audiogram metric has per-frequency sub-scores',
        metric != null &&
            metric.sub!.containsKey('R1000') &&
            metric.sub!.containsKey('pta_right') &&
            metric.higherIsBetter == false);
  }

  // --- ITD/ILD synthesis ---
  {
    final d = fractionalDelay(<double>[1, 0, 0, 0], 1.5);
    check('fractional delay interpolates',
        d.length == 4 && d[0] == 0 && (d[1] - 0.5).abs() < 1e-9 &&
            (d[2] - 0.5).abs() < 1e-9);
    final itd = itdTone(500, leadingSide: 'left');
    check('ITD tone: same length, right ear delayed copy',
        itd.left.length == itd.right.length &&
            itd.left.isNotEmpty &&
            rms(itd.right) > 0);
    // Cross-correlate at the expected lag: the delayed channel matches the
    // lead shifted by ITD samples.
    final lag = (500e-6 * kSampleRate).round();
    var diff = 0.0;
    for (var i = lag; i < itd.left.length; i++) {
      diff += (itd.right[i] - itd.left[i - lag]).abs();
    }
    check('ITD delay ≈ requested lag', diff / itd.left.length < 0.02);
    final ild = ildNoise(6, louderSide: 'right', seed: 5);
    final ratioDb = 20 *
        (rms(ild.right) > 0 && rms(ild.left) > 0
            ? (log10(rms(ild.right) / rms(ild.left)))
            : 0.0);
    check('ILD level split ≈ requested dB', (ratioDb - 6).abs() < 0.5);
    final assembled = assembleTwoIntervals(
        reference: diotticTone(), target: itdTone(300, leadingSide: 'right'),
        targetIndex: 1);
    final expectedLen =
        ((kBinauralIntervalSeconds * 2 + 0.3) * kSampleRate).round();
    check('two-interval assembly length = 2 intervals + gap',
        (assembled.left.length - expectedLen).abs() <= 2 &&
            assembled.left.length == assembled.right.length);
    check('ITD/ILD tracks start sane',
        itdTrack().value == 500 && ildTrack().value == 6);
  }

  // --- Figure-ground fixed-SNR scoring ---
  {
    final s = FigureGroundSession(trialsPerSnr: 2);
    check('figure-ground starts at +8 dB', s.currentSnrDb == 8);
    final gen = FourAfcGenerator(
        const ['bell', 'ball', 'bat', 'bag', 'pen', 'pin'], seed: 3);
    // +8 block: both correct; 0 block: one correct; −8: none correct.
    for (var i = 0; i < 6; i++) {
      final t = gen.next();
      final correctAnswer = i < 2 || i == 2;
      s.submit(t, correctAnswer ? t.targetIndex : (t.targetIndex + 1) % 4,
          latencyMs: 100);
    }
    check('figure-ground completes after 3 blocks', s.isComplete);
    check(
        'figure-ground per-SNR percents',
        s.percentFor(8) == 100 &&
            s.percentFor(0) == 50 &&
            s.percentFor(-8) == 0);
    final m = summarizeSession(s)!;
    check('figure-ground metric sub-scores',
        m.sub!['snr_p8'] == 100 && m.sub!['snr_m8'] == 0 && m.unit == '%');
  }

  // --- Pattern test: hummed responses persist under their own labels ---
  {
    final s = PatternSession(
      moduleId: 'temporal',
      groupId: 'frequency_pattern_hum',
      testName: 'FPT (hummed)',
      trialsPerEar: 1,
      responseMode: PatternResponseMode.humBack,
    );
    const trial = PatternTrial('HLH', 'right');
    check('hum match scores correct',
        s.submitHum(trial, matched: true) == true);
    check('hum record response label',
        s.records.single.response == 'hum-match' &&
            s.records.single.parameters['response_mode'] == 'humBack');
    check('labels submit still works', () {
      final s2 = PatternSession(
          moduleId: 'temporal',
          groupId: 'frequency_pattern',
          testName: 'FPT',
          trialsPerEar: 1);
      s2.submit(const PatternTrial('HLH', 'right'), 'HLH');
      return s2.records.single.correct &&
          s2.records.single.target == 'HLH';
    }());
  }

  // --- Adaptive sentence closure: response-set ladder 2-up/1-down ---
  {
    final s = SentenceClosureSession(maxTrials: 10);
    final gen = SentenceClosureGenerator(seed: 2);
    check('closure starts at 4 choices', s.currentChoiceCount == 4);
    // Two correct answers widen the set.
    for (var i = 0; i < 2; i++) {
      final t = gen.next(choiceCount: s.currentChoiceCount);
      s.submit(t, t.correctIndex, latencyMs: 50);
    }
    check('closure widens to 6 after 2 correct', s.currentChoiceCount == 6);
    final wide = gen.next(choiceCount: s.currentChoiceCount);
    check('closure generator honours set size and keeps the answer',
        wide.choices.length == 6 &&
            wide.choices.contains(wide.answer) &&
            wide.choices.toSet().length == 6);
    s.submit(wide, (wide.correctIndex + 1) % wide.choices.length,
        latencyMs: 50);
    check('closure narrows after an error', s.currentChoiceCount == 4);
    check('closure records choices parameter',
        s.records.last.parameters['choices'] == 6);
    check('closure metric reports max choices',
        summarizeSession(s)!.sub!['max_choices'] == 6);
  }

  // --- Confusion-pair persistence ---
  {
    final records = <TrialRecord>[
      TrialRecord(target: 'ba', response: 'pa', correct: false, latencyMs: 1),
      TrialRecord(target: 'ba', response: 'ba', correct: true, latencyMs: 1),
      TrialRecord(
          target: 'interval_1',
          response: 'interval_2',
          correct: false,
          latencyMs: 1),
      TrialRecord(target: 'da', response: '', correct: false, latencyMs: 1),
    ];
    final pairs = confusionPairsOf(records)!;
    check('confusion pairs keep labels, skip intervals/blanks',
        pairs.length == 2 &&
            pairs[0][0] == 'ba' &&
            pairs[0][1] == 'pa' &&
            pairs[1][1] == 'ba');
    check('confusion pairs null when nothing usable',
        confusionPairsOf(<TrialRecord>[
              TrialRecord(
                  target: 'interval_1',
                  response: 'interval_3',
                  correct: false,
                  latencyMs: 1)
            ]) ==
            null);
  }

  // --- Voice variants: deterministic, length scales by ratio ---
  {
    check('voice rotation deterministic',
        voiceForTrial(7, 3).id == voiceForTrial(7, 3).id &&
            kVoiceVariants.length == 4);
    final base = List<double>.generate(1000, (i) => i / 1000);
    final low = applyVoiceVariant(base, const VoiceVariant('x', 'X', 0.84));
    check('variant 0.84 lengthens ≈ 1/0.84',
        (low.length - (1000 / 0.84)).abs() <= 1);
    final same = applyVoiceVariant(base, kVoiceVariants.first);
    check('ratio 1.0 is identity', same.length == 1000 && same[500] == 0.5);
  }

  // --- PDF writer: emits a structurally valid PDF ---
  {
    final bytes = buildSimplePdf(
      title: 'Harness report',
      blocks: <PdfBlock>[
        const PdfHeading('Harness report', level: 1),
        const PdfKeyValue('Patient', 'Test'),
        const PdfTableRow(<String>['Test', 'Score'], bold: true),
        const PdfTableRow(<String>['Gap detection', '3.2 ms']),
        PdfParagraph('Long paragraph. ' * 60),
        const PdfDivider(),
        const PdfParagraph('Research only — not a diagnosis.', gray: true),
      ],
      tableColumns: const <double>[0.6, 0.4],
    );
    final text = String.fromCharCodes(bytes);
    check('PDF header/EOF', text.startsWith('%PDF-1.4') &&
        text.trimRight().endsWith('%%EOF'));
    check('PDF has xref + trailer',
        text.contains('\nxref\n') && text.contains('/Root 1 0 R'));
    check('PDF startxref offset points at xref', () {
      final m = RegExp(r'startxref\n(\d+)').firstMatch(text)!;
      final off = int.parse(m.group(1)!);
      return text.substring(off).startsWith('xref');
    }());
    check('PDF pages counted', RegExp(r'/Type /Page[ >]')
            .allMatches(text)
            .length >=
        1);
    check('PDF is ASCII-only bytes', bytes.every((b) => b < 128));
    // Every object offset in the xref table must point at "N 0 obj".
    check('PDF xref offsets resolve', () {
      final xref = text.substring(text.indexOf('\nxref\n') + 1);
      final lines = xref.split('\n');
      // lines[0]=xref, [1]="0 N", [2]=free entry, then offsets.
      final count = int.parse(lines[1].split(' ')[1]);
      for (var i = 1; i < count; i++) {
        final off = int.parse(lines[2 + i].split(' ')[0]);
        if (!text.substring(off).startsWith('$i 0 obj')) return false;
      }
      return true;
    }());
  }

  stdout.writeln(_failures == 0
      ? 'ALL DIAGNOSTICS CHECKS PASSED'
      : '$_failures DIAGNOSTICS CHECKS FAILED');
  if (_failures > 0) exit(1);
}

double log10(double x) =>
    x <= 0 ? double.negativeInfinity : math.log(x) / math.ln10;
