import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../data/session_history.dart';
import 'enhanced_report_page.dart';
import 'report_data.dart';

/// The Report tab: renders [EnhancedReportPage] from REAL on-device session
/// history (latest result per test), falling back to the labelled
/// demonstration report when nothing has been measured yet. Reloads whenever
/// the history or the listener-age setting changes.
class ReportTabPage extends StatefulWidget {
  const ReportTabPage({super.key});

  @override
  State<ReportTabPage> createState() => _ReportTabPageState();
}

class _ReportTabPageState extends State<ReportTabPage> {
  late Future<List<SessionRecord>> _future = SessionHistory().load();

  void _reload() {
    if (mounted) setState(() => _future = SessionHistory().load());
  }

  @override
  void initState() {
    super.initState();
    sessionHistoryRevision.addListener(_reload);
    appSettings.addListener(_reload);
  }

  @override
  void dispose() {
    sessionHistoryRevision.removeListener(_reload);
    appSettings.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SessionRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final age = appSettings.value.listenerAgeYears;
        final data =
            buildReportData(snapshot.data ?? const [], ageYears: age);
        if (data == null || data.tests.isEmpty) {
          // Nothing measured yet: the clearly-bannered demonstration report.
          return const EnhancedReportPage();
        }
        return EnhancedReportPage(
          demo: false,
          tests: data.tests,
          ageYears: age,
          narrativeInput: data.narrative,
          staircase: data.staircase,
          sessionCount: data.sessionCount,
          confusionMatrix: data.confusionMatrix,
          confusionSessionCount: data.confusionSessionCount,
          patientName: kDefaultPatient,
          patientId: 'on-device',
        );
      },
    );
  }
}
