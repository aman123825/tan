/// NOAH-style audiogram XML export (pure Dart, Flutter-free).
///
/// Emits the screening audiogram as XML structured after HIMSA's public
/// audiogram data standard (format 500): one `ToneThresholdAudiogram` per
/// ear with `TonePoints` (`StimulusFrequency` in Hz, `StimulusLevel` in dB).
///
/// UNOFFICIAL: HearBloom is not HIMSA-certified and this is not a NOAH
/// module — the file is for import tooling and record-keeping only. Levels
/// are **dB re: full scale on uncalibrated audio, NOT dB HL**; both caveats
/// are embedded in the document itself so they travel with the data.
library;

import 'audiogram.dart';

/// Escapes the five XML special characters.
String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Builds the NOAH-style XML document for a completed [session].
///
/// [measuredAt] stamps the record (callers pass a real timestamp; kept as a
/// parameter so the output stays deterministic for tests). Frequencies with
/// no threshold and no no-response marker are omitted; a no-response at the
/// cap is exported at the cap level with `NoResponse="true"`.
String noahStyleAudiogramXml(
  AudiogramSession session, {
  required DateTime measuredAt,
  String patientName = 'On-device listener',
}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<!-- UNOFFICIAL NOAH-style export from HearBloom research '
        'software. NOT dB HL: levels are dB re: full scale on uncalibrated '
        'consumer audio. Not a hearing test, not a diagnosis. -->')
    ..writeln('<HearBloomNoahStyleExport formatInspiredBy='
        '"HIMSA Audiogram 500" official="false">')
    ..writeln('  <ExportDate>${measuredAt.toIso8601String()}</ExportDate>')
    ..writeln('  <Patient>')
    ..writeln('    <Name>${xmlEscape(patientName)}</Name>')
    ..writeln('  </Patient>')
    ..writeln('  <Caveats>')
    ..writeln('    <Caveat>Levels are dB re: full scale (dBFS), not '
        'dB HL.</Caveat>')
    ..writeln('    <Caveat>Screening on uncalibrated audio; curve shape '
        'only.</Caveat>')
    ..writeln('    <Caveat>Research software, not a medical device.</Caveat>')
    ..writeln('  </Caveats>');
  for (final earSpec in const [('right', 'AudRight'), ('left', 'AudLeft')]) {
    final (ear, tag) = earSpec;
    b
      ..writeln('  <ToneThresholdAudiogram Ear="$tag">')
      ..writeln('    <AudMeasurementConditions>')
      ..writeln('      <StimulusSignalType>PureTone</StimulusSignalType>')
      ..writeln('      <StimulusSignalOutput>Headphones'
          '</StimulusSignalOutput>')
      ..writeln('      <LevelUnit>dBFS</LevelUnit>')
      ..writeln('      <TestMethod>ModifiedHughsonWestlake</TestMethod>')
      ..writeln('    </AudMeasurementConditions>');
    for (final f in kAudiogramFrequencies) {
      final t = session.thresholdFor(ear, f);
      final noResponse = session.noResponseFor(ear, f);
      if (t == null && !noResponse) continue;
      final level = t ?? kMaxLevelDbfs;
      b
        ..writeln('    <TonePoints'
            '${noResponse ? ' NoResponse="true"' : ''}>')
        ..writeln('      <StimulusFrequency>${f.round()}'
            '</StimulusFrequency>')
        ..writeln('      <StimulusLevel>${level.toStringAsFixed(0)}'
            '</StimulusLevel>')
        ..writeln('    </TonePoints>');
    }
    b.writeln('  </ToneThresholdAudiogram>');
  }
  b.writeln('</HearBloomNoahStyleExport>');
  return b.toString();
}
