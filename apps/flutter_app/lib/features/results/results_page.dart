import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../models/results.dart';

/// Displays a profile's results, separated per (condition, output device,
/// module, group, mode) with per-bucket reliability. Results are never pooled
/// across condition or output device — that guarantee is surfaced to the user.
class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key, required this.profileId, required this.api});

  final String profileId;
  final Api api;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  late Future<ResultsSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ResultsSummary> _load() async =>
      ResultsSummary.fromJson(await widget.api.results(widget.profileId));

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _showCsvExport() async {
    String csv;
    try {
      csv = await widget.api.exportCsv(widget.profileId);
    } catch (e) {
      csv = 'Export failed: $e';
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('CSV export (research data)'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SelectableText(
              csv,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _showCsvExport,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<ResultsSummary>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load results.\n${snapshot.error}'),
            );
          }
          return _ResultsView(summary: snapshot.data!);
        },
      ),
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.summary});

  final ResultsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (summary.totalTrials == 0) {
      return const Center(child: Text('No trials recorded yet.'));
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Overall',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      summary.accuracy == null
                          ? '—'
                          : '${(summary.accuracy! * 100).round()}%',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Overall accuracy',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${summary.totalTrials} trials across '
                            '${summary.separated.length} '
                            '${summary.separated.length == 1 ? 'condition' : 'conditions'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xff94a3b8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: summary.accuracy ?? 0,
                    minHeight: 10,
                    backgroundColor: const Color(0x33ffffff),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (summary.notPooled) const _PoolingNotice(),
        const SizedBox(height: 18),
        Text(
          'By condition & device',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Each row is a separate listening condition. Temporal and speech '
          'results are not comparable across different devices.',
          style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8)),
        ),
        const SizedBox(height: 12),
        if (summary.separated.length >= 2)
          _AccuracyChart(buckets: summary.separated),
        for (final bucket in summary.separated) _BucketCard(bucket: bucket),
        const SizedBox(height: 18),
        const _NormsReferenceCard(),
        const SizedBox(height: 16),
        Text(
          'Research measurement only — not a diagnosis and not a dB HL '
          'threshold.',
          style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8)),
        ),
      ],
    );
  }
}

class _NormsReferenceCard extends StatelessWidget {
  const _NormsReferenceCard();

  static const List<(String, String, String)> _refs = [
    ('Gaps-in-noise', '≤ 6 ms', 'Musiek et al., 2005'),
    ('Frequency difference limen', '~1% at 1 kHz',
        'Wier, Jesteadt & Green, 1977'),
    ('AM detection (TMTF)', '−20 to −26 dB', 'Viemeister, 1979'),
    ('Speech-in-noise (QuickSIN)', 'SNR loss < 3 dB', 'Killion et al., 2004'),
    ('Dichotic digits', '≥ 90% per ear', 'Musiek, 1983'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Research reference points (illustrative)',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Published normal ranges for the underlying measures. Your '
              'measured thresholds are interpreted against these on each '
              'task’s own results.',
              style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8)),
            ),
            const SizedBox(height: 12),
            for (final (name, band, cite) in _refs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(band,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary)),
                    ),
                    Expanded(
                      flex: 5,
                      child: Text(cite,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 11, color: const Color(0xff94a3b8))),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Illustrative on uncalibrated audio with demonstration stimuli '
              '— not a diagnosis.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black45, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

class _PoolingNotice extends StatelessWidget {
  const _PoolingNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xffeaf3ff),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Color(0xff246bce), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Results are kept separate per ear-condition and output device '
              '(wired / Bluetooth / speaker) and are never pooled.',
              style: TextStyle(color: Color(0xff20406b)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar chart of accuracy (%) per separated condition/device bucket.
class _AccuracyChart extends StatelessWidget {
  const _AccuracyChart({required this.buckets});

  final List<ConditionResult> buckets;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Accuracy by condition (%)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: 100,
                  minY: 0,
                  barGroups: [
                    for (var i = 0; i < buckets.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: (buckets[i].accuracy ?? 0) * 100,
                            color: primary,
                            width: 18,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ],
                      ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: true, reservedSize: 30),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${value.toInt() + 1}',
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: true),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < buckets.length; i++)
              Text(
                '${i + 1}: ${buckets[i].condition ?? '?'} · '
                '${buckets[i].outputDevice ?? '?'} · ${buckets[i].mode}',
                style: const TextStyle(fontSize: 11, color: const Color(0xff94a3b8)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BucketCard extends StatelessWidget {
  const _BucketCard({required this.bucket});

  final ConditionResult bucket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(label: Text(bucket.condition ?? 'unknown')),
                Chip(label: Text(bucket.outputDevice ?? 'unknown')),
                Chip(label: Text(bucket.mode)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${bucket.moduleId} · ${bucket.groupId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Metric(label: 'Trials', value: '${bucket.n}'),
                const SizedBox(width: 24),
                _Metric(
                  label: 'Accuracy',
                  value: bucket.accuracy == null
                      ? '—'
                      : '${(bucket.accuracy! * 100).round()}%',
                ),
                const Spacer(),
                _ReliabilityChip(reliability: bucket.reliability),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReliabilityChip extends StatelessWidget {
  const _ReliabilityChip({required this.reliability});

  final Reliability reliability;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, String label) = reliability.reliable
        ? (const Color(0xff22c55e), const Color(0x3322c55e), 'RELIABLE')
        : reliability.reason == 'insufficient_trials'
            ? (const Color(0xff5f6368), const Color(0xffeceff1), 'MORE TRIALS')
            : (const Color(0xff8a5300), const Color(0xfffdf0dc), 'CHECK');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: const TextStyle(color: const Color(0xff94a3b8), fontSize: 12),
        ),
      ],
    );
  }
}
