import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'report_printer_io.dart'
    if (dart.library.js_interop) 'report_printer_web.dart' as printer;
import 'pdf_saver_io.dart' if (dart.library.js_interop) 'pdf_saver_web.dart'
    as pdf_saver;

import 'confusion_matrix_page.dart';
import 'staircase_plot.dart';
import '../../core/confusion_matrix.dart';
import '../../core/fhir_export.dart';
import '../../core/pdf_writer.dart';
import '../../core/phoneme_analysis.dart';
import '../../core/narrative_report.dart';
import '../../core/psychometrics.dart';

/// Per-test outcome status shown in the results table. [info] means the value
/// was recorded but no defensible reference band exists — the report never
/// invents a status.
enum ReportStatus { normal, borderline, below, info }

extension ReportStatusInfo on ReportStatus {
  String get label => switch (this) {
        ReportStatus.normal => 'Normal',
        ReportStatus.borderline => 'Borderline',
        ReportStatus.below => 'Below',
        ReportStatus.info => 'Recorded',
      };

  /// Print-friendly (dark-on-light) status colour.
  Color get color => switch (this) {
        ReportStatus.normal => const Color(0xff15803d),
        ReportStatus.borderline => const Color(0xffb45309),
        ReportStatus.below => const Color(0xffb91c1c),
        ReportStatus.info => const Color(0xff475569),
      };

  IconData get icon => switch (this) {
        ReportStatus.normal => Icons.check_circle,
        ReportStatus.borderline => Icons.error_outline,
        ReportStatus.below => Icons.cancel,
        ReportStatus.info => Icons.radio_button_unchecked,
      };
}

/// One staircase run for the report's trajectory plot (real per-trial data
/// persisted by `_persistRun` via `core/session_summary.dart`).
class StaircaseRun {
  const StaircaseRun({
    required this.title,
    required this.values,
    required this.reversalIndices,
    required this.unit,
    this.threshold,
    this.correct,
    this.chanceLevel,
  });

  final String title;
  final List<double> values;
  final List<int> reversalIndices;
  final String unit;
  final double? threshold;

  /// Per-trial correctness aligned with [values] (for the psychometric fit).
  final List<bool>? correct;

  /// Guess rate γ for the fit (1/n for nAFC, 0 for open-set), when known.
  final double? chanceLevel;
}

/// Buffalo-Model central-auditory-processing categories used to classify a
/// profile from the pattern of below/borderline results.
enum BuffaloProfile {
  auditoryDecoding,
  toleranceFadingMemory,
  integration,
  organization,
  prosodic,
}

extension BuffaloProfileInfo on BuffaloProfile {
  String get title => switch (this) {
        BuffaloProfile.auditoryDecoding => 'Auditory Decoding',
        BuffaloProfile.toleranceFadingMemory => 'Tolerance-Fading Memory',
        BuffaloProfile.integration => 'Integration',
        BuffaloProfile.organization => 'Organization',
        BuffaloProfile.prosodic => 'Prosodic',
      };

  String get description => switch (this) {
        BuffaloProfile.auditoryDecoding =>
          'Difficulty analysing speech sounds quickly and accurately, '
              'especially in noise or when speech is degraded.',
        BuffaloProfile.toleranceFadingMemory =>
          'Reduced tolerance for background noise and/or weaker auditory '
              'short-term memory and sequencing.',
        BuffaloProfile.integration =>
          'Difficulty combining information across the two ears / senses '
              '(dichotic and binaural integration).',
        BuffaloProfile.organization =>
          'Difficulty organising and sequencing auditory output in the '
              'correct order.',
        BuffaloProfile.prosodic =>
          'Difficulty using pitch, timing and stress (prosody / patterning) '
              'cues in speech and music.',
      };
}

/// One measured test in the report. Extends the simple table row with an ear
/// column and a three-level status (normal / borderline / below).
class ReportTest {
  const ReportTest({
    required this.name,
    required this.score,
    required this.norm,
    required this.status,
    this.ear = '—',
    this.profile,
  });

  final String name;
  final String score;
  final String norm;
  final ReportStatus status;

  /// "Left", "Right", "Both", or "—" (not ear-specific).
  final String ear;

  /// Buffalo category this test loads onto (null if not classifiable).
  final BuffaloProfile? profile;
}

/// Demonstration result set so the report renders standalone.
const List<ReportTest> kSampleReportTests = <ReportTest>[
  ReportTest(
    name: 'Random Gap Detection',
    score: '7.5 ms',
    norm: '≤ 8 ms',
    status: ReportStatus.normal,
    ear: 'Both',
    profile: BuffaloProfile.prosodic,
  ),
  ReportTest(
    name: 'Dichotic Digits — Left',
    score: '78%',
    norm: '≥ 90%',
    status: ReportStatus.below,
    ear: 'Left',
    profile: BuffaloProfile.integration,
  ),
  ReportTest(
    name: 'Dichotic Digits — Right',
    score: '92%',
    norm: '≥ 90%',
    status: ReportStatus.normal,
    ear: 'Right',
    profile: BuffaloProfile.integration,
  ),
  ReportTest(
    name: 'Phoneme discrimination',
    score: '64%',
    norm: '≥ 80%',
    status: ReportStatus.below,
    ear: 'Both',
    profile: BuffaloProfile.auditoryDecoding,
  ),
  ReportTest(
    name: 'Sentences in noise (SNR-50)',
    score: '+1.2 dB',
    norm: '≈ −2.9 dB',
    status: ReportStatus.borderline,
    ear: 'Both',
    profile: BuffaloProfile.toleranceFadingMemory,
  ),
  ReportTest(
    name: 'Duration Pattern Test',
    score: '73%',
    norm: '≥ 75%',
    status: ReportStatus.borderline,
    ear: 'Both',
    profile: BuffaloProfile.prosodic,
  ),
  ReportTest(
    name: 'Digit span (forward)',
    score: '5 digits',
    norm: '≥ 6 digits',
    status: ReportStatus.below,
    ear: '—',
    profile: BuffaloProfile.toleranceFadingMemory,
  ),
];

/// The set of Buffalo categories with any below/borderline result.
Set<BuffaloProfile> affectedProfiles(List<ReportTest> tests) {
  final out = <BuffaloProfile>{};
  for (final t in tests) {
    if (t.profile != null && t.status != ReportStatus.normal) {
      out.add(t.profile!);
    }
  }
  return out;
}

/// Human-readable profile classification sentence(s).
String classifyBuffaloProfile(List<ReportTest> tests) {
  final affected = affectedProfiles(tests);
  if (affected.isEmpty) {
    return 'All tested domains fall within their task-relative typical ranges. '
        'No clear Buffalo-Model central-auditory-processing weakness was '
        'observed. This is a research summary, not a clinical diagnosis.';
  }
  final names = affected.map((p) => p.title).join(', ');
  return 'The pattern of below/borderline scores is most consistent with the '
      'following Buffalo-Model categor${affected.length == 1 ? 'y' : 'ies'}: '
      '$names. This is a research profile, NOT a clinical diagnosis.';
}

/// Deficit-specific, non-clinical suggestions keyed to affected categories.
List<String> reportRecommendations(List<ReportTest> tests) {
  final affected = affectedProfiles(tests);
  final recs = <String>[];
  if (affected.contains(BuffaloProfile.auditoryDecoding)) {
    recs.add(
        'Phonemic training recommended — structured phoneme-discrimination '
        'and auditory-closure practice.');
  }
  if (affected.contains(BuffaloProfile.toleranceFadingMemory)) {
    recs.add('Working-memory and sequencing practice (digit span, n-back); '
        'chunking and note-taking strategies; reduce memory load.');
  }
  if (affected.contains(BuffaloProfile.integration)) {
    recs.add('Dichotic-listening / binaural-integration training targets may '
        'be explored.');
  }
  if (affected.contains(BuffaloProfile.organization)) {
    recs.add('Sequencing and organisation strategies; structured, ordered '
        'routines for multi-step instructions.');
  }
  if (affected.contains(BuffaloProfile.prosodic)) {
    recs.add('Prosody and temporal-patterning practice; music-based listening '
        'activities.');
  }
  if (affected.contains(BuffaloProfile.auditoryDecoding) ||
      affected.contains(BuffaloProfile.toleranceFadingMemory) ||
      affected.contains(BuffaloProfile.integration)) {
    recs.add('Consider a remote-microphone / FM system in the classroom and '
        'preferential, front-facing seating.');
  }
  recs.add('Refer to a qualified audiologist for a calibrated, validated '
      'clinical CAPD assessment before any diagnosis or intervention.');
  return recs;
}

/// A comprehensive, print-styled on-screen CAPD research report.
///
/// Renders a light "paper" card (even inside the dark app) so it prints cleanly
/// via the browser (Ctrl+P / the Print button on web). It can also be copied as
/// formatted text. This is NOT a generated PDF file and NOT a diagnosis.
class EnhancedReportPage extends StatelessWidget {
  const EnhancedReportPage({
    super.key,
    this.patientName = '(patient name)',
    this.patientId = '(patient ID)',
    this.ageYears,
    this.date,
    this.tests = kSampleReportTests,
    this.demo = true,
    this.narrativeInput,
    this.staircase,
    this.sessionCount = 0,
    this.confusionMatrix,
    this.confusionSessionCount = 0,
    this.embedded = false,
  });

  final String patientName;
  final String patientId;
  final int? ageYears;
  final DateTime? date;
  final List<ReportTest> tests;

  /// True when showing the built-in demonstration data set (no real sessions
  /// yet). Real reports hide the demo-only sections and the demo banner.
  final bool demo;

  /// Real measured inputs for the rule-based narrative (null in demo mode).
  final NarrativeInput? narrativeInput;

  /// The most recent real staircase run, when one exists.
  final StaircaseRun? staircase;

  /// Number of stored sessions behind a real report.
  final int sessionCount;

  /// REAL aggregated response confusions from stored sessions, when any
  /// identification-style sessions have been recorded. Null in demo mode (a
  /// labelled sample matrix is shown instead) and when no session carries
  /// confusion pairs (section hidden — no data is invented).
  final ConfusionMatrix? confusionMatrix;

  /// Number of stored sessions contributing to [confusionMatrix].
  final int confusionSessionCount;

  /// Removes the page scaffold/app bar when shown inside the Report center.
  final bool embedded;

  static const Color _paper = Color(0xfff8fafc);
  static const Color _panel = Color(0xffeef2f7);
  static const Color _ink = Color(0xff0f172a);
  static const Color _muted = Color(0xff475569);
  static const Color _line = Color(0xffcbd5e1);

  String get _dateStr => DateFormat.yMMMMd().format(date ?? DateTime.now());
  String get _ageStr => ageYears == null ? '(age)' : '$ageYears years';

  String plainText() {
    final b = StringBuffer();
    b.writeln('HearBloom — CAPD Research Report');
    b.writeln('Research measurement only — not a clinical diagnosis.');
    b.writeln('');
    b.writeln('Patient: $patientName');
    b.writeln('Patient ID: $patientId');
    b.writeln('Age: $_ageStr');
    b.writeln('Date: $_dateStr');
    b.writeln('');
    b.writeln('Test Results');
    b.writeln('Test | Score | Ear | Norm | Status');
    for (final t in tests) {
      b.writeln('${t.name} | ${t.score} | ${t.ear} | ${t.norm} | '
          '${t.status.label}');
    }
    b.writeln('');
    b.writeln('CAPD Profile (Buffalo Model)');
    b.writeln(classifyBuffaloProfile(tests));
    b.writeln('');
    b.writeln('Recommendations');
    for (final r in reportRecommendations(tests)) {
      b.writeln('- $r');
    }
    b.writeln('');
    b.writeln('Narrative');
    b.writeln(generateNarrativeReport(narrativeInput ?? _demoNarrativeInput)
        .paragraph);
    if (demo) b.writeln('(Demonstration data.)');
    b.writeln('');
    b.writeln('Disclaimer: Research measurement only — not a clinical '
        'diagnosis. Measurements were taken on uncalibrated audio.');
    return b.toString();
  }

  void _copy(BuildContext context) {
    // Fire the clipboard write and confirm immediately; the write is
    // effectively synchronous from the user's perspective.
    unawaited(Clipboard.setData(ClipboardData(text: plainText())));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report text copied to clipboard')),
    );
  }

  /// Maps the report's [tests] to FHIR observation inputs (value + unit parsed
  /// from each score string, ear + interpretation carried through).
  List<FhirObservationInput> fhirInputs() => <FhirObservationInput>[
        for (final t in tests)
          () {
            final parsed = parseScore(t.score);
            return FhirObservationInput(
              testName: t.name,
              value: parsed.value,
              unit: parsed.unit,
              ear: t.ear,
              // "Recorded" is not an interpretation — omit it rather than
              // export a fabricated one.
              interpretation:
                  t.status == ReportStatus.info ? null : t.status.label,
              note: 'Research measurement on uncalibrated audio — not a '
                  'clinical diagnosis.',
            );
          }(),
      ];

  /// The full FHIR R4 collection bundle as pretty-printed JSON.
  String fhirBundleJson() {
    final bundle = fhirBundle(
      fhirInputs(),
      effective: date,
      patientName: patientName,
    );
    return const JsonEncoder.withIndent('  ').convert(bundle);
  }

  void _exportFhir(BuildContext context) {
    unawaited(Clipboard.setData(ClipboardData(text: fhirBundleJson())));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('FHIR R4 bundle (${tests.length} observations) copied '
            'to clipboard — paste into any FHIR-compliant EHR.'),
      ),
    );
  }

  void _print(BuildContext context) {
    if (printer.canPrintPage) {
      printer.printPage();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use your browser\'s Print (Ctrl+P / ⌘+P) to print '
              'this report.'),
        ),
      );
    }
  }

  /// The report as REAL PDF file bytes (pure-Dart writer, standard fonts).
  Uint8List reportPdfBytes() {
    final blocks = <PdfBlock>[
      const PdfHeading('HearBloom - CAPD Research Report', level: 1),
      const PdfParagraph(
          'Research measurement only - not a clinical diagnosis.',
          gray: true),
      const PdfSpacer(6),
      PdfKeyValue('Patient', patientName),
      PdfKeyValue('Patient ID', patientId),
      PdfKeyValue('Age', _ageStr),
      PdfKeyValue('Date', _dateStr),
      if (demo) ...[
        const PdfSpacer(4),
        const PdfParagraph(
            'DEMONSTRATION DATA - no measured sessions were used.',
            gray: true),
      ],
      const PdfSpacer(6),
      const PdfHeading('Test Results'),
      const PdfTableRow(<String>['Test', 'Score', 'Ear', 'Norm', 'Status'],
          bold: true),
      const PdfDivider(),
      for (final t in tests)
        PdfTableRow(<String>[t.name, t.score, t.ear, t.norm, t.status.label]),
      const PdfSpacer(8),
      const PdfHeading('CAPD Profile - Buffalo Model'),
      PdfParagraph(classifyBuffaloProfile(tests)),
      const PdfSpacer(6),
      const PdfHeading('Recommendations'),
      for (final r in reportRecommendations(tests)) PdfParagraph('* $r'),
      const PdfSpacer(6),
      const PdfHeading('Narrative'),
      PdfParagraph(
          generateNarrativeReport(narrativeInput ?? _demoNarrativeInput)
              .paragraph),
      const PdfSpacer(10),
      const PdfDivider(),
      const PdfParagraph(
          'Disclaimer: research measurement only - not a clinical diagnosis. '
          'Measurements were taken on uncalibrated consumer audio.',
          size: 8.5,
          gray: true),
    ];
    return buildSimplePdf(
      title: 'HearBloom report',
      blocks: blocks,
      tableColumns: const <double>[0.34, 0.18, 0.10, 0.24, 0.14],
    );
  }

  Future<void> _downloadPdf(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final stamp = DateFormat('yyyyMMdd-HHmm').format(date ?? DateTime.now());
    try {
      final path = await pdf_saver.savePdf(
          reportPdfBytes(), 'hearbloom-report-$stamp.pdf');
      messenger.showSnackBar(SnackBar(
        content: Text(path == null
            ? 'Report PDF downloaded.'
            : 'Report PDF saved to $path'),
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save the PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              _actionRow(context),
              const SizedBox(height: 14),
              Container(
                key: const Key('report-paper'),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: _paper,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(),
                    const SizedBox(height: 18),
                    if (demo) ...[
                      _demoBanner(),
                      const SizedBox(height: 14),
                    ],
                    _patientSection(),
                    const SizedBox(height: 22),
                    _sectionTitle('Test Results'),
                    const SizedBox(height: 8),
                    if (!demo && sessionCount > 0) ...[
                      Text(
                        'Latest result per test, from $sessionCount stored '
                        'session${sessionCount == 1 ? '' : 's'} on this '
                        'device.',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _resultsTable(),
                    const SizedBox(height: 22),
                    _sectionTitle('CAPD Profile — Buffalo Model'),
                    const SizedBox(height: 8),
                    _profileSection(),
                    const SizedBox(height: 22),
                    _sectionTitle('Recommendations'),
                    const SizedBox(height: 8),
                    for (final r in reportRecommendations(tests)) _bullet(r),
                    if (demo || confusionMatrix != null) ...[
                      const SizedBox(height: 22),
                      _sectionTitle('Response Confusion Matrix'),
                      const SizedBox(height: 8),
                      _confusionSection(),
                      const SizedBox(height: 22),
                      _sectionTitle('Phoneme Feature Analysis'),
                      const SizedBox(height: 8),
                      _phonemeSection(),
                    ],
                    const SizedBox(height: 22),
                    _sectionTitle('Auto-Generated Narrative'),
                    const SizedBox(height: 8),
                    _narrativeSection(),
                    if (demo || staircase != null) ...[
                      const SizedBox(height: 22),
                      _sectionTitle('Adaptive Staircase Trajectory'),
                      const SizedBox(height: 8),
                      _staircaseSection(),
                    ],
                    if (!demo && _fit != null) ...[
                      const SizedBox(height: 22),
                      _sectionTitle('Psychometric Function Fit'),
                      const SizedBox(height: 8),
                      _fitSection(),
                    ],
                    const SizedBox(height: 18),
                    const Divider(color: _line),
                    const SizedBox(height: 8),
                    _disclaimer(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report'),
        actions: [
          IconButton(
            tooltip: 'Download PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _downloadPdf(context),
          ),
          IconButton(
            tooltip: 'Print report',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => _print(context),
          ),
          IconButton(
            tooltip: 'Copy report text',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => _copy(context),
          ),
          IconButton(
            tooltip: 'Export FHIR',
            icon: const Icon(Icons.medical_information_outlined),
            onPressed: () => _exportFhir(context),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _actionRow(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Semantics(
          button: true,
          label: 'Download PDF report',
          child: FilledButton.icon(
            key: const Key('report-pdf'),
            onPressed: () => _downloadPdf(context),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Download PDF'),
          ),
        ),
        Semantics(
          button: true,
          label: 'Print report',
          child: FilledButton.icon(
            key: const Key('report-print'),
            onPressed: () => _print(context),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print Report'),
          ),
        ),
        Semantics(
          button: true,
          label: 'Copy report text',
          child: OutlinedButton.icon(
            key: const Key('report-copy'),
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Copy Text'),
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          button: true,
          label: 'Export FHIR bundle',
          child: OutlinedButton.icon(
            key: const Key('report-fhir'),
            onPressed: () => _exportFhir(context),
            icon: const Icon(Icons.medical_information_outlined),
            label: const Text('Export FHIR'),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff3b82f6), Color(0xff8b5cf6)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Text(
            'HB',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HearBloom — CAPD Research Report',
                style: TextStyle(
                    color: _ink, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 2),
              Text(
                'Central Auditory Processing summary',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _patientSection() {
    Widget cell(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                    color: _ink, fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          cell('Patient', patientName),
          cell('ID', patientId),
          cell('Age', _ageStr),
          cell('Date', _dateStr),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
            color: _ink, fontSize: 16, fontWeight: FontWeight.w800),
      );

  Widget _resultsTable() {
    const headerStyle =
        TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 12.5);
    return Table(
      border: TableBorder.all(color: _line),
      columnWidths: const {
        0: FlexColumnWidth(2.6),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(1.0),
        3: FlexColumnWidth(1.3),
        4: FlexColumnWidth(1.4),
      },
      children: [
        const TableRow(
          decoration: BoxDecoration(color: Color(0xffe2e8f0)),
          children: [
            Padding(
                padding: EdgeInsets.all(8),
                child: Text('Test', style: headerStyle)),
            Padding(
                padding: EdgeInsets.all(8),
                child: Text('Score', style: headerStyle)),
            Padding(
                padding: EdgeInsets.all(8),
                child: Text('Ear', style: headerStyle)),
            Padding(
                padding: EdgeInsets.all(8),
                child: Text('Norm', style: headerStyle)),
            Padding(
                padding: EdgeInsets.all(8),
                child: Text('Status', style: headerStyle)),
          ],
        ),
        for (final t in tests)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(t.name,
                    style: const TextStyle(color: _ink, fontSize: 12.5)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(t.score,
                    style: const TextStyle(
                        color: _ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(t.ear,
                    style: const TextStyle(color: _muted, fontSize: 12.5)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(t.norm,
                    style: const TextStyle(color: _muted, fontSize: 12.5)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Icon(t.status.icon, size: 15, color: t.status.color),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        t.status.label,
                        style: TextStyle(
                            color: t.status.color,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _profileSection() {
    final affected = affectedProfiles(tests).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(classifyBuffaloProfile(tests),
            style: const TextStyle(color: _ink, height: 1.4, fontSize: 13.5)),
        if (affected.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final p in affected)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.title,
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(p.description,
                        style: const TextStyle(
                            color: _muted, fontSize: 12.5, height: 1.35)),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  ',
                style: TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            Expanded(
              child:
                  Text(text, style: const TextStyle(color: _ink, height: 1.4)),
            ),
          ],
        ),
      );

  /// Real aggregated confusions when available; the labelled demo sample
  /// otherwise (only reachable in demo mode).
  ConfusionMatrix get _reportMatrix =>
      confusionMatrix ?? ConfusionMatrixPage.sample();

  String get _confusionSourceNote => confusionMatrix != null
      ? 'aggregated from $confusionSessionCount recorded '
          'session${confusionSessionCount == 1 ? '' : 's'} on this device'
      : 'demonstration data';

  Widget _confusionSection() {
    final matrix = _reportMatrix;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConfusionMatrixView(
            matrix: matrix,
            palette: ConfusionPalette.light,
          ),
          const SizedBox(height: 8),
          Text(
            'Rows are the presented item; columns are the response. The '
            'diagonal is correct; off-diagonal cells are confusions '
            '($_confusionSourceNote).',
            style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _phonemeSection() {
    final analysis = PhonemeErrorAnalysis.fromMatrix(_reportMatrix);
    Widget row(String label, double pct) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(color: _muted, fontSize: 12.5)),
              Text('${pct.round()}%',
                  style: const TextStyle(
                      color: _ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(analysis.summary(),
              style: const TextStyle(
                  color: _ink,
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          row('Voicing errors',
              analysis.percentFor(PhonemeFeatureError.voicing)),
          row('Place-of-articulation errors',
              analysis.percentFor(PhonemeFeatureError.place)),
          row('Manner-of-articulation errors',
              analysis.percentFor(PhonemeFeatureError.manner)),
          const SizedBox(height: 6),
          Text(
            'Errors are classified by the single distinctive feature that '
            'changed ($_confusionSourceNote).',
            style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  /// The demonstration narrative input (used only in demo mode).
  static const NarrativeInput _demoNarrativeInput = NarrativeInput(
    ageYears: 9,
    ginMs: 8,
    dptRightPct: 55,
    dptLeftPct: 60,
    mldDb: 12,
    sinSnrDb: 2,
    ddtRightPct: 92,
    ddtLeftPct: 78,
    digitSpan: 5,
  );

  Widget _demoBanner() => Container(
        key: const Key('report-demo-banner'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xfffef3c7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xfff59e0b)),
        ),
        child: const Row(
          children: [
            Icon(Icons.science_outlined, size: 18, color: Color(0xff92400e)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Demonstration report with sample data. Complete tests and '
                'your own results will appear here automatically.',
                style: TextStyle(
                    color: Color(0xff92400e), fontSize: 12.5, height: 1.35),
              ),
            ),
          ],
        ),
      );

  Widget _narrativeSection() {
    final report =
        generateNarrativeReport(narrativeInput ?? _demoNarrativeInput);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Text(
          demo ? '${report.paragraph} (Demonstration data.)' : report.paragraph,
          style: const TextStyle(color: _ink, fontSize: 13.5, height: 1.5)),
    );
  }

  Widget _staircaseSection() {
    final run = staircase;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: run != null
          ? StaircasePlot(
              values: run.values,
              reversalIndices: run.reversalIndices,
              threshold: run.threshold,
              title: run.title,
              unit: run.unit,
              textColor: _muted,
            )
          : const StaircasePlot(
              values: <double>[
                12,
                10,
                8,
                6,
                8,
                6,
                4,
                6,
                4,
                2,
                4,
                2,
                3,
                2,
                3,
                2
              ],
              reversalIndices: <int>[4, 6, 9, 11, 12, 13, 14, 15],
              threshold: 2.5,
              title: 'Speech-in-noise SNR staircase (demonstration)',
              unit: 'dB SNR',
              textColor: _muted,
            ),
    );
  }

  /// Logistic psychometric fit of the latest real staircase run, when its
  /// per-trial data and chance level are known.
  LogisticFit? get _fit {
    final run = staircase;
    if (run == null || run.correct == null || run.chanceLevel == null) {
      return null;
    }
    return fitLogistic(run.values, run.correct!, guessRate: run.chanceLevel!);
  }

  Widget _fitSection() {
    final fit = _fit!;
    final run = staircase!;
    final rows = <(String, String)>[
      if (fit.threshold != null)
        (
          'Threshold @ ${(fit.targetProportion * 100).round()}% correct',
          '${fit.threshold!.toStringAsFixed(2)} ${run.unit}'
        ),
      ('Slope (β)', '${fit.beta.toStringAsFixed(2)} per ${run.unit}'),
      ('Guess rate (γ)', '${(fit.gamma * 100).round()}%'),
      ('Trials fitted', '${fit.nTrials}'),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${run.title} — maximum-likelihood logistic fit',
              style: const TextStyle(
                  color: _ink, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: const TextStyle(color: _muted, fontSize: 12.5)),
                  Text(value,
                      style: const TextStyle(
                          color: _ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'P(correct) = γ + (1 − γ − λ)·σ(β(x − α)) fitted to the run\'s '
            'per-trial data; the threshold is read at the staircase\'s target '
            'proportion. Research summary on uncalibrated audio.',
            style: TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _disclaimer() => const Text(
        'Disclaimer: Research measurement only — not a clinical diagnosis. '
        'These demonstration measurements were taken on uncalibrated audio and '
        'must not be used for absolute dB HL judgements or clinical decisions.',
        style: TextStyle(
            color: _muted,
            fontSize: 12,
            fontStyle: FontStyle.italic,
            height: 1.4),
      );
}
