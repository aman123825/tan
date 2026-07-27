import 'package:flutter/material.dart';

import '../../core/battery.dart';

/// One stage of a composite battery: a label and a builder for its renderer.
/// The renderer must pop its session (all HearBloom renderers do) so the runner
/// can read its `accuracy`.
class BatteryStage {
  const BatteryStage(this.label, this.build);

  final String label;
  final Widget Function(double level) build;
}

/// Runs a list of [stages] in sequence at a fixed comfortable [level], reading
/// each popped session's accuracy, then shows an aggregate. Each sub-test keeps
/// its own deterministic engine, safety rules and persistence; this only
/// orchestrates and summarizes.
class BatteryRunnerPage extends StatefulWidget {
  const BatteryRunnerPage({
    super.key,
    required this.title,
    required this.level,
    required this.stages,
  });

  final String title;
  final double level;
  final List<BatteryStage> stages;

  @override
  State<BatteryRunnerPage> createState() => _BatteryRunnerPageState();
}

class _BatteryRunnerPageState extends State<BatteryRunnerPage> {
  final List<BatteryStageResult> _results = <BatteryStageResult>[];
  int _index = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runNext());
  }

  Future<void> _runNext() async {
    if (_index >= widget.stages.length) {
      setState(() => _done = true);
      return;
    }
    final stage = widget.stages[_index];
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(builder: (_) => stage.build(widget.level)),
    );
    var accuracy = 0.0;
    if (result != null) {
      try {
        final a = (result as dynamic).accuracy;
        if (a is num) accuracy = a.toDouble();
      } catch (_) {
        // Session without an accuracy getter contributes 0.
      }
    }
    if (!mounted) return;
    setState(() {
      _results.add(BatteryStageResult(stage.label, accuracy));
      _index++;
    });
    _runNext();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _done
            ? _buildSummary(theme)
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Running test ${_index + 1} of ${widget.stages.length}…',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final overall = batteryOverall(_results);
    return ListView(
      children: [
        Text('Battery complete',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        for (final r in _results)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(r.label, style: const TextStyle(color: Color(0xff94a3b8))),
                Text('${(r.accuracy * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Overall',
                style: TextStyle(fontWeight: FontWeight.w800)),
            Text('${(overall * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Research measurement only — not a diagnosis. Each sub-test is stored '
          'separately with its own reliability; this is a summary of accuracy.',
          style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xff94a3b8)),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
