import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Broad category a test contributes to, used to classify the CAPD profile.
enum CapdCategory {
  temporal,
  dichotic,
  binaural,
  speechInNoise,
  degradedSpeech,
  other,
}

/// One row of the report's results table.
class ReportEntry {
  const ReportEntry({
    required this.testName,
    required this.score,
    required this.norm,
    required this.interpretation,
    required this.withinNorm,
    this.category = CapdCategory.other,
  });

  final String testName;
  final String score;
  final String norm;
  final String interpretation;
  final bool withinNorm;
  final CapdCategory category;
}

/// A small default set of results so the report renders standalone (e.g. via
/// `?preview=report`). Real callers pass their own [entries].
const List<ReportEntry> kSampleReportEntries = <ReportEntry>[
  ReportEntry(
    testName: 'Random Gap Detection (combined)',
    score: '7.5 ms',
    norm: '≤ 10 ms',
    interpretation: 'Within typical range',
    withinNorm: true,
    category: CapdCategory.temporal,
  ),
  ReportEntry(
    testName: 'Dichotic Digits — left ear',
    score: '78%',
    norm: '≥ 90%',
    interpretation: 'Below typical range',
    withinNorm: false,
    category: CapdCategory.dichotic,
  ),
  ReportEntry(
    testName: 'Dichotic Digits — right ear',
    score: '92%',
    norm: '≥ 90%',
    interpretation: 'Within typical range',
    withinNorm: true,
    category: CapdCategory.dichotic,
  ),
  ReportEntry(
    testName: 'Competing Sentences (worst ear)',
    score: '82%',
    norm: '≥ 90%',
    interpretation: 'Slightly below typical',
    withinNorm: false,
    category: CapdCategory.dichotic,
  ),
  ReportEntry(
    testName: 'Sentences in noise (SRT-50)',
    score: '+1.2 dB',
    norm: '≈ −2.9 dB',
    interpretation: 'More favourable SNR needed',
    withinNorm: false,
    category: CapdCategory.speechInNoise,
  ),
  ReportEntry(
    testName: 'Filtered speech (worst ear)',
    score: '72%',
    norm: '≥ 70%',
    interpretation: 'Within typical range',
    withinNorm: true,
    category: CapdCategory.degradedSpeech,
  ),
];

/// Classifies a CAPD profile from the pattern of abnormal results.
String classifyCapdProfile(List<ReportEntry> entries) {
  final abnormal = entries.where((e) => !e.withinNorm).toList();
  if (abnormal.isEmpty) {
    return 'No clear central auditory processing weakness across the tested '
        'domains. All measured scores fall within their task-relative typical '
        'ranges.';
  }
  final cats = abnormal.map((e) => e.category).toSet();
  final domains = <String>[];
  if (cats.contains(CapdCategory.temporal)) {
    domains.add('temporal processing (gap detection / patterning)');
  }
  if (cats.contains(CapdCategory.dichotic) ||
      cats.contains(CapdCategory.binaural)) {
    domains.add('binaural integration / dichotic listening');
  }
  if (cats.contains(CapdCategory.speechInNoise)) {
    domains.add('speech recognition in noise');
  }
  if (cats.contains(CapdCategory.degradedSpeech)) {
    domains.add('auditory closure (degraded speech)');
  }
  if (domains.isEmpty) domains.add('one or more auditory domains');
  return 'Pattern suggests relative difficulty in: ${domains.join('; ')}. '
      'This pattern is consistent with a research profile in those domains and '
      'is NOT a clinical diagnosis.';
}

/// Profile-aware, generic (non-clinical) suggestions.
List<String> reportRecommendations(List<ReportEntry> entries) {
  final abnormal = entries.where((e) => !e.withinNorm).toList();
  final cats = abnormal.map((e) => e.category).toSet();
  final recs = <String>[];
  if (cats.contains(CapdCategory.speechInNoise) ||
      cats.contains(CapdCategory.dichotic)) {
    recs.add('Reduce background noise and use clear, front-facing speech; '
        'consider a remote-microphone/FM system in classrooms.');
  }
  if (cats.contains(CapdCategory.temporal) ||
      cats.contains(CapdCategory.degradedSpeech)) {
    recs.add('Structured auditory-training practice for temporal resolution '
        'and degraded-speech closure may be explored.');
  }
  if (cats.contains(CapdCategory.dichotic) ||
      cats.contains(CapdCategory.binaural)) {
    recs.add('Dichotic-listening and binaural-integration training targets '
        'may be considered.');
  }
  recs.add('Refer to a qualified audiologist for a calibrated, validated '
      'clinical CAPD assessment before any diagnosis or intervention.');
  return recs;
}

/// On-screen, print-styled CAPD research report card.
///
/// Renders a light "paper" card (even in the dark app) with a patient header,
/// a results table, a classified CAPD profile, recommendations, and a
/// copy-to-clipboard action. This is NOT a generated PDF file and NOT a
/// diagnosis — it is a formatted research summary.
class PdfReportPage extends StatelessWidget {
  const PdfReportPage({
    super.key,
    this.patientName = '(patient name)',
    this.ageYears,
    this.date,
    this.entries = kSampleReportEntries,
  });

  final String patientName;
  final int? ageYears;
  final DateTime? date;
  final List<ReportEntry> entries;

  static const Color _paper = Color(0xfff8fafc);
  static const Color _ink = Color(0xff0f172a);
  static const Color _muted = Color(0xff475569);
  static const Color _line = Color(0xffcbd5e1);
  static const Color _good = Color(0xff15803d);
  static const Color _bad = Color(0xffb91c1c);

  String get _dateStr => DateFormat.yMMMMd().format(date ?? DateTime.now());

  String _plainText() {
    final b = StringBuffer();
    b.writeln('HearBloom — CAPD Research Report');
    b.writeln('Research use only — not a diagnosis.');
    b.writeln('');
    b.writeln('Patient: $patientName');
    b.writeln('Age: ${ageYears == null ? '(age)' : '$ageYears years'}');
    b.writeln('Date: $_dateStr');
    b.writeln('');
    b.writeln('Results');
    b.writeln('Test | Score | Norm | Interpretation');
    for (final e in entries) {
      b.writeln('${e.testName} | ${e.score} | ${e.norm} | ${e.interpretation}');
    }
    b.writeln('');
    b.writeln('CAPD profile');
    b.writeln(classifyCapdProfile(entries));
    b.writeln('');
    b.writeln('Recommendations');
    for (final r in reportRecommendations(entries)) {
      b.writeln('- $r');
    }
    b.writeln('');
    b.writeln('This report presents demonstration measurements on '
        'uncalibrated audio and is not a clinical or diagnostic document.');
    return b.toString();
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _plainText()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report card'),
        actions: [
          IconButton(
            tooltip: 'Copy to clipboard',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => _copy(context),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
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
                  _patientSection(),
                  const SizedBox(height: 20),
                  _sectionTitle('Results'),
                  const SizedBox(height: 8),
                  _resultsTable(),
                  const SizedBox(height: 20),
                  _sectionTitle('CAPD profile classification'),
                  const SizedBox(height: 6),
                  Text(classifyCapdProfile(entries),
                      style: const TextStyle(color: _ink, height: 1.4)),
                  const SizedBox(height: 20),
                  _sectionTitle('Recommendations'),
                  const SizedBox(height: 6),
                  for (final r in reportRecommendations(entries))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ',
                              style: TextStyle(
                                  color: _ink, fontWeight: FontWeight.w700)),
                          Expanded(
                            child: Text(r,
                                style:
                                    const TextStyle(color: _ink, height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 18),
                  const Divider(color: _line),
                  const SizedBox(height: 8),
                  const Text(
                    'This report presents demonstration measurements on '
                    'uncalibrated audio. It is a research summary only — not a '
                    'clinical or diagnostic document.',
                    style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: FilledButton.icon(
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copy to clipboard'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xff246bce),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Text('HB',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('HearBloom — CAPD Research Report',
                  style: TextStyle(
                      color: _ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('Research use only — not a diagnosis',
                  style: TextStyle(color: _muted, fontSize: 13)),
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
              Text(label.toUpperCase(),
                  style: TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffeef2f7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          cell('Patient', patientName),
          cell('Age', ageYears == null ? '(age)' : '$ageYears years'),
          cell('Date', _dateStr),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(
          color: _ink, fontSize: 16, fontWeight: FontWeight.w800));

  Widget _resultsTable() {
    const headerStyle = TextStyle(
        color: _ink, fontWeight: FontWeight.w800, fontSize: 12.5);
    TableRow headerRow() => const TableRow(
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
                child: Text('Norm', style: headerStyle)),
            Padding(
                padding: EdgeInsets.all(8),
                child: Text('Interpretation', style: headerStyle)),
          ],
        );
    return Table(
      border: TableBorder.all(color: _line),
      columnWidths: const {
        0: FlexColumnWidth(2.6),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(2.2),
      },
      children: [
        headerRow(),
        for (final e in entries)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(e.testName,
                    style: const TextStyle(color: _ink, fontSize: 12.5)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(e.score,
                    style: const TextStyle(
                        color: _ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(e.norm,
                    style: const TextStyle(color: _muted, fontSize: 12.5)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Icon(e.withinNorm ? Icons.check_circle : Icons.error,
                        size: 15, color: e.withinNorm ? _good : _bad),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(e.interpretation,
                          style: TextStyle(
                              color: e.withinNorm ? _good : _bad,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}
