import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../comfortable_level/comfortable_level_page.dart';
import '../headphone_check/headphone_check_page.dart';
import '../home/home_page.dart';

/// Persists whether the first-launch introduction has been completed.
class OnboardingStore {
  OnboardingStore({this.key = 'onboarding_complete'});

  final String key;

  Future<bool> isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  Future<void> setComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

class OnboardingStep {
  const OnboardingStep({
    required this.icon,
    required this.headline,
    required this.body,
  });

  final IconData icon;
  final String headline;
  final String body;
}

const List<OnboardingStep> kOnboardingSteps = <OnboardingStep>[
  OnboardingStep(
    icon: Icons.graphic_eq,
    headline: 'Welcome to HearBloom',
    body: 'A research workspace for auditory training and central auditory '
        'processing exercises. HearBloom is not a medical device and does '
        'not provide a diagnosis.',
  ),
  OnboardingStep(
    icon: Icons.route_outlined,
    headline: 'Know the flow before you start',
    body: 'Each session moves from a short introduction to a familiarisation '
        'example, the listening task, and a result report. You can skip the '
        'introduction or stop between steps.',
  ),
  OnboardingStep(
    icon: Icons.headphones_outlined,
    headline: 'Set up reliable listening',
    body: 'Use wired headphones when possible and keep left and right channels '
        'separate. A headphone check and comfortable-level step are available '
        'before testing.',
  ),
  OnboardingStep(
    icon: Icons.tune,
    headline: 'Difficulty adapts, volume does not',
    body: 'Exercises become harder or easier based on your responses. The '
        'master volume stays under your control and is never changed by the '
        'scoring engine.',
  ),
  OnboardingStep(
    icon: Icons.assessment_outlined,
    headline: 'Reports work offline',
    body: 'Every completed test creates an on-device report with a score and '
        'graph. Online sharing is optional, and pending reports remain saved '
        'until you choose to sync them.',
  ),
];

/// First-launch introduction. It can also be reopened from the app shell.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.store, this.onFinished});

  final OnboardingStore? store;

  /// When supplied, completion calls this hook instead of opening another
  /// [HomePage]. This is used by tests and by the in-app Introduction entry.
  final VoidCallback? onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  late final OnboardingStore _store = widget.store ?? OnboardingStore();
  int _index = 0;

  bool get _isLast => _index == kOnboardingSteps.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish(startCheck: true);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_index == 0) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish({required bool startCheck}) async {
    final navigator = Navigator.of(context);
    await _store.setComplete();
    if (!mounted) return;
    if (widget.onFinished != null) {
      widget.onFinished!();
      return;
    }

    navigator.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomePage()),
    );
    if (startCheck) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => HeadphoneCheckPage(
            onCompleted: (_) => navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => ComfortableLevelPage(
                  onLocked: (_) => navigator.popUntil((route) => route.isFirst),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.graphic_eq,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'HearBloom',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Introduction',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        key: const Key('onboarding-skip'),
                        onPressed: () => _finish(startCheck: false),
                        child: const Text('Skip intro'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: kOnboardingSteps.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _StepView(
                      step: kOnboardingSteps[i],
                      index: i,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton.outlined(
                          tooltip: 'Previous introduction step',
                          onPressed: _index == 0 ? null : _back,
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _DotsIndicator(
                          count: kOnboardingSteps.length,
                          index: _index,
                        ),
                      ),
                      const SizedBox(width: 14),
                      FilledButton.icon(
                        key: const Key('onboarding-next'),
                        onPressed: _next,
                        icon: Icon(
                          _isLast
                              ? Icons.headphones_outlined
                              : Icons.arrow_forward,
                        ),
                        label: Text(_isLast ? "Let's begin" : 'Next'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step, required this.index});

  final OnboardingStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final visual = _StepVisual(step: step, index: index);
        final copy = _StepCopy(step: step, index: index);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
            child: wide
                ? Row(
                    children: [
                      Expanded(flex: 11, child: visual),
                      const SizedBox(width: 40),
                      Expanded(flex: 10, child: copy),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: 270, child: visual),
                      const SizedBox(height: 28),
                      copy,
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _StepCopy extends StatelessWidget {
  const _StepCopy({required this.step, required this.index});

  final OnboardingStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STEP ${index + 1} OF ${kOnboardingSteps.length}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          step.headline,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          step.body,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              index == 4
                  ? Icons.check_circle_outline
                  : Icons.touch_app_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                index == 4
                    ? 'Start the listening check, or skip it and explore the '
                        'app directly.'
                    : 'Swipe, use Next, or skip the introduction at any time.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepVisual extends StatelessWidget {
  const _StepVisual({required this.step, required this.index});

  final OnboardingStep step;
  final int index;

  static const _colors = <Color>[
    Color(0xff1f8a70),
    Color(0xff3d7ea6),
    Color(0xffdc6b4f),
    Color(0xff7a6f9b),
    Color(0xff2f9e75),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[index % _colors.length];
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 260, maxHeight: 430),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _WaveFieldPainter(
                lineColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              child: Icon(step.icon, size: 56, color: Colors.white),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Row(
              children: [
                const Icon(Icons.hearing, size: 17, color: Colors.white),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _visualCaption(index),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _visualCaption(int stepIndex) => switch (stepIndex) {
        0 => 'Listening science, made usable',
        1 => 'Introduction, example, task, report',
        2 => 'Reliable left and right channel setup',
        3 => 'Adaptive challenge with stable volume',
        _ => 'Offline report first, optional sync later',
      };
}

class _DotsIndicator extends StatelessWidget {
  const _DotsIndicator({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 28 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

class _WaveFieldPainter extends CustomPainter {
  const _WaveFieldPainter({required this.lineColor});

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (var row = 0; row < 6; row++) {
      final path = Path();
      final center = size.height * (0.2 + row * 0.12);
      for (var x = 0.0; x <= size.width; x += 3) {
        final y = center +
            math.sin(x / size.width * math.pi * 4 + row * 0.7) * (9 + row * 2);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveFieldPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor;
}
