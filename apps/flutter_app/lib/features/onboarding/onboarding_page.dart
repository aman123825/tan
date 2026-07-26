import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../comfortable_level/comfortable_level_page.dart';
import '../headphone_check/headphone_check_page.dart';
import '../home/home_page.dart';

// Dark glassmorphic palette.
const Color _bg = Color(0xff0f172a);
const Color _ink = Color(0xffe2e8f0);
const Color _muted = Color(0xff94a3b8);
const Color _border = Color(0x33ffffff);
const Color _primary = Color(0xff3b82f6);

/// Persists whether the first-launch onboarding tour has been completed.
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

/// A single onboarding step's content.
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
    body:
        'A research lab for auditory training and central-auditory-processing '
        'exercises. This is research software — not a medical device, and not '
        'for diagnosis or treatment.',
  ),
  OnboardingStep(
    icon: Icons.route,
    headline: 'How it works',
    body:
        'A simple flow guides every session:\n\n'
        'Screen  →  Calibrate  →  Test  →  Train  →  Report\n\n'
        'You can stop between steps — your progress is kept on this device.',
  ),
  OnboardingStep(
    icon: Icons.hearing,
    headline: 'Your ears are unique',
    body:
        'Many tasks measure each ear separately, so left and right results '
        'stay distinct. Please use wired headphones so the two ears never '
        'blend — several exercises depend on it.',
  ),
  OnboardingStep(
    icon: Icons.tune,
    headline: 'Adaptive difficulty',
    body:
        'Exercises get harder when you do well and easier when you struggle, '
        'so you always train near your edge. Only the task difficulty adapts — '
        'the master volume stays locked and never changes.',
  ),
  OnboardingStep(
    icon: Icons.rocket_launch,
    headline: 'Let’s begin',
    body:
        'First we’ll check your headphones, then set a comfortable listening '
        'level. After that the full lab is yours to explore.',
  ),
];

/// Five-step first-launch onboarding carousel. On completion it records the
/// `onboarding_complete` flag; the final CTA starts the headphone check →
/// comfortable-level flow. When [onFinished] is supplied it is invoked instead
/// of navigating (used by tests).
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.store, this.onFinished});

  final OnboardingStore? store;

  /// Optional hook called after the flag is set (tests). When null, the page
  /// navigates to the home screen itself.
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
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finish({required bool startCheck}) async {
    final navigator = Navigator.of(context);
    await _store.setComplete();
    if (!mounted) return;
    if (widget.onFinished != null) {
      widget.onFinished!();
      return;
    }
    // Replace the onboarding route with the home screen.
    navigator.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomePage()),
    );
    if (startCheck) {
      // Headphone check → comfortable-level, layered on top of home.
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => HeadphoneCheckPage(
            onCompleted: (_) => navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => ComfortableLevelPage(
                  onLocked: (_) =>
                      navigator.popUntil((route) => route.isFirst),
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
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  key: const Key('onboarding-skip'),
                  onPressed: () => _finish(startCheck: false),
                  child: const Text('Skip', style: TextStyle(color: _muted)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: kOnboardingSteps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _StepView(step: kOnboardingSteps[i]),
              ),
            ),
            _DotsIndicator(count: kOnboardingSteps.length, index: _index),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('onboarding-next'),
                  onPressed: _next,
                  child: Text(_isLast ? 'Let’s begin' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x333b82f6), Color(0x228b5cf6)],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: _border),
            ),
            child: Icon(step.icon, size: 56, color: _primary),
          ),
          const SizedBox(height: 36),
          Text(
            step.headline,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            step.body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _muted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  const _DotsIndicator({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? _primary : const Color(0x33ffffff),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
