import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearbloom/core/difficulty.dart';
import 'package:hearbloom/features/common/difficulty_selector.dart';

void main() {
  group('DifficultyConfig presets', () {
    test('starting SNR decreases (easier → harder): 15 / 10 / 5 / 0 dB', () {
      expect(DifficultyLevel.easy.config.startSnrDb, 15);
      expect(DifficultyLevel.medium.config.startSnrDb, 10);
      expect(DifficultyLevel.hard.config.startSnrDb, 5);
      expect(DifficultyLevel.expert.config.startSnrDb, 0);
    });

    test('starting gap decreases: 20 / 10 / 6 / 4 ms', () {
      expect(DifficultyLevel.easy.config.startGapMs, 20);
      expect(DifficultyLevel.medium.config.startGapMs, 10);
      expect(DifficultyLevel.hard.config.startGapMs, 6);
      expect(DifficultyLevel.expert.config.startGapMs, 4);
    });

    test('pattern trials per ear decrease: 30 / 25 / 20 / 15', () {
      expect(DifficultyLevel.easy.config.trialsPerEar, 30);
      expect(DifficultyLevel.medium.config.trialsPerEar, 25);
      expect(DifficultyLevel.hard.config.trialsPerEar, 20);
      expect(DifficultyLevel.expert.config.trialsPerEar, 15);
    });

    test('vocoder starting channels decrease: 32 / 16 / 8 / 4', () {
      expect(DifficultyLevel.easy.config.startingChannels, 32);
      expect(DifficultyLevel.medium.config.startingChannels, 16);
      expect(DifficultyLevel.hard.config.startingChannels, 8);
      expect(DifficultyLevel.expert.config.startingChannels, 4);
    });

    test('training speed multiplier increases: 1.0 / 1.3 / 1.5 / 1.8', () {
      expect(DifficultyLevel.easy.config.speedMultiplier, 1.0);
      expect(DifficultyLevel.medium.config.speedMultiplier, 1.3);
      expect(DifficultyLevel.hard.config.speedMultiplier, 1.5);
      expect(DifficultyLevel.expert.config.speedMultiplier, 1.8);
    });

    test('every level exposes a label and descriptions', () {
      for (final level in DifficultyLevel.values) {
        expect(level.label, isNotEmpty);
        expect(level.shortDescription, isNotEmpty);
        expect(level.longDescription, isNotEmpty);
      }
      expect(DifficultyLevel.medium.shortDescription, 'Standard clinical');
    });
  });

  group('Difficulty storage', () {
    test('fromStorage round-trips names and falls back to medium', () {
      for (final level in DifficultyLevel.values) {
        expect(DifficultyLevelInfo.fromStorage(level.storageKey), level);
      }
      expect(DifficultyLevelInfo.fromStorage(null), DifficultyLevel.medium);
      expect(DifficultyLevelInfo.fromStorage('nonsense'),
          DifficultyLevel.medium);
    });

    test('DifficultyStore persists and reloads the last choice', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = DifficultyStore();
      expect(await store.load(), DifficultyLevel.medium);
      await store.save(DifficultyLevel.hard);
      expect(await store.load(), DifficultyLevel.hard);
    });
  });

  group('DifficultySelector widget', () {
    testWidgets('shows four cards and Start returns the selected level',
        (tester) async {
      DifficultyLevel? started;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DifficultySelector(
              persistSelection: false,
              initial: DifficultyLevel.medium,
              onStart: (level) => started = level,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // All four levels are offered.
      for (final level in DifficultyLevel.values) {
        expect(find.byKey(Key('difficulty-card-${level.name}')), findsOneWidget);
      }

      // Choose "Hard", then Start → the callback receives Hard.
      await tester.tap(find.byKey(const Key('difficulty-card-hard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('difficulty-start')));
      await tester.pumpAndSettle();
      expect(started, DifficultyLevel.hard);
    });
  });
}
