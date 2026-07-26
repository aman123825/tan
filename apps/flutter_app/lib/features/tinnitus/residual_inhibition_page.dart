import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_port.dart';
import '../../core/audio/pcm_synth.dart';
import '../../core/tinnitus/residual_inhibition.dart';
import '../../core/tinnitus/tinnitus_store.dart';
import '../catalog/validation_badge.dart';

/// Residual inhibition (D4): one minute of masking noise at MML + 10 dB
/// (safety-capped), then an immediate suppression report and a "tap when it
/// is back to normal" timer. Requires a stored MML from the MML page first.
class ResidualInhibitionPage extends StatefulWidget {
  const ResidualInhibitionPage({
    super.key,
    this.maskerSeconds = 60,
    this.audioPort,
    this.store,
    this.onCompleted,
  });

  final int maskerSeconds;
  final AudioPort? audioPort;
  final TinnitusStore? store;
  final void Function(ResidualInhibitionSession session)? onCompleted;

  @override
  State<ResidualInhibitionPage> createState() =>
      _ResidualInhibitionPageState();
}

enum _Phase { loading, needMml, ready, masking, report, timing, done }

class _ResidualInhibitionPageState extends State<ResidualInhibitionPage> {
  static const Color _ink = Color(0xffe2e8f0);
  static const Color _muted = Color(0xff94a3b8);
  static const Color _glass = Color(0x1affffff);
  static const Color _border = Color(0x33ffffff);

  late final AudioPort _audio = widget.audioPort ?? SilentAudioPort();
  ResidualInhibitionSession? _session;
  _Phase _phase = _Phase.loading;
  int _maskerRemaining = 0;
  Timer? _tick;
  final Stopwatch _returnClock = Stopwatch();

  @override
  void initState() {
    super.initState();
    (widget.store ?? TinnitusStore()).load().then((profile) {
      if (!mounted) return;
      setState(() {
        if (profile.mmlDb == null) {
          _phase = _Phase.needMml;
        } else {
          _session = ResidualInhibitionSession(
              mmlDb: profile.mmlDb!, maskerSeconds: widget.maskerSeconds);
          _phase = _Phase.ready;
        }
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _startMasker() async {
    final s = _session!;
    setState(() {
      _phase = _Phase.masking;
      _maskerRemaining = s.maskerSeconds;
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _maskerRemaining--);
      if (_maskerRemaining <= 0) {
        t.cancel();
        setState(() => _phase = _Phase.report);
      }
    });
    // One long buffer; playback failures never block the flow.
    try {
      await _audio.playWav(encodeWav16(whiteNoise(
        seconds: s.maskerSeconds.toDouble(),
        amp: s.maskerAmplitude,
        seed: 42,
      )));
    } catch (_) {}
  }

  void _reportDepth(RiDepth depth) {
    _session!.recordDepth(depth);
    if (depth == RiDepth.none) {
      _finish();
    } else {
      _returnClock
        ..reset()
        ..start();
      setState(() => _phase = _Phase.timing);
    }
  }

  void _tinnitusBack() {
    _returnClock.stop();
    _session!.recordReturnSeconds(_returnClock.elapsedMilliseconds / 1000);
    _finish();
  }

  void _finish() {
    _tick?.cancel();
    setState(() => _phase = _Phase.done);
    widget.onCompleted?.call(_session!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Residual inhibition'),
        actions: const [
          Padding(
            padding: EdgeInsets.all(12),
            child: ValidationBadge(validationStatus: 'unvalidated'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _body(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.needMml:
        return _card(
          icon: Icons.info_outline,
          title: 'Measure your masking level first',
          body: 'Residual inhibition uses your minimum masking level '
              '(MML) to set a safe masker. Run "Minimum masking level" on '
              'the Tinnitus tab, then come back.',
          actions: [
            FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('OK')),
          ],
        );
      case _Phase.ready:
        return _card(
          icon: Icons.blur_on,
          title: 'One minute of masking noise',
          body: 'A steady noise will play for ${widget.maskerSeconds} '
              'seconds at your masking level + 10 dB (safety-capped). '
              'Listen through it; when it stops, notice what your tinnitus '
              'does. Many people hear it briefly quieter — some don\'t, '
              'and both are normal.',
          actions: [
            FilledButton.icon(
                key: const Key('ri-start'),
                onPressed: _startMasker,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start the masker')),
          ],
        );
      case _Phase.masking:
        return _card(
          icon: Icons.graphic_eq,
          title: 'Masker playing…',
          body: '$_maskerRemaining s remaining. Just listen — nothing to '
              'do yet.',
          actions: const [],
        );
      case _Phase.report:
        return _card(
          icon: Icons.hearing,
          title: 'The masker just stopped — how is your tinnitus RIGHT '
              'now?',
          body: 'Answer immediately; the effect fades within seconds to '
              'a minute.',
          actions: [
            for (final d in RiDepth.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton(
                  key: Key('ri-depth-${d.name}'),
                  onPressed: () => _reportDepth(d),
                  child: Text(d.label),
                ),
              ),
          ],
        );
      case _Phase.timing:
        return _card(
          icon: Icons.timer_outlined,
          title: 'Tap the button the moment your tinnitus is back to '
              'normal',
          body: 'Timing since the masker stopped…',
          actions: [
            FilledButton.icon(
                key: const Key('ri-back'),
                onPressed: _tinnitusBack,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('It\'s back to normal')),
          ],
        );
      case _Phase.done:
        final s = _session!;
        return _card(
          icon: s.positive ? Icons.check_circle_outline : Icons.circle_outlined,
          title: 'Observation recorded',
          body: '${s.summary()}\n\nResidual inhibition is a research '
              'observation about your tinnitus mechanism — it is not a '
              'treatment, and its absence means nothing bad.',
          actions: [
            FilledButton(
                onPressed: () => Navigator.of(context).maybePop(s),
                child: const Text('Done')),
          ],
        );
    }
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String body,
    required List<Widget> actions,
  }) {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, size: 40, color: const Color(0xff3b82f6)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _muted, fontSize: 14, height: 1.45)),
            const SizedBox(height: 18),
            ...actions,
          ],
        ),
      ),
    );
  }
}
