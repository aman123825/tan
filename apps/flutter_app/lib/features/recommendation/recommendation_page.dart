import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../models/recommendation.dart';

/// Shows the explainable, advisory training recommendation for a profile.
///
/// Always presents a human-readable reason and a confidence. A clinician can
/// override it — the AI never changes locked assessment scoring.
class RecommendationPage extends StatefulWidget {
  const RecommendationPage({
    super.key,
    required this.profileId,
    required this.api,
    this.onAccept,
    this.onOverride,
  });

  final String profileId;
  final Api api;
  final void Function(Recommendation recommendation)? onAccept;
  final VoidCallback? onOverride;

  @override
  State<RecommendationPage> createState() => _RecommendationPageState();
}

class _RecommendationPageState extends State<RecommendationPage> {
  late Future<Recommendation> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Recommendation> _load() async => Recommendation.fromJson(
        await widget.api.recommendation(widget.profileId),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suggested next step')),
      body: FutureBuilder<Recommendation>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load a recommendation.\n${snapshot.error}',
              ),
            );
          }
          return _RecommendationView(
            recommendation: snapshot.data!,
            onAccept: widget.onAccept,
            onOverride: widget.onOverride,
          );
        },
      ),
    );
  }
}

class _RecommendationView extends StatelessWidget {
  const _RecommendationView({
    required this.recommendation,
    this.onAccept,
    this.onOverride,
  });

  final Recommendation recommendation;
  final void Function(Recommendation recommendation)? onAccept;
  final VoidCallback? onOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rec = recommendation;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          color: const Color(0xffeaf3ff),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SUGGESTED NEXT',
                  style: TextStyle(
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff246bce),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${rec.moduleId} · ${rec.groupId}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(rec.reason, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                _ConfidenceBar(percent: rec.confidencePercent),
                if (rec.parameters.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final entry in rec.parameters.entries)
                        Chip(label: Text('${entry.key}: ${entry.value}')),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _AdvisoryNotice(),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onAccept == null ? null : () => onAccept!(rec),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Accept & start'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onOverride,
          icon: const Icon(Icons.medical_services_outlined),
          label: const Text('Clinician override — choose manually'),
        ),
      ],
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  const _ConfidenceBar({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confidence: $percent%',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

class _AdvisoryNotice extends StatelessWidget {
  const _AdvisoryNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfffdf0dc),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Color(0xff8a5300)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Advisory only. A clinician can override this suggestion. The AI '
              'recommends training; it never changes locked assessment scoring '
              'and never raises master volume.',
              style: TextStyle(color: Color(0xff8a5300)),
            ),
          ),
        ],
      ),
    );
  }
}
