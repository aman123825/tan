/// Headless checks for the Tier-3 (27 Jul 2026) additions: residual
/// inhibition, the desensitization ladder's safety invariants, the
/// NOAH-style audiogram XML and the music masker.
library;

import 'dart:io';

import '../../lib/core/audio/pcm_synth.dart';
import '../../lib/core/audio/timbre.dart';
import '../../lib/core/audiogram.dart';
import '../../lib/core/noah_export.dart';
import '../../lib/core/session_summary.dart';
import '../../lib/core/tinnitus/desensitization.dart';
import '../../lib/core/tinnitus/levels.dart';
import '../../lib/core/tinnitus/residual_inhibition.dart';

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
  // --- Residual inhibition ---
  {
    final s = ResidualInhibitionSession(mmlDb: 12);
    check('RI masker = MML + 10', s.maskerDb == 22);
    check('RI masker amplitude under the safety cap',
        s.maskerAmplitude <= kMaxSafeAmp);
    // A huge MML cannot push the masker past the cap level.
    final loud = ResidualInhibitionSession(mmlDb: 100);
    check('RI masker level clamped at the cap',
        loud.maskerDb <= amplitudeCapDb() &&
            loud.maskerAmplitude <= kMaxSafeAmp);
    s.recordDepth(RiDepth.partial);
    check('RI incomplete until the return time arrives', !s.isComplete);
    s.recordReturnSeconds(23.4);
    check('RI complete + positive with suppression',
        s.isComplete && s.positive);
    check('RI record carries masker + return parameters', () {
      final r = s.records.single;
      return r.parameters['mml_db'] == 12 &&
          r.parameters['masker_db'] == 22 &&
          (r.parameters['return_seconds'] as double) == 23.4 &&
          r.correct;
    }());
    check('RI summary mentions the duration',
        s.summary().contains('23 s'));
    final none = ResidualInhibitionSession(mmlDb: 12)
      ..recordDepth(RiDepth.none);
    check('RI "none" completes without timing',
        none.isComplete && !none.positive);
    final metric = summarizeSession(s)!;
    check('RI metric: seconds value + positive sub-score',
        metric.value == 23.4 && metric.sub!['positive'] == 1);
  }

  // --- Desensitization ladder safety ---
  {
    final p = DesensitizationProgram(ldlDb: 30);
    check('desens ceiling = LDL − 10', p.ceilingDb == 20);
    var monotone = true, capped = true;
    for (var i = 1; i < kDesensitizationSteps; i++) {
      if (p.levelForStep(i) < p.levelForStep(i - 1)) monotone = false;
      if (p.levelForStep(i) > p.ceilingDb) capped = false;
    }
    check('desens ladder rises monotonically', monotone);
    check('desens ladder never exceeds the ceiling', capped);
    check('desens final step reaches the ceiling',
        p.levelForStep(kDesensitizationSteps - 1) == p.ceilingDb);
    check('desens amplitude always under the safety cap', () {
      for (var i = 0; i < kDesensitizationSteps; i++) {
        if (relativeDbToAmplitude(p.levelForStep(i)) > kMaxSafeAmp) {
          return false;
        }
      }
      return true;
    }());
    final noLdl = DesensitizationProgram();
    check('desens without LDL uses cap − 10',
        noLdl.ceilingDb == amplitudeCapDb() - 10);
    check('desens one-step-per-day rule', () {
      final today = DateTime(2026, 7, 27);
      return canCompleteStepToday(null, today) &&
          canCompleteStepToday('2026-07-26', today) &&
          !canCompleteStepToday('2026-07-27', today);
    }());
    p.completedSteps = kDesensitizationSteps;
    check('desens finished flag', p.isFinished);
    p.completeStep();
    check('desens completeStep is a no-op when finished',
        p.completedSteps == kDesensitizationSteps);
  }

  // --- NOAH-style XML ---
  {
    final session = AudiogramSession(seed: 4);
    var guard = 0;
    while (!session.isComplete && guard < 2000) {
      final pres = session.next()!;
      session.submit(!pres.isCatch && pres.levelDbfs >= -50);
      guard++;
    }
    final xml = noahStyleAudiogramXml(
      session,
      measuredAt: DateTime.utc(2026, 7, 27, 12),
      patientName: 'A <b> & "c"',
    );
    check('NOAH xml declares itself unofficial + dBFS',
        xml.contains('official="false"') && xml.contains('not dB HL'));
    check('NOAH xml has both ears',
        xml.contains('Ear="AudRight"') && xml.contains('Ear="AudLeft"'));
    check('NOAH xml escapes patient name',
        xml.contains('A &lt;b&gt; &amp; &quot;c&quot;'));
    check('NOAH xml has tone points with frequency + level',
        RegExp('<TonePoints').allMatches(xml).length >= 6 &&
            xml.contains('<StimulusFrequency>1000</StimulusFrequency>'));
    check('NOAH xml balanced root',
        xml.trim().endsWith('</HearBloomNoahStyleExport>') &&
            xml.contains('<HearBloomNoahStyleExport'));
    check('xmlEscape covers all five entities',
        xmlEscape('<&>"\'') == '&lt;&amp;&gt;&quot;&apos;');
  }

  // --- Music masker (K4) ---
  {
    final a = musicMaskerStimulus(seconds: 2, seed: 3);
    final b = musicMaskerStimulus(seconds: 2, seed: 3);
    check('music masker deterministic',
        a.length == b.length && a[1000] == b[1000]);
    check('music masker length honours seconds',
        (a.length - 2 * kSampleRate).abs() <= 2);
    check('music masker peak-normalized',
        a.every((v) => v.abs() <= 0.9 + 1e-9) && rms(a) > 0.01);
    final other = musicMaskerStimulus(seconds: 2, seed: 4);
    var diff = 0.0;
    for (var i = 0; i < a.length; i++) {
      diff += (a[i] - other[i]).abs();
    }
    check('music masker varies with seed', diff / a.length > 1e-3);
  }

  stdout.writeln(_failures == 0
      ? 'ALL TIER3 CHECKS PASSED'
      : '$_failures TIER3 CHECKS FAILED');
  if (_failures > 0) exit(1);
}
