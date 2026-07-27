import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/audio/pcm_synth.dart';
import '../../core/audio/task_stimuli.dart';
import '../../core/audio/timbre.dart';
import '../../core/closed_set.dart';
import '../../core/content_pools.dart';
import '../../core/difficulty.dart';
import '../../core/interval_task.dart';
import '../../core/gap_detection.dart' show buildGapSequence;
import '../../core/modulation_detection.dart' show buildModulationSequence;
import '../../core/modulation_rate.dart' show buildRateOddballSequence;
import '../../core/pitch_discrimination.dart' show buildOddballSequence;
import '../../core/open_set.dart';
import '../../core/protocol_engine.dart';
import '../../core/trial_event.dart';
import '../../core/trial_queue.dart';
import '../../data/api.dart';
import '../../data/aes_gcm_cipher.dart';
import '../../data/catalog_repository.dart';
import '../../data/just_audio_player.dart';
import '../../data/local_key_store.dart';
import '../../data/prefs_trial_queue_store.dart';
import '../../data/session_history.dart';
import '../../models/catalog.dart';
import '../battery/battery_page.dart';
import '../battery/capd_battery_presets.dart';
import '../binaural_fusion/binaural_fusion_page.dart';
import '../catalog/module_detail_sheet.dart';
import '../competing_sentences/competing_sentences_page.dart';
import '../compressed_speech/compressed_speech_page.dart';
import '../filtered_speech/filtered_speech_page.dart';
import '../hint_sin/hint_sin_page.dart';
import '../../core/music_perception.dart'
    show buildRhythmChangeSequence, rhythmChangeTrack;
import '../../core/psychoacoustics.dart'
    show buildIrnSequence, buildRippleOddballSequence, irnTrack, rippleTrack;
import '../audiogram/audiogram_page.dart';
import '../binaural_jnd/binaural_jnd_page.dart';
import '../../data/consent_store.dart';
import '../../data/favorites_store.dart';
import '../../data/reminder_store.dart';
import '../../data/usage_stats.dart';
import '../compare/session_compare_page.dart';
import '../consent/consent_page.dart';
import '../figure_ground/figure_ground_page.dart';
import '../gamification/personal_bests_page.dart';
import '../history/session_history_sheet.dart';
import '../../core/pattern_test.dart' show PatternResponseMode;
import '../pattern_test/pattern_test_page.dart';
import '../psychoacoustics/beat_tap_page.dart';
import '../psychoacoustics/music_in_noise_page.dart';
import '../psychoacoustics/tmtf_page.dart';
import '../mld/mld_test_page.dart';
import '../dashboard/clinician_dashboard_page.dart';
import '../report/report_tab.dart';
import '../report/session_result_sheet.dart';
import '../settings/settings_page.dart';
import '../validation/validation_protocol_page.dart';
import '../rgdt/rgdt_page.dart';
import '../trends/trend_page.dart';
import '../chord/chord_identification_page.dart';
import '../closed_set/closed_set_page.dart';
import '../comfortable_level/comfortable_level_page.dart';
import '../dichotic/dichotic_page.dart';
import '../dsi/dsi_page.dart';
import '../lisns/lisns_page.dart';
import '../ssw/ssw_page.dart';
import '../questionnaires/aphab_page.dart';
import '../questionnaires/fisher_page.dart';
import '../questionnaires/hhie_page.dart';
import '../questionnaires/questionnaires_hub.dart';
import '../questionnaires/ssq12_page.dart';
import '../questionnaires/tfi_page.dart';
import '../questionnaires/thi_page.dart';
import '../fatigue/fatigue_sheet.dart';
import '../gap_detection/gap_detection_page.dart';
import '../identification/identification_page.dart';
import '../interval_task/interval_task_page.dart';
import '../common/norm_tile.dart';
import '../common/difficulty_selector.dart';
import '../mci/mci_page.dart';
import '../modulation_detection/modulation_detection_page.dart';
import '../note_sequence/note_sequence_page.dart';
import '../onboarding/onboarding_page.dart';
import '../open_set/open_set_page.dart';
import '../pitch_discrimination/pitch_discrimination_page.dart';
import '../protocol/protocol_intro_screen.dart';
import '../recommendation/recommendation_page.dart';
import '../results/results_page.dart';
import '../review/clinician_review_page.dart';
import '../sequence_entry/sequence_entry_page.dart';
import '../speech_in_noise/speech_in_noise_page.dart';
import '../../core/session_summary.dart';
import '../../data/gamification_store.dart';
import '../gamification/gamification_overlay.dart';
import '../training/competing_speakers_page.dart';
import '../training/compressed_training_page.dart';
import '../training/phonemic_contrast_page.dart';
import '../training/closure_training_page.dart';
import '../training/continuum_page.dart';
import '../training/working_memory_page.dart';
import '../training/following_directions_page.dart';
import '../training/vocoder_page.dart';
import '../training/spatial_page.dart';
import '../training/dichotic_integration_page.dart';
import '../training/vowel_training_page.dart';
import '../training/consonant_training_page.dart';
import '../training/prosody_page.dart';
import '../training/reverb_page.dart';
import '../training/pitch_ranking_page.dart';
import '../training/timbre_page.dart';
import '../training/music_emotion_page.dart';
import '../training/phonological_page.dart';
import '../training/scene_page.dart';
import '../training/interhemispheric_page.dart';
import '../training/speech_tracking_page.dart';
import '../training/sentence_closure_page.dart';
import '../tinnitus/pitch_match_page.dart';
import '../tinnitus/loudness_match_page.dart';
import '../tinnitus/mml_page.dart';
import '../tinnitus/desensitization_page.dart';
import '../tinnitus/residual_inhibition_page.dart';
import '../tinnitus/sound_therapy_page.dart';
import '../tinnitus/trt_education_page.dart';
import '../tinnitus/ldl_page.dart';
import '../../core/word_lists.dart';
import '../kids/guardian_view_page.dart';
import '../kids/kids_abc_page.dart';
import '../kids/kids_mode.dart';
import '../kids/story_path_page.dart';
import '../../core/settings/app_settings.dart';
import '../report/confusion_matrix_page.dart';
import '../planner/planner_page.dart';
import '../../core/session_planner.dart';

/// Presentation-only metadata (glyph + tagline) per module id.
///
/// This is display sugar; the module *structure* is the catalog's job. Keeping
/// it separate means the catalog stays the single source of protocol truth.
class _ModulePresentation {
  const _ModulePresentation(this.glyph, this.tagline);
  final String glyph;
  final String tagline;
}

const Map<String, _ModulePresentation> _presentation = {
  'foundation': _ModulePresentation(
    '◉',
    'Tones, speech and environmental foundations',
  ),
  'telephone': _ModulePresentation('☎', 'Telephone-bandwidth communication'),
  'noise': _ModulePresentation('≋', 'SNR, babble and competing talkers'),
  'melodic': _ModulePresentation('⌁', 'Nine five-note contour patterns'),
  'openset': _ModulePresentation('Aa', 'Typed words, sentences and sequences'),
  'music': _ModulePresentation('♫', 'Pitch, rhythm, chords and instruments'),
  'auditory': _ModulePresentation('◒', 'Temporal and spectral processing'),
  'assessment': _ModulePresentation('✓', 'Locked research baselines'),
  'learning': _ModulePresentation('⌂', 'Vocabulary and auditory scenes'),
};

const _ModulePresentation _fallbackPresentation = _ModulePresentation(
  '◈',
  'Protocol module',
);

/// Display descriptor for an adaptive-training exercise on the home grid. The
/// order here is the index contract used by `_launchTraining`.
class _TrainingModule {
  const _TrainingModule(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

const List<_TrainingModule> _kTrainingModules = <_TrainingModule>[
  _TrainingModule(
      'Competing Speakers', 'Follow the louder talker', Icons.people),
  _TrainingModule('Speed Training', 'Keep up with faster speech', Icons.speed),
  _TrainingModule(
      'Phonemic Contrast', 'Tell close sounds apart', Icons.spellcheck),
  _TrainingModule('Auditory Closure', 'Fill in the masked gaps', Icons.blur_on),
  _TrainingModule(
      'Sound Continuum', 'Climb progressive levels', Icons.trending_up),
  _TrainingModule('Working Memory', 'Digit span and n-back', Icons.psychology),
  _TrainingModule(
      'Following Directions', 'Act on ordered steps', Icons.directions),
  _TrainingModule(
      'Vocoded Speech', 'Understand cochlear-implant sound', Icons.graphic_eq),
  _TrainingModule('Sound Localization', 'Find where sounds come from',
      Icons.spatial_audio_off),
  _TrainingModule('Vowel Training', 'Tell the 12 vowels apart · 5 levels',
      Icons.record_voice_over),
  _TrainingModule('Consonant Training',
      'Sharpen consonant contrasts · 4 levels', Icons.graphic_eq),
  _TrainingModule('Dichotic Integration',
      'Train the weak ear · fading level gap', Icons.hearing),
  _TrainingModule('Prosody Training',
      'Question, stress and emotion · 20 trials', Icons.record_voice_over),
  _TrainingModule(
      'Reverb Training', 'Hear words in a room · adaptive RT60', Icons.blur_on),
  _TrainingModule(
      'Pitch Ranking', 'Order tones low to high · 15 trials', Icons.sort),
  _TrainingModule(
      'Timbre Training', 'Tell waveforms apart · 4AFC', Icons.graphic_eq),
  _TrainingModule(
      'Emotion in Music', 'Happy, sad, tense or calm · 4AFC', Icons.music_note),
  _TrainingModule('Phonological Games',
      'Rhyme, blend & delete sounds · 3 games', Icons.child_care),
  _TrainingModule('Real-World Scenes',
      'Restaurant, classroom & phone · adaptive', Icons.restaurant),
  _TrainingModule(
      'Interhemispheric', 'Hear one ear, tap the other hand', Icons.swap_horiz),
  _TrainingModule(
      'Speech Tracking', 'Type words as you hear them · WPM', Icons.keyboard),
  _TrainingModule(
      'Sentence Closure', 'Fill the gap from context · 4AFC', Icons.short_text),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.repository});

  final CatalogRepository? repository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final CatalogRepository _repository =
      widget.repository ?? CatalogRepository();
  late Future<Catalog> _catalogFuture;

  /// Durable offline queue + API client used to sync completed trials. The
  /// queue is encrypted at rest (AES-GCM) with a locally-stored key.
  final Api _api = Api();
  late final Future<TrialQueue> _queueFuture = _buildQueue();

  Future<TrialQueue> _buildQueue() async {
    final key = await LocalKeyStore().loadOrCreateKey();
    return TrialQueue(
      EncryptingTrialQueueStore(
        PrefsTrialQueueStore(),
        AesGcmQueueCipher(key),
      ),
    );
  }

  /// Profile id from the most recent successfully-created server session, used
  /// to open the results screen.
  String? _lastProfileId;

  /// Selected bottom-navigation tab: 0 Home, 1 Tests, 2 Training, 3 Tinnitus,
  /// 4 Report, 5 Settings.
  int _tabIndex = 0;

  /// The starting difficulty last chosen by the listener. Persisted via
  /// [DifficultyStore] and remembered between sessions; the selector is shown
  /// before each test/training launch and updates this.
  DifficultyLevel _difficulty = DifficultyLevel.medium;
  final DifficultyStore _difficultyStore = DifficultyStore();

  @override
  void initState() {
    super.initState();
    _catalogFuture = _repository.load();
    _difficultyStore.load().then((level) {
      if (mounted) setState(() => _difficulty = level);
    });
    // Populate the shared favourites set (fire-and-forget).
    FavoritesStore().load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenPreview());
    // Research consent (J8): ask once per consent-text version.
    ConsentStore().load().then((decision) {
      if (decision == null && mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const ConsentPage()));
      }
    });
  }

  /// Shows the difficulty selector (remembering the last choice) and returns
  /// the chosen level, or null if dismissed. Updates [_difficulty] on success.
  Future<DifficultyLevel?> _chooseDifficulty({
    String title = 'Choose a starting level',
  }) async {
    final chosen = await showDifficultyDialog(
      context,
      initial: _difficulty,
      title: title,
      store: _difficultyStore,
    );
    if (chosen != null && mounted) setState(() => _difficulty = chosen);
    return chosen;
  }

  /// Dev-only: open a screen directly via `?preview=<name>` so individual
  /// screens can be screenshotted in isolation during design work. Never
  /// triggered in normal use (no query param present).
  void _maybeOpenPreview() {
    final name = Uri.base.queryParameters['preview'];
    if (name == null || name.isEmpty) return;
    Widget? page;
    switch (name) {
      case 'loudness':
        final session = IntervalTaskSession(
          moduleId: 'auditory',
          groupId: 'amplitude',
          paramName: 'delta_db',
          track: AdaptiveTrack(value: 8, min: 0.5, max: 15, step: 1),
        );
        page = IntervalTaskPage(
          title: 'Loudness discrimination',
          instruction: 'Play the three sounds. One is louder — choose which.',
          session: session,
          synth: (target, param, i) => levelDiscriminationStimulus(
            targetInterval: target,
            deltaDb: param,
            intervals: session.intervals,
          ),
          paramChip: (v) => 'Δ ${v.toStringAsFixed(1)} dB',
          thresholdText: (t) =>
              t == null ? 'not reached' : '${t.toStringAsFixed(1)} dB',
          choiceWord: 'Sound',
          audioPort: JustAudioPort(),
        );
      case 'pitch':
        final session = IntervalTaskSession(
          moduleId: 'foundation',
          groupId: 'pure_tone',
          paramName: 'delta_semitones',
          track: AdaptiveTrack.frequency(),
          extraParameters: const <String, Object?>{'reference_hz': 440.0},
        );
        page = IntervalTaskPage(
          title: 'Pitch discrimination',
          instruction: 'Play the three tones. One is higher — choose which.',
          session: session,
          synth: (t, p, i) => buildOddballSequence(
            targetInterval: t,
            referenceHz: 440,
            deltaSemitones: p,
          ),
          paramChip: (v) => 'Δ ${v.toStringAsFixed(1)} st',
          thresholdText: (t) =>
              t == null ? 'not reached' : '${t.toStringAsFixed(2)} semitones',
          choiceWord: 'Tone',
          intervalSeconds: 0.4,
          gapSeconds: 0.2,
          audioPort: JustAudioPort(),
          resultExtra: (ctx, t) => NormTile(Norms.frequencySemitones(t)),
        );
      case 'sin':
        page = const SpeechInNoisePage(
          moduleId: 'noise',
          groupId: 'sentence_noise',
          comfortableLevel: 0.4,
        );
      case 'word':
        page = ClosedSetPage(
          moduleId: 'learning',
          groupId: 'word',
          comfortableLevel: 0.4,
          pool: kWordItems,
          title: 'Word recognition',
          instruction: 'Listen, then choose the word you heard.',
          choiceCount: 4,
          snrTrack: AdaptiveTrack.snr(),
        );
      case 'dichotic':
        page = const DichoticPage(comfortableLevel: 0.4);
      case 'ident':
        page = IdentificationPage(
          moduleId: 'foundation',
          groupId: 'environment',
          comfortableLevel: 0.4,
          pool: kEnvironmentChoices,
          title: 'Environmental sounds',
          instruction: 'Listen, then choose the sound you heard.',
          choiceCount: 4,
          playLabel: 'Play sound',
          audioProvider: (target, i) async =>
              encodeWav16(sfxStimulus(target.id)),
          audioPort: JustAudioPort(),
        );
      case 'mci':
        page = const MciPage();
      case 'openword':
        page = const OpenSetPage(comfortableLevel: 0.4);
      case 'seq':
        page = const SequenceEntryPage();
      case 'dpt':
        page = PatternTestPage(
          testType: 'dpt',
          trialsPerEar: 5,
          audioPort: JustAudioPort(),
          onCompleted: (s) =>
              _persistRun(s.moduleId, s.groupId, 'test', s.records, session: s),
        );
      case 'fpt':
        page = PatternTestPage(
          testType: 'fpt',
          trialsPerEar: 5,
          audioPort: JustAudioPort(),
          onCompleted: (s) =>
              _persistRun(s.moduleId, s.groupId, 'test', s.records, session: s),
        );
      case 'mld':
        page = MldTestPage(
          maxTrialsPerCondition: 15,
          audioPort: JustAudioPort(),
        );
      case 'comfortable':
        page = const ComfortableLevelPage();
      case 'cst':
        page = CompetingSentencesPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
        );
      case 'filtered':
        page = FilteredSpeechPage(
          comfortableLevel: 0.4,
          trialsPerEar: 5,
          audioPort: JustAudioPort(),
        );
      case 'compressed':
        page = CompressedSpeechPage(
          comfortableLevel: 0.4,
          maxTrials: 8,
          audioPort: JustAudioPort(),
        );
      case 'fusion':
        page = BinauralFusionPage(
          comfortableLevel: 0.4,
          maxTrials: 8,
          audioPort: JustAudioPort(),
        );
      case 'hint':
        page = HintSinPage(
          comfortableLevel: 0.4,
          maxTrials: 10,
          audioPort: JustAudioPort(),
        );
      case 'rgdt':
        page = RgdtPage(
          comfortableLevel: 0.4,
          presentationsPerGap: 1,
          catchPerFrequency: 1,
          audioPort: JustAudioPort(),
        );
      case 'competing':
        page = CompetingSpeakersPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'speedtrain':
        page = CompressedTrainingPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'phonemic':
        page = PhonemicContrastPage(
          comfortableLevel: 0.4,
          maxTrials: 30,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'closure':
        page = ClosureTrainingPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'continuum':
        page = ContinuumPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'memory':
        page = WorkingMemoryPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          onCompleted: (records) =>
              _persistRun('auditory', 'working_memory', 'training', records),
        );
      case 'directions':
        page = FollowingDirectionsPage(
          comfortableLevel: 0.4,
          maxTrials: 15,
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'report':
        page = const ReportTabPage();
      case 'vowel':
        page = VowelTrainingPage(
          audioPort: JustAudioPort(),
          onCompleted: (records) =>
              _persistRun('learning', 'vowel_training', 'training', records),
        );
      case 'consonant':
        page = ConsonantTrainingPage(
          audioPort: JustAudioPort(),
          onCompleted: (records) => _persistRun(
              'learning', 'consonant_training', 'training', records),
        );
      case 'confusion':
        page = ConfusionMatrixPage(matrix: ConfusionMatrixPage.sample());
      case 'compare':
        page = const SessionComparePage();
      case 'audiogram':
        page = AudiogramPage(
          audioPort: JustAudioPort(),
          onCompleted: (s) =>
              _persistRun(s.moduleId, s.groupId, 'test', s.records, session: s),
        );
      case 'itdjnd':
        page = BinauralJndPage(
          mode: 'itd',
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'ildjnd':
        page = BinauralJndPage(
          mode: 'ild',
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'figureground':
        page = FigureGroundPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'tmtf':
        page = TmtfPage(
          audioPort: JustAudioPort(),
          onCompleted: (s) =>
              _persistRun(s.moduleId, s.groupId, 'test', s.records, session: s),
        );
      case 'ripple':
        page = _buildRipplePage();
      case 'irn':
        page = _buildIrnPage();
      case 'rhythmchange':
        page = _buildRhythmChangePage();
      case 'musicnoise':
        page = MusicInNoisePage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'beattap':
        page = BeatTapPage(
          audioPort: JustAudioPort(),
          onCompleted: (s) =>
              _persistRun(s.moduleId, s.groupId, 'test', s.records, session: s),
        );
      case 'bests':
        page = const PersonalBestsPage();
      case 'ri':
        page = ResidualInhibitionPage(
          audioPort: JustAudioPort(),
          onCompleted: (s) =>
              _persistRun(s.moduleId, s.groupId, 'test', s.records, session: s),
        );
      case 'desens':
        page = DesensitizationPage(audioPort: JustAudioPort());
      case 'trt':
        page = const TrtEducationPage();
      case 'thi':
        page = const ThiPage();
      case 'tfi':
        page = const TfiPage();
      case 'consent':
        page = const ConsentPage();
      case 'guardian':
        page = const GuardianViewPage();
      case 'story':
        page = const StoryPathPage();
      case 'kidsabc':
        page = KidsAbcPage(
          audioPortBuilder: JustAudioPort.new,
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'trends':
        page = const TrendPage();
      case 'vocoder':
        page = VocoderPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'spatial':
        page = SpatialPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'planner':
        page = PlannerPage(onStartExercise: _launchRecommended);
      case 'lisns':
        page = LisnsPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'ssw':
        page = SswPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'dsi':
        page = DsiPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'dichoticint':
        page = DichoticIntegrationPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'ssq12':
        page = const Ssq12Page();
      case 'hhie':
        page = const HhiePage();
      case 'aphab':
        page = const AphabPage();
      case 'fisher':
        page = const FisherPage();
      case 'questionnaires':
        page = const QuestionnairesHubPage();
      case 'tpitch':
        page = PitchMatchPage(audioPort: JustAudioPort());
      case 'tloud':
        page = LoudnessMatchPage(audioPort: JustAudioPort());
      case 'tmml':
        page = MmlPage(audioPort: JustAudioPort());
      case 'therapy':
        page = SoundTherapyPage(audioPort: JustAudioPort());
      case 'ldl':
        page = LdlPage(audioPort: JustAudioPort());
      case 'phono':
        page = PhonologicalPage(
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'scene':
        page = ScenePage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'interhemi':
        page = InterhemisphericPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'tracking':
        page = SpeechTrackingPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (records) =>
              _persistRun('openset', 'speech_tracking', 'training', records),
        );
      case 'sentclosure':
        page = SentenceClosurePage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 'openpools':
        page = _openWordPoolPage();
    }
    final built = page;
    if (built != null && mounted) {
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => built));
    }
  }

  void _openModule(Catalog catalog, Module module) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff1e293b),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ModuleDetailSheet(
        module: module,
        catalog: catalog,
        extraGroups: _diagnosticGroupsFor(module.id),
        onOpenGroup: (module, group) {
          Navigator.of(context).pop(); // close the sheet
          _openGroup(module, group);
        },
      ),
    );
  }

  /// Non-catalog CAPD diagnostic protocols surfaced inside a module's detail
  /// sheet. These live outside the signed 56-group catalog (which is pinned by
  /// the harness + backend tests) but reuse the same tile + routing so they are
  /// launchable from the module grid rather than only via `?preview=` links.
  List<ProtocolGroup> _diagnosticGroupsFor(String moduleId) {
    switch (moduleId) {
      case 'auditory':
        return <ProtocolGroup>[
          _diagGroup('duration_pattern', 'Duration Pattern Test (DPT)',
              'pattern_sequence'),
          _diagGroup('frequency_pattern', 'Frequency Pattern Test (FPT)',
              'pattern_sequence'),
          _diagGroup('masking_level_difference',
              'Masking Level Difference (MLD)', 'mld'),
          _diagGroup(
              'random_gap_detection', 'Random Gap Detection (RGDT)', 'rgdt'),
          _diagGroup('ssw', 'Staggered Spondaic Words (SSW)', 'ssw'),
          _diagGroup('dsi', 'Dichotic Sentence Identification (DSI)', 'dsi'),
          _diagGroup('screening_audiogram', 'Screening Audiogram (250–8k Hz)',
              'audiogram'),
          _diagGroup('itd_jnd', 'ITD Lateralization JND', 'binaural_jnd'),
          _diagGroup('ild_jnd', 'ILD Lateralization JND', 'binaural_jnd'),
          _diagGroup('tmtf', 'Temporal Modulation Curve (TMTF)', 'tmtf'),
          _diagGroup(
              'spectral_ripple', 'Spectral Ripple Discrimination', 'ripple'),
          _diagGroup('irn_pitch', 'Rippled-Noise Pitch Strength (IRN)', 'irn'),
        ];
      case 'music':
        return <ProtocolGroup>[
          _diagGroup(
              'rhythm_change', 'Rhythm Change in Melody', 'rhythm_change'),
          _diagGroup(
              'music_in_noise', 'Music in Noise (melodies)', 'music_in_noise'),
          _diagGroup(
              'beat_tapping', 'Beat Tapping (production)', 'beat_tapping'),
        ];
      case 'noise':
        return <ProtocolGroup>[
          _diagGroup('competing_sentences', 'Competing Sentences (CST)',
              'competing_sentences'),
          _diagGroup(
              'filtered_speech', 'Low-pass Filtered Speech', 'filtered_speech'),
          _diagGroup('compressed_speech', 'Time-compressed Speech',
              'compressed_speech'),
          _diagGroup('binaural_fusion', 'Binaural Fusion', 'binaural_fusion'),
          _diagGroup('hint_sentences', 'HINT Sentences in Noise', 'hint'),
          _diagGroup('lisn_s', 'LiSN-S (Spatialized Sentences)', 'lisn_s'),
          _diagGroup('figure_ground', 'Figure-Ground Words (+8/0/−8 dB SNR)',
              'figure_ground'),
        ];
      default:
        return const <ProtocolGroup>[];
    }
  }

  ProtocolGroup _diagGroup(String id, String name, String protocol) =>
      ProtocolGroup(
        id: id,
        name: name,
        protocol: protocol,
        modes: kWorkflowStages,
        validationStatus: 'unvalidated',
        parameters: const <String, dynamic>{},
      );

  /// Pushes a full-screen page onto the navigator.
  void _pushPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// Spectral ripple discrimination (A10): 3AFC phase-inverted-ripple oddball;
  /// the adapted parameter is the ripple period in octaves (reported as
  /// ripples/octave = 1/period).
  Widget _buildRipplePage() {
    final session = IntervalTaskSession(
      moduleId: 'auditory',
      groupId: 'spectral_ripple',
      paramName: 'ripple_period_oct',
      track: rippleTrack(),
    );
    return IntervalTaskPage(
      title: 'Spectral ripple discrimination',
      instruction:
          'Three noisy sounds play. One has a flipped spectral pattern — '
          'choose which sounds different.',
      session: session,
      synth: (t, p, i) =>
          buildRippleOddballSequence(targetInterval: t, periodOct: p, seed: i),
      paramChip: (v) => '${(1 / v).toStringAsFixed(1)} ripples/oct',
      thresholdText: (t) => t == null
          ? 'not reached'
          : '${(1 / t).toStringAsFixed(1)} ripples/oct resolved',
      choiceWord: 'Sound',
      intervalSeconds: 0.35,
      gapSeconds: 0.25,
      audioPort: JustAudioPort(),
      onCompleted: (s) => _persistRun(
          s.moduleId, s.groupId, s.mode.name, s.records,
          session: s),
    );
  }

  /// IRN pitch strength (A11): 2AFC IRN-vs-noise; the adapted parameter is
  /// the delay-add iteration count (fewer = weaker pitch = harder).
  Widget _buildIrnPage() {
    final session = IntervalTaskSession(
      moduleId: 'auditory',
      groupId: 'irn_pitch',
      paramName: 'irn_iterations',
      track: irnTrack(),
      intervals: 2,
    );
    return IntervalTaskPage(
      title: 'Rippled-noise pitch (IRN)',
      instruction:
          'Two noises play. One has a faint tone-like pitch inside it — '
          'choose which.',
      session: session,
      synth: (t, p, i) =>
          buildIrnSequence(targetInterval: t, iterations: p, seed: i),
      paramChip: (v) => 'n = ${v.round()}',
      thresholdText: (t) => t == null
          ? 'not reached'
          : 'pitch heard down to n = ${t.round()} iterations',
      choiceWord: 'Sound',
      intervalSeconds: 0.4,
      gapSeconds: 0.3,
      audioPort: JustAudioPort(),
      onCompleted: (s) => _persistRun(
          s.moduleId, s.groupId, s.mode.name, s.records,
          session: s),
    );
  }

  /// Rhythm change in melody (E6): 2AFC even-vs-displaced rendition of the
  /// same melody; the adapted parameter is the onset displacement (ms).
  Widget _buildRhythmChangePage() {
    final session = IntervalTaskSession(
      moduleId: 'music',
      groupId: 'rhythm_change',
      paramName: 'onset_shift_ms',
      track: rhythmChangeTrack(),
      intervals: 2,
    );
    return IntervalTaskPage(
      title: 'Rhythm change in melody',
      instruction:
          'The same tune plays twice. One version has an uneven rhythm — '
          'choose which.',
      session: session,
      synth: (t, p, i) =>
          buildRhythmChangeSequence(targetInterval: t, displaceMs: p, seed: i),
      paramChip: (v) => '${v.round()} ms shift',
      thresholdText: (t) =>
          t == null ? 'not reached' : '${t.round()} ms timing change detected',
      choiceWord: 'Melody',
      intervalSeconds: 4.5,
      gapSeconds: 0.5,
      validationStatus: 'demo_only',
      audioPort: JustAudioPort(),
      onCompleted: (s) => _persistRun(
          s.moduleId, s.groupId, s.mode.name, s.records,
          session: s),
    );
  }

  /// Shows the difficulty selector, then pushes a difficulty-aware diagnostic
  /// page (pattern tests, MLD, …) that runs directly without a comfortable-level
  /// check. No-op if the listener dismisses the selector.
  Future<void> _launchDiagnostic(
    Widget Function(DifficultyLevel difficulty) build,
  ) async {
    final chosen = await _chooseDifficulty();
    if (chosen == null || !mounted) return;
    _pushPage(build(chosen));
  }

  /// Routes a group to its renderer. Adaptive speech-in-noise goes through the
  /// comfortable-level check first; other protocols are not yet rendered.
  void _openGroup(Module module, ProtocolGroup group) {
    if (group.protocol == 'adaptive_snr_4afc') {
      _startSpeechInNoise(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'adaptive_3afc' && group.id == 'gap') {
      _startGapDetection(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'adaptive_3afc' &&
        group.id == 'modulation_depth') {
      _startModulationDetection(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'adaptive_3afc' &&
        group.id == 'modulation_rate') {
      _startModulationRate(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'adaptive_3afc' && group.id == 'amplitude') {
      _startLevelDiscrimination(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'adaptive_3afc' &&
        group.id == 'frequency_jnd') {
      _startPitch(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'adaptive_detection') {
      _startDetection(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
        masked: group.id == 'forward_masking',
      );
    } else if (group.protocol == 'rhythm_discrimination') {
      _startRhythm(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'chord_identification') {
      _startChord(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'closed_set' &&
        (group.id == 'word' ||
            group.id == 'sentence' ||
            group.id == 'numbers' ||
            group.id == 'alphabet')) {
      _startClosedSet(module: module, group: group);
    } else if (group.protocol == 'phoneme_contrast') {
      _startClosedSet(module: module, group: group);
    } else if (group.protocol == 'picture_identification' &&
        group.id == 'colors') {
      _startClosedSet(module: module, group: group);
    } else if (group.protocol == 'picture_identification' &&
        (group.id == 'food' || group.id == 'animals')) {
      _startPictures(module: module, group: group);
    } else if (group.protocol == 'closed_set' && group.id == 'environment') {
      _startEnvironment(module: module, group: group);
    } else if (group.protocol == 'closed_set' && group.id == 'speaker') {
      _startSpeaker(module: module, group: group);
    } else if (group.protocol == 'melody_identification') {
      _startFamiliarMelody(module: module, group: group);
    } else if (group.protocol == 'instrument_sequence' ||
        (group.protocol == 'sequence_entry' &&
            group.id == 'instrument_sequence')) {
      _startInstrumentSequence(module: module, group: group);
    } else if (group.protocol == 'mci_with_masker') {
      _startMci(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'sequence_entry' &&
        (group.id == 'melody_sequence' || group.id == 'melodic_sequence')) {
      _startNoteSequence(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'sequence_entry' && group.id == 'digit_span') {
      _startDigitSpan(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'typed_open_set' && group.id == 'open_word') {
      _startOpenWord(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'typed_open_set' &&
        group.id == 'open_sentence') {
      _startOpenSentence(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'typed_open_set' &&
        group.id == 'cnc_battery') {
      _startCnc(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'matrix_sentence') {
      _startMatrix(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'mci_9choice') {
      _startMci(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == '3afc_oddball') {
      _startPitch(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'dichotic_digits') {
      _startDichotic(
        moduleId: module.id,
        groupId: group.id,
        validationStatus: group.validationStatus,
      );
    } else if (group.protocol == 'threshold_battery' ||
        group.protocol == 'music_battery' ||
        group.protocol == 'adaptive_span' ||
        group.protocol == 'adaptive_srt' ||
        group.protocol == 'identification_matrix' ||
        group.protocol == 'music_identification') {
      _startBattery(module: module, group: group);
    } else if (group.id.contains('duration_pattern')) {
      _launchDiagnostic((d) => PatternTestPage(
          testType: 'dpt',
          difficulty: d,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, 'test', s.records,
              session: s)));
    } else if (group.id.contains('frequency_pattern')) {
      _launchDiagnostic((d) => PatternTestPage(
          testType: 'fpt',
          difficulty: d,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, 'test', s.records,
              session: s)));
    } else if (group.id.contains('masking_level') || group.id.contains('mld')) {
      _launchDiagnostic((d) => MldTestPage(
          maxTrialsPerCondition: 15,
          difficulty: d,
          audioPort: JustAudioPort()));
    } else if (group.id.contains('gap_detection') ||
        group.id.contains('rgdt')) {
      _pushPage(RgdtPage(
        comfortableLevel: 0.4,
        presentationsPerGap: 1,
        catchPerFrequency: 1,
        audioPort: JustAudioPort(),
      ));
    } else if (group.id.contains('competing_sentence')) {
      _pushPage(CompetingSentencesPage(
          comfortableLevel: 0.4, audioPort: JustAudioPort()));
    } else if (group.id.contains('filtered')) {
      _pushPage(FilteredSpeechPage(
          comfortableLevel: 0.4, trialsPerEar: 5, audioPort: JustAudioPort()));
    } else if (group.id.contains('compressed')) {
      _pushPage(CompressedSpeechPage(
          comfortableLevel: 0.4, maxTrials: 8, audioPort: JustAudioPort()));
    } else if (group.id.contains('binaural_fusion')) {
      _pushPage(BinauralFusionPage(
          comfortableLevel: 0.4, maxTrials: 8, audioPort: JustAudioPort()));
    } else if (group.id.contains('hint')) {
      _pushPage(HintSinPage(
          comfortableLevel: 0.4, maxTrials: 10, audioPort: JustAudioPort()));
    } else if (group.id.contains('lisn')) {
      _pushPage(LisnsPage(
        comfortableLevel: 0.4,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            s.moduleId, s.groupId, s.mode.name, s.records,
            session: s),
      ));
    } else if (group.id == 'ssw') {
      _pushPage(SswPage(
        comfortableLevel: 0.4,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            s.moduleId, s.groupId, s.mode.name, s.records,
            session: s),
      ));
    } else if (group.id == 'dsi') {
      _pushPage(DsiPage(
        comfortableLevel: 0.4,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            s.moduleId, s.groupId, s.mode.name, s.records,
            session: s),
      ));
    } else if (group.id == 'screening_audiogram') {
      _pushPage(AudiogramPage(
        audioPort: JustAudioPort(),
        onCompleted: (s) =>
            _persistRun(s.moduleId, s.groupId, 'test', s.records, session: s),
      ));
    } else if (group.id == 'itd_jnd' || group.id == 'ild_jnd') {
      _pushPage(BinauralJndPage(
        mode: group.id == 'itd_jnd' ? 'itd' : 'ild',
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            s.moduleId, s.groupId, s.mode.name, s.records,
            session: s),
      ));
    } else if (group.id == 'figure_ground') {
      _pushPage(FigureGroundPage(
        comfortableLevel: 0.4,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            s.moduleId, s.groupId, s.mode.name, s.records,
            session: s),
      ));
    } else if (group.id == 'tmtf') {
      _pushPage(TmtfPage(
        audioPort: JustAudioPort(),
        onCompleted: (s) =>
            _persistRun(s.moduleId, s.groupId, 'test', s.records, session: s),
      ));
    } else if (group.id == 'spectral_ripple') {
      _pushPage(_buildRipplePage());
    } else if (group.id == 'irn_pitch') {
      _pushPage(_buildIrnPage());
    } else if (group.id == 'rhythm_change') {
      _pushPage(_buildRhythmChangePage());
    } else if (group.id == 'music_in_noise') {
      _pushPage(MusicInNoisePage(
        comfortableLevel: 0.4,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            s.moduleId, s.groupId, s.mode.name, s.records,
            session: s),
      ));
    } else if (group.id == 'beat_tapping') {
      _pushPage(BeatTapPage(
        audioPort: JustAudioPort(),
        onCompleted: (s) =>
            _persistRun(s.moduleId, s.groupId, 'test', s.records, session: s),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('The "${group.protocol}" renderer is not built yet.'),
        ),
      );
    }
  }

  void _startComfortableCheck() {
    // Default entry point trains the everyday sentence-in-noise group.
    _startSpeechInNoise(
      moduleId: 'noise',
      groupId: 'sentence_noise',
      validationStatus: 'unvalidated',
    );
  }

  /// Difficulty selector → Comfortable-level check → Introduction → Preview →
  /// renderer (Training → Test → Results). Shared by every protocol launch.
  ///
  /// The chosen level is stored in [_difficulty] before the renderer is built,
  /// so renderer closures can pass it straight to their page.
  Future<void> _launchProtocol({
    required String title,
    required String description,
    required String exampleText,
    required String validationStatus,
    required Widget Function(double level) renderer,
  }) async {
    final chosen = await _chooseDifficulty();
    if (chosen == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComfortableLevelPage(
          onLocked: (level) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => ProtocolIntroScreen(
                  title: title,
                  description: description,
                  exampleText: exampleText,
                  validationStatus: validationStatus,
                  onStart: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => renderer(level)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _startSpeechInNoise({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Speech in noise',
      description:
          'You will hear an everyday word mixed with background noise, then '
          'choose which of four words you heard. The noise level adapts to '
          'your responses.',
      exampleText:
          'Example: you hear a word in noise, then tap it from four choices.',
      validationStatus: validationStatus,
      renderer: (level) => SpeechInNoisePage(
        moduleId: moduleId,
        groupId: groupId,
        comfortableLevel: level,
        difficulty: _difficulty,
        validationStatus: validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (session) => _persistRun(
            moduleId, groupId, session.mode.name, session.records,
            session: session),
      ),
    );
  }

  void _startModulationRate({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Modulation-rate discrimination',
      description:
          'You will hear three modulated sounds. One flutters faster than the '
          'others. Choose which. The difference shrinks as you improve.',
      exampleText:
          'Example: three sounds play; tap the one whose pulsing is faster.',
      validationStatus: validationStatus,
      renderer: (level) {
        final session = IntervalTaskSession(
          moduleId: moduleId,
          groupId: groupId,
          paramName: 'rate_ratio',
          track: AdaptiveTrack(value: 2, min: 1.05, max: 4, step: 0.2),
          extraParameters: const <String, Object?>{'reference_rate_hz': 20.0},
        );
        return IntervalTaskPage(
          title: 'Modulation-rate discrimination',
          instruction:
              'Play the three sounds. One flutters faster — choose which.',
          session: session,
          synth: (t, p, i) => buildRateOddballSequence(
            targetInterval: t,
            referenceRateHz: 20,
            ratio: p,
            seed: i,
          ),
          paramChip: (v) => '×${v.toStringAsFixed(2)}',
          difficulty: _difficulty,
          thresholdText: (t) =>
              t == null ? 'not reached' : '×${t.toStringAsFixed(2)} rate ratio',
          choiceWord: 'Sound',
          intervalSeconds: 0.5,
          gapSeconds: 0.25,
          validationStatus: validationStatus,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              moduleId, groupId, s.mode.name, s.records,
              session: s),
        );
      },
    );
  }

  /// Comfortable-level check → locked level → modulation-detection training.
  void _startModulationDetection({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Modulation detection',
      description:
          'You will hear three sounds. One flutters (its loudness pulses). '
          'Choose which one. The flutter becomes subtler as you improve.',
      exampleText:
          'Example: three sounds play; the one that pulses is the target.',
      validationStatus: validationStatus,
      renderer: (level) {
        final session = IntervalTaskSession(
          moduleId: moduleId,
          groupId: groupId,
          paramName: 'depth_db',
          track: AdaptiveTrack.modulation(),
          extraParameters: const <String, Object?>{'rate_hz': 20.0},
        );
        return IntervalTaskPage(
          title: 'Modulation detection',
          instruction: 'Play the three sounds. One flutters — choose which.',
          session: session,
          synth: (t, p, i) => buildModulationSequence(
            targetInterval: t,
            depthDb: p,
            rateHz: 20,
            seed: i,
          ),
          paramChip: (v) => '${v.toStringAsFixed(1)} dB',
          difficulty: _difficulty,
          thresholdText: (t) =>
              t == null ? 'not reached' : '${t.toStringAsFixed(1)} dB',
          choiceWord: 'Sound',
          intervalSeconds: 0.4,
          gapSeconds: 0.25,
          validationStatus: validationStatus,
          audioPort: JustAudioPort(),
          resultExtra: (ctx, t) => NormTile(Norms.amDepthDb(t)),
          onCompleted: (s) => _persistRun(
              moduleId, groupId, s.mode.name, s.records,
              session: s),
        );
      },
    );
  }

  void _startMci({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Melodic contour',
      description:
          'You will hear a five-note melody, then choose its overall shape '
          '(rising, falling, flat, or a combination) from nine options.',
      exampleText:
          'Example: you hear notes going up then down, then tap “Rise–Fall”.',
      validationStatus: validationStatus,
      renderer: (level) => MciPage(
        moduleId: moduleId,
        groupId: groupId,
        comfortableLevel: level,
        validationStatus: validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (session) => _persistRun(
            moduleId, groupId, session.mode.name, session.records,
            session: session),
      ),
    );
  }

  void _startPitch({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Pitch discrimination',
      description:
          'You will hear three tones. One is higher than the other two. '
          'Choose which. The pitch difference shrinks as you improve.',
      exampleText: 'Example: three tones play; tap the one that sounds higher.',
      validationStatus: validationStatus,
      renderer: (level) {
        final session = IntervalTaskSession(
          moduleId: moduleId,
          groupId: groupId,
          paramName: 'delta_semitones',
          track: AdaptiveTrack.frequency(),
          extraParameters: const <String, Object?>{'reference_hz': 440.0},
        );
        return IntervalTaskPage(
          title: 'Pitch discrimination',
          instruction: 'Play the three tones. One is higher — choose which.',
          session: session,
          synth: (t, p, i) => buildOddballSequence(
            targetInterval: t,
            referenceHz: 440,
            deltaSemitones: p,
          ),
          paramChip: (v) => 'Δ ${v.toStringAsFixed(1)} st',
          thresholdText: (t) =>
              t == null ? 'not reached' : '${t.toStringAsFixed(2)} semitones',
          choiceWord: 'Tone',
          intervalSeconds: 0.4,
          gapSeconds: 0.2,
          validationStatus: validationStatus,
          difficulty: _difficulty,
          audioPort: JustAudioPort(),
          resultExtra: (ctx, t) => NormTile(Norms.frequencySemitones(t)),
          onCompleted: (s) => _persistRun(
              moduleId, groupId, s.mode.name, s.records,
              session: s),
        );
      },
    );
  }

  void _startOpenWord({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Open-word recognition',
      description:
          'You will hear a word and type what you heard. Spelling is matched '
          'leniently (case and punctuation are ignored).',
      exampleText: 'Example: you hear “bell”, then type "bell".',
      validationStatus: validationStatus,
      renderer: (level) => OpenSetPage(
        moduleId: moduleId,
        groupId: groupId,
        comfortableLevel: level,
        validationStatus: validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (session) => _persistRun(
            moduleId, groupId, session.mode.name, session.records,
            session: session),
      ),
    );
  }

  void _startLevelDiscrimination({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Loudness discrimination',
      description:
          'Three sounds play. One is a little louder — choose which. It gets '
          'harder as the loudness difference shrinks.',
      exampleText: 'Example: sound 2 is slightly louder than 1 and 3.',
      validationStatus: validationStatus,
      renderer: (level) {
        final session = IntervalTaskSession(
          moduleId: moduleId,
          groupId: groupId,
          paramName: 'delta_db',
          track: AdaptiveTrack(value: 8, min: 0.5, max: 15, step: 1),
          extraParameters: const <String, Object?>{'carrier': 'tone_1000hz'},
        );
        return IntervalTaskPage(
          title: 'Loudness discrimination',
          instruction: 'Play the three sounds. One is louder — choose which.',
          session: session,
          synth: (target, param, i) => levelDiscriminationStimulus(
            targetInterval: target,
            deltaDb: param,
            intervals: session.intervals,
          ),
          paramChip: (v) => 'Δ ${v.toStringAsFixed(1)} dB',
          thresholdText: (t) =>
              t == null ? 'not reached' : '${t.toStringAsFixed(1)} dB',
          playLabel: 'Play sounds',
          replayLabel: 'Replay sounds',
          choiceWord: 'Sound',
          researchNote: 'Research measurement only — not a diagnosis.',
          validationStatus: validationStatus,
          difficulty: _difficulty,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              moduleId, groupId, s.mode.name, s.records,
              session: s),
        );
      },
    );
  }

  void _startDetection({
    required String moduleId,
    required String groupId,
    required String validationStatus,
    required bool masked,
  }) {
    _launchProtocol(
      title: 'Tone detection',
      description: masked
          ? 'A masking noise plays in each interval; a faint tone follows in '
              'one of them. Choose the interval with the tone.'
          : 'A faint tone is in one of three intervals. Choose which. It gets '
              'harder as the tone gets softer. Research only — not a hearing '
              '(dB HL) test.',
      exampleText: 'Example: only interval 3 contains the tone.',
      validationStatus: validationStatus,
      renderer: (level) {
        final session = IntervalTaskSession(
          moduleId: moduleId,
          groupId: groupId,
          paramName: 'tone_level_db',
          track: AdaptiveTrack(value: -6, min: -40, max: 6, step: 2),
          extraParameters: <String, Object?>{
            'research_only': true,
            if (masked) 'masker': 'white_noise',
          },
        );
        return IntervalTaskPage(
          title: 'Tone detection',
          instruction: 'Play the intervals. One has a tone — choose which.',
          session: session,
          synth: (target, param, i) => detectionStimulus(
            targetInterval: target,
            toneLevelDb: param,
            intervals: session.intervals,
            maskerAmp: masked ? 0.3 : 0,
            forwardGapMs: masked ? 30 : 0,
            seed: 1 + i,
          ),
          paramChip: (v) => 'Tone ${v.toStringAsFixed(0)} dB',
          difficulty: _difficulty,
          thresholdText: (t) => t == null
              ? 'not reached'
              : '${t.toStringAsFixed(1)} dB (relative, not dB HL)',
          playLabel: 'Play intervals',
          replayLabel: 'Replay intervals',
          choiceWord: 'Interval',
          intervalSeconds: 0.3,
          gapSeconds: 0.25,
          researchNote:
              'Research only — a relative-level detection task, not audiometry, '
              'and not a dB HL threshold.',
          validationStatus: validationStatus,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              moduleId, groupId, s.mode.name, s.records,
              session: s),
        );
      },
    );
  }

  void _startRhythm({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Rhythm discrimination',
      description:
          'Three rhythms play. Two are steady and one has a beat out of time — '
          'choose the odd one out.',
      exampleText: 'Example: rhythm 2 has one beat late.',
      validationStatus: validationStatus,
      renderer: (level) {
        final session = IntervalTaskSession(
          moduleId: moduleId,
          groupId: groupId,
          paramName: 'delta_ms',
          track: AdaptiveTrack(value: 90, min: 5, max: 150, step: 10),
        );
        return IntervalTaskPage(
          title: 'Rhythm discrimination',
          instruction:
              'Play the three rhythms. One is different — choose which.',
          session: session,
          synth: (target, param, i) => rhythmStimulus(
            targetInterval: target,
            deltaMs: param,
            intervals: session.intervals,
          ),
          paramChip: (v) => 'Δ ${v.toStringAsFixed(0)} ms',
          difficulty: _difficulty,
          thresholdText: (t) =>
              t == null ? 'not reached' : '${t.toStringAsFixed(0)} ms',
          playLabel: 'Play rhythms',
          replayLabel: 'Replay rhythms',
          choiceWord: 'Rhythm',
          intervalSeconds: 1.25,
          gapSeconds: 0.35,
          researchNote: 'Research measurement only — not a diagnosis.',
          validationStatus: validationStatus,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              moduleId, groupId, s.mode.name, s.records,
              session: s),
        );
      },
    );
  }

  void _startChord({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Chord identification',
      description:
          'A chord (three notes together) plays. Choose whether it is Major, '
          'Minor, Diminished, or Augmented.',
      exampleText: 'Example: a bright, stable chord is Major.',
      validationStatus: validationStatus,
      renderer: (level) => ChordIdentificationPage(
        moduleId: moduleId,
        groupId: groupId,
        comfortableLevel: level,
        validationStatus: validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (s) =>
            _persistRun(moduleId, groupId, s.mode.name, s.records, session: s),
      ),
    );
  }

  ({
    List<ClosedSetItem> pool,
    String title,
    String instruction,
    int choiceCount,
  }) _closedSetConfig(String groupId) {
    switch (groupId) {
      case 'word':
        return (
          pool: kWordItems,
          title: 'Word recognition',
          instruction: 'Play the word, then choose which word you heard.',
          choiceCount: 4,
        );
      case 'sentence':
        return (
          pool: kSentenceItems,
          title: 'Sentence recognition',
          instruction: 'Play the sentence, then choose which one you heard.',
          choiceCount: 4,
        );
      case 'numbers':
        return (
          pool: kDigitItems,
          title: 'Number recognition',
          instruction: 'Play the number, then choose which you heard.',
          choiceCount: 4,
        );
      case 'alphabet':
        return (
          pool: kLetterItems,
          title: 'Letter recognition',
          instruction: 'Play the letter, then choose which you heard.',
          choiceCount: 4,
        );
      case 'colors':
        return (
          pool: kColorItems,
          title: 'Color identification',
          instruction: 'Play the color name, then tap the matching color.',
          choiceCount: 4,
        );
      case 'vowel':
        return (
          pool: kPhonemeItems,
          title: 'Vowel recognition',
          instruction: 'Play the sound, then choose the syllable you heard.',
          choiceCount: 4,
        );
      case 'consonant':
        return (
          pool: kPhonemeItems,
          title: 'Consonant recognition',
          instruction: 'Play the sound, then choose the syllable you heard.',
          choiceCount: 4,
        );
      default: // phonetic_contrast and any other phoneme group
        return (
          pool: kPhonemeItems,
          title: 'Minimal phonetic contrasts',
          instruction: 'Play the sound, then choose the syllable you heard.',
          choiceCount: 4,
        );
    }
  }

  void _startOpenSentence({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Open-set sentence recognition',
      description:
          'You will hear a sentence and type what you heard. Scoring counts the '
          'words you get right (order-independent).',
      exampleText: 'Example: you hear “she reads a book”, type what you can.',
      validationStatus: validationStatus,
      renderer: (level) => OpenSetPage(
        moduleId: moduleId,
        groupId: groupId,
        comfortableLevel: level,
        itemBuilder: (i) {
          final it = kSentenceItems[i % kSentenceItems.length];
          return OpenSetItem(it.label, <String>[it.assetPath]);
        },
        scoreMode: OpenSetScoreMode.wordAccuracy,
        title: 'Open-set sentence recognition',
        instruction: 'Listen, then type the sentence you heard.',
        playNoun: 'sentence',
        validationStatus: validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (s) =>
            _persistRun(moduleId, groupId, s.mode.name, s.records, session: s),
      ),
    );
  }

  void _startCnc({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Open-set CNC word recognition',
      description:
          'You will hear a single word and type what you heard. Spelling is '
          'matched leniently.',
      exampleText: 'Example: you hear “boat”, type "boat".',
      validationStatus: validationStatus,
      renderer: (level) => OpenSetPage(
        moduleId: moduleId,
        groupId: groupId,
        comfortableLevel: level,
        itemBuilder: (i) {
          final it = kWordItems[i % kWordItems.length];
          return OpenSetItem(it.label, <String>[it.assetPath]);
        },
        title: 'Open-set CNC word recognition',
        instruction: 'Listen, then type the word you heard.',
        playNoun: 'word',
        validationStatus: validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (s) =>
            _persistRun(moduleId, groupId, s.mode.name, s.records, session: s),
      ),
    );
  }

  void _startMatrix({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Concatenated matrix sentences',
      description:
          'You will hear a five-word sentence (name, verb, number, adjective, '
          'noun) and type what you heard. Scoring counts the words you get '
          'right.',
      exampleText: 'Example: “lucy buys three red toys”.',
      validationStatus: validationStatus,
      renderer: (level) => OpenSetPage(
        moduleId: moduleId,
        groupId: groupId,
        comfortableLevel: level,
        itemBuilder: (i) {
          final m = buildMatrixSentence(Random(1000 + i));
          return OpenSetItem(m.text, m.assetPaths);
        },
        scoreMode: OpenSetScoreMode.wordAccuracy,
        title: 'Concatenated matrix sentences',
        instruction: 'Listen, then type the five-word sentence you heard.',
        playNoun: 'sentence',
        maxTrials: 15,
        validationStatus: validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (s) =>
            _persistRun(moduleId, groupId, s.mode.name, s.records, session: s),
      ),
    );
  }

  void _startEnvironment(
      {required Module module, required ProtocolGroup group}) {
    _launchProtocol(
      title: 'Environmental sounds',
      description:
          'You will hear a sound and choose what it is. Sounds are synthesized '
          'demonstrations, not recordings.',
      exampleText: 'Example: a ringing sound is a bell.',
      validationStatus: group.validationStatus,
      renderer: (level) => IdentificationPage(
        moduleId: module.id,
        groupId: group.id,
        comfortableLevel: level,
        pool: kEnvironmentChoices,
        title: 'Environmental sounds',
        instruction: 'Play the sound, then choose what it is.',
        playLabel: 'Play sound',
        validationStatus: group.validationStatus,
        audioProvider: (target, i) async => encodeWav16(sfxStimulus(target.id)),
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            module.id, group.id, s.mode.name, s.records,
            session: s),
      ),
    );
  }

  void _startSpeaker({required Module module, required ProtocolGroup group}) {
    _launchProtocol(
      title: 'Speaker identification',
      description:
          'You will hear a voice and choose which talker it was. Voices are '
          'generated demonstrations (`demo_only`).',
      exampleText: 'Example: a deeper voice is a different talker.',
      validationStatus: group.validationStatus,
      renderer: (level) => IdentificationPage(
        moduleId: module.id,
        groupId: group.id,
        comfortableLevel: level,
        pool: kSpeakerChoices,
        title: 'Speaker identification',
        instruction: 'Play the voice, then choose which talker it was.',
        playLabel: 'Play voice',
        validationStatus: group.validationStatus,
        audioProvider: (target, i) async =>
            (await rootBundle.load(target.assetPath!)).buffer.asUint8List(),
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            module.id, group.id, s.mode.name, s.records,
            session: s),
      ),
    );
  }

  void _startFamiliarMelody(
      {required Module module, required ProtocolGroup group}) {
    _launchProtocol(
      title: 'Familiar melody',
      description:
          'You will hear a well-known tune and choose which one it is. Tunes '
          'are synthesized (public-domain melodies).',
      exampleText: 'Example: “Twinkle, Twinkle”.',
      validationStatus: group.validationStatus,
      renderer: (level) => IdentificationPage(
        moduleId: module.id,
        groupId: group.id,
        comfortableLevel: level,
        pool: kMelodyChoices,
        title: 'Familiar melody',
        instruction: 'Play the tune, then choose which melody it is.',
        playLabel: 'Play tune',
        validationStatus: group.validationStatus,
        audioProvider: (target, i) async => encodeWav16(melodySynth(target.id)),
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            module.id, group.id, s.mode.name, s.records,
            session: s),
      ),
    );
  }

  void _startInstrumentSequence(
      {required Module module, required ProtocolGroup group}) {
    final lengths = group.id == 'instrument'
        ? const <int>[1, 2, 3, 5]
        : const <int>[2, 3, 5, 7];
    _launchProtocol(
      title: 'Instrument sequence',
      description:
          'You will hear one or more instruments and tap them back in order. '
          'Instrument timbres are synthesized (`demo_only`).',
      exampleText: 'Example: flute, then trumpet.',
      validationStatus: group.validationStatus,
      renderer: (level) => SymbolSequencePage(
        moduleId: module.id,
        groupId: group.id,
        comfortableLevel: level,
        symbols: kInstruments,
        synth: (symbols) => instrumentSequenceStimulus(symbols),
        labelFor: (s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1),
        title: 'Instrument sequence',
        playNoun: 'sounds',
        lengths: lengths,
        validationStatus: group.validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            module.id, group.id, s.mode.name, s.records,
            session: s),
      ),
    );
  }

  void _startPictures({required Module module, required ProtocolGroup group}) {
    final pool = group.id == 'food' ? kFoodChoices : kAnimalChoices;
    final noun = group.id == 'food' ? 'food' : 'animal';
    _launchProtocol(
      title: group.id == 'food' ? 'Learning food names' : 'Learning animals',
      description:
          'You will hear a $noun name and tap the matching picture. Speech is '
          'generated demonstration material (`demo_only`).',
      exampleText: 'Example: you hear the name, then tap its picture.',
      validationStatus: group.validationStatus,
      renderer: (level) => IdentificationPage(
        moduleId: module.id,
        groupId: group.id,
        comfortableLevel: level,
        pool: pool,
        title: group.id == 'food' ? 'Food names' : 'Animal names',
        instruction: 'Play the word, then tap the matching picture.',
        playLabel: 'Play word',
        validationStatus: group.validationStatus,
        audioProvider: (target, i) async =>
            (await rootBundle.load(target.assetPath!)).buffer.asUint8List(),
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            module.id, group.id, s.mode.name, s.records,
            session: s),
      ),
    );
  }

  void _startDichotic({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Dichotic digits',
      description:
          'A different number plays in each ear at the same time. Choose the '
          'number you heard in the cued ear. Use wired headphones so the ears '
          'stay separate.',
      exampleText:
          'Example: left ear “3”, right ear “7” — report the cued ear.',
      validationStatus: validationStatus,
      renderer: (level) => DichoticPage(
        moduleId: moduleId,
        groupId: groupId,
        comfortableLevel: level,
        validationStatus: validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (s) =>
            _persistRun(moduleId, groupId, s.mode.name, s.records, session: s),
      ),
    );
  }

  void _startClosedSet({required Module module, required ProtocolGroup group}) {
    final config = _closedSetConfig(group.id);
    // Word recognition is presented in *adaptive noise*: the SNR tracks the
    // listener 2-down/1-up, so difficulty follows the noise (cf. adaptive
    // speech-in-noise). Other closed sets stay quiet. Master volume is fixed.
    final adaptiveNoise = group.id == 'word';
    _launchProtocol(
      title: config.title,
      description: config.instruction,
      exampleText: adaptiveNoise
          ? 'Listen through the noise, then choose the word you heard.'
          : 'Listen to the sound, then choose what you heard.',
      validationStatus: group.validationStatus,
      renderer: (level) => ClosedSetPage(
        moduleId: module.id,
        groupId: group.id,
        comfortableLevel: level,
        pool: config.pool,
        title: config.title,
        instruction: adaptiveNoise
            ? 'Listen through the noise, then choose the word you heard.'
            : config.instruction,
        choiceCount: config.choiceCount,
        snrTrack: adaptiveNoise ? AdaptiveTrack.snr() : null,
        // Word/sentence recognition rotates the 4 proxy voices for talker
        // variety (presentation only).
        varyVoice: group.id == 'word' || group.id == 'sentence',
        validationStatus: group.validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            module.id, group.id, s.mode.name, s.records,
            session: s),
      ),
    );
  }

  String _batteryTitle(String id) => switch (id) {
        'resolution_battery' => 'Auditory resolution battery',
        'music_battery' => 'Music perception battery',
        'cognition_battery' => 'Auditory cognition battery',
        'noise_battery' => 'Speech-in-noise battery',
        'recognition_threshold' => 'Recognition threshold battery',
        'phoneme_battery' => 'Phoneme recognition battery',
        'music_appreciation' => 'Music appreciation sampler',
        _ => 'Assessment battery',
      };

  List<BatteryStage> _batteryStages(String id) {
    JustAudioPort port() => JustAudioPort();
    switch (id) {
      case 'resolution_battery':
        return <BatteryStage>[
          BatteryStage(
              'Gap detection',
              (lvl) => GapDetectionPage(
                  comfortableLevel: lvl,
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'auditory', 'gap', s.mode.name, s.records,
                      session: s))),
          BatteryStage(
              'Modulation detection',
              (lvl) => ModulationDetectionPage(
                  comfortableLevel: lvl,
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'auditory', 'modulation_depth', s.mode.name, s.records,
                      session: s))),
          BatteryStage(
              'Frequency discrimination',
              (lvl) => PitchDiscriminationPage(
                  moduleId: 'auditory',
                  groupId: 'frequency_jnd',
                  comfortableLevel: lvl,
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'auditory', 'frequency_jnd', s.mode.name, s.records,
                      session: s))),
        ];
      case 'music_battery':
      case 'music_appreciation':
        return <BatteryStage>[
          BatteryStage(
              'Note discrimination',
              (lvl) => PitchDiscriminationPage(
                  moduleId: 'music',
                  groupId: 'note_discrimination',
                  comfortableLevel: lvl,
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'music', 'note_discrimination', s.mode.name, s.records,
                      session: s))),
          BatteryStage(
              'Melodic contour',
              (lvl) => MciPage(
                  comfortableLevel: lvl,
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'music', 'mci', s.mode.name, s.records,
                      session: s))),
          BatteryStage(
              'Chord identification',
              (lvl) => ChordIdentificationPage(
                  comfortableLevel: lvl,
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'music', 'chord', s.mode.name, s.records,
                      session: s))),
        ];
      case 'cognition_battery':
        return <BatteryStage>[
          BatteryStage(
              'Digit span',
              (lvl) => SequenceEntryPage(
                  comfortableLevel: lvl,
                  onCompleted: (s) => _persistRun(
                      'openset', 'digit_span', s.mode.name, s.records,
                      session: s))),
          BatteryStage(
              'Melody recall',
              (lvl) => SymbolSequencePage(
                  moduleId: 'openset',
                  groupId: 'melody_sequence',
                  comfortableLevel: lvl,
                  symbols: const <String>['C', 'D', 'E', 'F', 'G'],
                  synth: (s) => noteSequenceStimulus(s),
                  title: 'Melody recall',
                  playNoun: 'melody',
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'openset', 'melody_sequence', s.mode.name, s.records,
                      session: s))),
        ];
      case 'noise_battery':
        return <BatteryStage>[
          BatteryStage(
              'Speech in noise',
              (lvl) => SpeechInNoisePage(
                  moduleId: 'noise',
                  groupId: 'sentence_noise',
                  comfortableLevel: lvl,
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'noise', 'sentence_noise', s.mode.name, s.records,
                      session: s))),
        ];
      case 'recognition_threshold':
        return <BatteryStage>[
          BatteryStage(
              'Speech in noise',
              (lvl) => SpeechInNoisePage(
                  moduleId: 'noise',
                  groupId: 'sentence_noise',
                  comfortableLevel: lvl,
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'noise', 'sentence_noise', s.mode.name, s.records,
                      session: s))),
          BatteryStage(
              'Open-set words',
              (lvl) => OpenSetPage(
                  comfortableLevel: lvl,
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'openset', 'open_word', s.mode.name, s.records,
                      session: s))),
        ];
      case 'phoneme_battery':
        return <BatteryStage>[
          BatteryStage(
              'Phoneme recognition',
              (lvl) => ClosedSetPage(
                  moduleId: 'assessment',
                  groupId: 'phoneme_battery',
                  comfortableLevel: lvl,
                  pool: kPhonemeItems,
                  title: 'Phoneme recognition',
                  instruction:
                      'Play the sound, then choose the syllable you heard.',
                  choiceCount: 4,
                  audioPort: port(),
                  onCompleted: (s) => _persistRun(
                      'assessment', 'phoneme_battery', s.mode.name, s.records,
                      session: s))),
        ];
      default:
        return const <BatteryStage>[];
    }
  }

  void _startBattery({required Module module, required ProtocolGroup group}) {
    final title = _batteryTitle(group.id);
    final stages = _batteryStages(group.id);
    _launchProtocol(
      title: title,
      description:
          'This battery runs several short tests in a row and shows a combined '
          'summary. Each test is stored separately with its own reliability.',
      exampleText: 'You can stop between tests; your progress is kept.',
      validationStatus: group.validationStatus,
      renderer: (level) =>
          BatteryRunnerPage(title: title, level: level, stages: stages),
    );
  }

  void _startNoteSequence({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Melody recall',
      description:
          'A short melody of notes plays. Tap the notes back in the same order. '
          'It gets longer as you succeed.',
      exampleText: 'Example: you hear C – E – G, then tap C, E, G.',
      validationStatus: validationStatus,
      renderer: (level) => SymbolSequencePage(
        moduleId: moduleId,
        groupId: groupId,
        comfortableLevel: level,
        symbols: const <String>['C', 'D', 'E', 'F', 'G'],
        synth: (symbols) => noteSequenceStimulus(symbols),
        title: 'Melody recall',
        playNoun: 'melody',
        validationStatus: validationStatus,
        audioPort: JustAudioPort(),
        onCompleted: (session) => _persistRun(
            moduleId, groupId, session.mode.name, session.records,
            session: session),
      ),
    );
  }

  void _startDigitSpan({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Digit sequence recall',
      description:
          'You will see a sequence of digits, then type it back from memory. '
          'The sequence gets longer as you improve. (Shown visually for now.)',
      exampleText: 'Example: you see 3 1 4, then type "314".',
      validationStatus: validationStatus,
      renderer: (level) => SequenceEntryPage(
        moduleId: moduleId,
        groupId: groupId,
        comfortableLevel: level,
        validationStatus: validationStatus,
        onCompleted: (session) => _persistRun(
            moduleId, groupId, session.mode.name, session.records,
            session: session),
      ),
    );
  }

  /// Comfortable-level check → locked level → temporal gap-detection training.
  void _startGapDetection({
    required String moduleId,
    required String groupId,
    required String validationStatus,
  }) {
    _launchProtocol(
      title: 'Temporal gap detection',
      description:
          'You will hear three bursts of noise. One contains a brief silent '
          'gap. Choose which burst had the gap. The gap gets shorter as you '
          'improve.',
      exampleText:
          'Example: three sounds play; the one with a tiny silence is the '
          'target.',
      validationStatus: validationStatus,
      renderer: (level) {
        final session = IntervalTaskSession(
          moduleId: moduleId,
          groupId: groupId,
          paramName: 'gap_ms',
          track: AdaptiveTrack.gap(startMs: _difficulty.config.startGapMs),
        );
        return IntervalTaskPage(
          title: 'Temporal gap detection',
          instruction:
              'Play the three sounds. One has a brief silent gap — choose '
              'which.',
          session: session,
          synth: (t, p, i) => buildGapSequence(
            targetInterval: t,
            gapMs: p,
            seed: i,
          ),
          paramChip: (v) => '${v.toStringAsFixed(1)} ms',
          thresholdText: (t) =>
              t == null ? 'not reached' : '${t.toStringAsFixed(1)} ms',
          choiceWord: 'Sound',
          intervalSeconds: 0.4,
          gapSeconds: 0.25,
          validationStatus: validationStatus,
          difficulty: _difficulty,
          audioPort: JustAudioPort(),
          resultExtra: (ctx, t) => NormTile(Norms.gapMs(t)),
          onCompleted: (s) => _persistRun(
              moduleId, groupId, s.mode.name, s.records,
              session: s),
        );
      },
    );
  }

  /// Saves a completed run locally first, shows its report, then performs
  /// optional network work in the background.
  Future<void> _persistRun(
    String moduleId,
    String groupId,
    String mode,
    List<TrialRecord> records, {
    Object? session,
  }) async {
    if (records.isEmpty) return;
    // Consent (J8): an explicit decline means nothing is persisted. The
    // listener still receives an in-memory result report for this run.
    final canPersist = persistenceAllowed;

    // Post-session fatigue + confidence self-report (optional; never affects
    // scoring).
    PostSessionRatings? ratings;
    if (mounted) {
      ratings = await showFatigueSheet(context);
    }

    // Build and persist the real report before touching the network. This is
    // the offline-first source of truth used by reports, trends and exports.
    final correct = records.where((r) => r.correct == true).length;
    final accuracy = records.isEmpty ? 0.0 : correct / records.length;
    final metric = summarizeSession(session);
    final record = SessionRecord(
      timestamp: DateTime.now(),
      moduleId: moduleId,
      groupId: groupId,
      title: _titleForGroup(moduleId, groupId),
      accuracy: accuracy,
      trials: records.length,
      metric: metric?.display,
      metricValue: metric?.value,
      metricUnit: metric?.unit,
      subScores: metric?.sub,
      trajectory: metric?.trajectory,
      trajectoryCorrect: metric?.trajectoryCorrect,
      chanceLevel: metric?.chanceLevel,
      higherIsBetter: metric?.higherIsBetter,
      confidence: ratings?.confidence,
      confusions: confusionPairsOf(records),
      label: ratings?.label,
    );
    var savedOffline = false;
    if (canPersist) {
      try {
        await SessionHistory().add(record);
        savedOffline = true;

        // Keep raw trials in the encrypted on-device queue. Upload is never
        // attempted here; online sharing happens only from the explicit Sync
        // screen after the listener links a clinician code.
        unawaited(_queueCompletedRun(
          moduleId: moduleId,
          groupId: groupId,
          mode: mode,
          records: records,
        ));

        // Opt-in local usage counters (J10): a no-op unless enabled.
        await UsageStats().record(groupId);

        // Gamification is local-only and never affects scoring or volume.
        final newBadges = await GamificationStore().recordSession(
          trials: records.length,
          correct: correct,
          testId: groupId,
        );
        for (final badge in newBadges) {
          if (!mounted) break;
          await showBadgeCelebration(context, badge);
        }
      } catch (_) {
        // Storage failures must not suppress the just-completed result.
      }
    }

    if (!mounted) return;
    final openReports = await showSessionResultSheet(
      context,
      record: record,
      savedOffline: savedOffline,
    );
    if (!mounted || !openReports) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _tabIndex = 4);
  }

  /// Queues raw trials locally without making a network request.
  Future<void> _queueCompletedRun({
    required String moduleId,
    required String groupId,
    required String mode,
    required List<TrialRecord> records,
  }) async {
    try {
      final trialQueue = await _queueFuture;
      await trialQueue.load();
      await enqueueSessionTrials(
        trialQueue,
        sessionId: 'local-${DateTime.now().microsecondsSinceEpoch}',
        moduleId: moduleId,
        groupId: groupId,
        mode: mode,
        records: records,
      );
    } catch (_) {
      // The summary report remains available if raw-trial queuing fails.
    }
  }

  String _titleForGroup(String moduleId, String groupId) {
    // Best-effort human-readable title from the group ID.
    return groupId
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp(r'^[a-z]'), (m) => m[0]!.toUpperCase());
  }

  /// Relaunches the exercise behind a history record ("Resume where you left
  /// off"). Reuses the planner's groupId→renderer routing.
  void _resumeSession(SessionRecord record) {
    _launchRecommended(ExercisePriority(
      moduleId: record.moduleId,
      groupId: record.groupId,
      title: record.title,
      lastScore: record.accuracy,
      trend: ExerciseTrend.stable,
      daysSinceAttempt: 0,
      attempts: 1,
      priority: 0,
      status: ExerciseStatus.improving,
      reason: 'resume',
    ));
  }

  /// Opens the automated session planner. Selecting an exercise closes the
  /// planner and launches the matching renderer.
  void _openPlanner() {
    _pushPage(PlannerPage(
      onStartExercise: (pick) {
        Navigator.of(context).pop(); // close the planner
        _launchRecommended(pick);
      },
    ));
  }

  /// Routes a planner recommendation to its renderer (best-effort; falls back
  /// to a message for exercises without a direct launcher here).
  void _launchRecommended(ExercisePriority pick) {
    final id = pick.groupId;
    final module = pick.moduleId;
    const unvalidated = 'unvalidated';
    if (id == 'vocoder') {
      _pushPage(VocoderPage(
        comfortableLevel: 0.4,
        maxTrials: 20,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            s.moduleId, s.groupId, s.mode.name, s.records,
            session: s),
      ));
    } else if (id == 'spatial') {
      _pushPage(SpatialPage(
        comfortableLevel: 0.4,
        maxTrials: 20,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            s.moduleId, s.groupId, s.mode.name, s.records,
            session: s),
      ));
    } else if (id.contains('noise') || module == 'noise') {
      _startSpeechInNoise(
          moduleId: 'noise',
          groupId: 'sentence_noise',
          validationStatus: unvalidated);
    } else if (id == 'gap') {
      _startGapDetection(
          moduleId: module, groupId: id, validationStatus: unvalidated);
    } else if (id == 'modulation_depth') {
      _startModulationDetection(
          moduleId: module, groupId: id, validationStatus: unvalidated);
    } else if (id == 'modulation_rate') {
      _startModulationRate(
          moduleId: module, groupId: id, validationStatus: unvalidated);
    } else if (id == 'frequency_jnd' || id == 'note_discrimination') {
      _startPitch(moduleId: module, groupId: id, validationStatus: unvalidated);
    } else if (id == 'amplitude') {
      _startLevelDiscrimination(
          moduleId: module, groupId: id, validationStatus: unvalidated);
    } else if (id == 'mci') {
      _startMci(moduleId: module, groupId: id, validationStatus: unvalidated);
    } else if (id == 'open_word') {
      _startOpenWord(
          moduleId: module, groupId: id, validationStatus: unvalidated);
    } else if (id == 'phonemic_contrast') {
      _pushPage(PhonemicContrastPage(
        comfortableLevel: 0.4,
        maxTrials: 30,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            s.moduleId, s.groupId, s.mode.name, s.records,
            session: s),
      ));
    } else if (id == 'speed_training') {
      _pushPage(CompressedTrainingPage(
        comfortableLevel: 0.4,
        maxTrials: 20,
        audioPort: JustAudioPort(),
        onCompleted: (s) => _persistRun(
            s.moduleId, s.groupId, s.mode.name, s.records,
            session: s),
      ));
    } else if (id == 'working_memory') {
      _pushPage(WorkingMemoryPage(
        comfortableLevel: 0.4,
        maxTrials: 20,
        onCompleted: (records) =>
            _persistRun('auditory', 'working_memory', 'training', records),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Open "${pick.title}" from its module to practise it.'),
        ),
      );
    }
  }

  /// Opens the explainable recommendation for the last persisted profile.
  void _openRecommendation() {
    final pid = _lastProfileId;
    if (pid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecommendationPage(
          profileId: pid,
          api: _api,
          onAccept: (rec) {
            Navigator.of(context).pop();
            if (rec.moduleId == 'noise') {
              _startSpeechInNoise(
                moduleId: rec.moduleId,
                groupId: rec.groupId,
                validationStatus: 'unvalidated',
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'The "${rec.moduleId} · ${rec.groupId}" renderer is not '
                    'built yet.',
                  ),
                ),
              );
            }
          },
          onOverride: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// Launches one of the adaptive-training exercises. Training needs no
  /// comfortable-level check (difficulty is what adapts, never volume), but the
  /// difficulty selector is still shown first so the listener can start harder.
  Future<void> _launchTraining(int index) async {
    final chosen = await _chooseDifficulty(title: 'Choose a training level');
    if (chosen == null || !mounted) return;
    final Widget page;
    switch (index) {
      case 0:
        page = CompetingSpeakersPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 1:
        page = CompressedTrainingPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 2:
        page = PhonemicContrastPage(
          comfortableLevel: 0.4,
          maxTrials: 30,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 3:
        page = ClosureTrainingPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 4:
        page = ContinuumPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 5:
        page = WorkingMemoryPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          onCompleted: (records) =>
              _persistRun('auditory', 'working_memory', 'training', records),
        );
      case 6:
        page = FollowingDirectionsPage(
          comfortableLevel: 0.4,
          maxTrials: 15,
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 7:
        page = VocoderPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          difficulty: chosen,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 8:
        page = SpatialPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 9:
        page = VowelTrainingPage(
          audioPort: JustAudioPort(),
          onCompleted: (records) =>
              _persistRun('learning', 'vowel_training', 'training', records),
        );
      case 10:
        page = ConsonantTrainingPage(
          audioPort: JustAudioPort(),
          onCompleted: (records) => _persistRun(
              'learning', 'consonant_training', 'training', records),
        );
      case 11:
        page = DichoticIntegrationPage(
          comfortableLevel: 0.4,
          maxTrials: 20,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 12:
        page = ProsodyPage(
          audioPort: JustAudioPort(),
          onCompleted: (records) =>
              _persistRun('foundation', 'prosody', 'training', records),
        );
      case 13:
        page = ReverbPage(
          audioPort: JustAudioPort(),
          onCompleted: (records) =>
              _persistRun('noise', 'reverb', 'training', records),
        );
      case 14:
        page = PitchRankingPage(
          audioPort: JustAudioPort(),
          onCompleted: (records) =>
              _persistRun('music', 'pitch_ranking', 'training', records),
        );
      case 15:
        page = TimbrePage(
          audioPort: JustAudioPort(),
          onCompleted: (records) =>
              _persistRun('music', 'timbre', 'training', records),
        );
      case 16:
        page = MusicEmotionPage(
          audioPort: JustAudioPort(),
          onCompleted: (records) =>
              _persistRun('music', 'music_emotion', 'training', records),
        );
      case 17:
        page = PhonologicalPage(
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 18:
        page = ScenePage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 19:
        page = InterhemisphericPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      case 20:
        page = SpeechTrackingPage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (records) =>
              _persistRun('openset', 'speech_tracking', 'training', records),
        );
      case 21:
        page = SentenceClosurePage(
          comfortableLevel: 0.4,
          audioPort: JustAudioPort(),
          onCompleted: (s) => _persistRun(
              s.moduleId, s.groupId, s.mode.name, s.records,
              session: s),
        );
      default:
        return;
    }
    _pushPage(page);
  }

  /// Builds the open-set word-recognition page with a Demo / CNC / NU-6 word
  /// pool selector (T3-5).
  Widget _openWordPoolPage() {
    const demo = WordListPool(
      id: 'demo',
      name: 'Demo',
      family: 'Demo',
      words: kOpenWordPool,
    );
    return OpenSetPage(
      moduleId: 'openset',
      groupId: 'open_word',
      comfortableLevel: 0.4,
      title: 'Word recognition',
      poolOptions: <WordListPool>[demo, ...kCncLists, ...kNu6Lists],
      poolLabel: 'Demo',
      audioPort: JustAudioPort(),
      onCompleted: (s) => _persistRun(
          s.moduleId, s.groupId, s.mode.name, s.records,
          session: s),
    );
  }

  /// Quick-start: pick a random training exercise.
  void _launchRandomTraining() =>
      _launchTraining(Random().nextInt(_kTrainingModules.length));

  /// Quick-start: jump to the Report tab in the bottom navigation.
  void _viewReport() => setState(() => _tabIndex = 4);

  void _openIntroduction() {
    _pushPage(
      OnboardingPage(
        onFinished: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }

  /// Quick-start: run the "Screening" CAPD battery preset. Shows the difficulty
  /// selector first, then pushes each mapped test in turn; when the listener
  /// leaves one, the next begins.
  Future<void> _launchCapdScreening() async {
    final chosen =
        await _chooseDifficulty(title: 'Choose a level for the screening');
    if (chosen == null || !mounted) return;
    final preset = kCapdBatteryPresets.firstWhere(
      (p) => p.name == 'Screening',
      orElse: () => kCapdBatteryPresets.first,
    );
    final pages = <Widget>[];
    for (final code in preset.tests) {
      final page = _capdTestPage(code, chosen);
      if (page != null) pages.add(page);
    }
    if (pages.isEmpty) return;
    _runSequence(pages, 0);
  }

  /// Maps a CAPD battery test code to its renderer (null if not built). The
  /// chosen [difficulty] is passed to the sub-tests that support it (pattern
  /// tests and MLD); the pattern tests keep a short per-ear count for the quick
  /// battery while still surfacing the level.
  Widget? _capdTestPage(String code, DifficultyLevel difficulty) {
    switch (code) {
      case 'GIN':
        return RgdtPage(
          comfortableLevel: 0.4,
          presentationsPerGap: 1,
          catchPerFrequency: 1,
          audioPort: JustAudioPort(),
        );
      case 'DDT':
        return const DichoticPage(comfortableLevel: 0.4);
      case 'DPT':
        return PatternTestPage(
            testType: 'dpt',
            trialsPerEar: 5,
            difficulty: difficulty,
            // Battery runs use the standard labeled mode (skip the chooser).
            responseMode: PatternResponseMode.labels,
            audioPort: JustAudioPort(),
            onCompleted: (s) => _persistRun(
                s.moduleId, s.groupId, 'test', s.records,
                session: s));
      case 'FPT':
        return PatternTestPage(
            testType: 'fpt',
            trialsPerEar: 5,
            difficulty: difficulty,
            responseMode: PatternResponseMode.labels,
            audioPort: JustAudioPort(),
            onCompleted: (s) => _persistRun(
                s.moduleId, s.groupId, 'test', s.records,
                session: s));
      case 'MLD':
        return MldTestPage(
            maxTrialsPerCondition: 15,
            difficulty: difficulty,
            audioPort: JustAudioPort());
      case 'SIN':
        return HintSinPage(
            comfortableLevel: 0.4, maxTrials: 10, audioPort: JustAudioPort());
      case 'Digit Span':
        return const SequenceEntryPage();
    }
    return null;
  }

  /// Pushes [pages] one after another: the next opens when the current pops.
  void _runSequence(List<Widget> pages, int index) {
    if (index >= pages.length || !mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => pages[index]))
        .then((_) => _runSequence(pages, index + 1));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildHomeTab(),
      _buildTestsTab(),
      _buildTrainingTab(),
      _buildTinnitusTab(),
      ReportTabPage(
        onStartTests: () => setState(() => _tabIndex = 1),
        onOpenIntroduction: _openIntroduction,
      ),
      const SettingsPage(),
    ];
    final content = IndexedStack(index: _tabIndex, children: pages);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    extended: constraints.maxWidth >= 1180,
                    selectedIndex: _tabIndex,
                    onDestinationSelected: (i) => setState(() => _tabIndex = i),
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: IconButton.filled(
                        tooltip: 'Introduction',
                        onPressed: _openIntroduction,
                        icon: const Icon(Icons.graphic_eq),
                      ),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home),
                        label: Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.hearing_outlined),
                        selectedIcon: Icon(Icons.hearing),
                        label: Text('Tests'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.fitness_center_outlined),
                        selectedIcon: Icon(Icons.fitness_center),
                        label: Text('Training'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.spa_outlined),
                        selectedIcon: Icon(Icons.spa),
                        label: Text('Tinnitus'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.description_outlined),
                        selectedIcon: Icon(Icons.description),
                        label: Text('Reports'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text('Settings'),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _compactNavigationIndex,
            onDestinationSelected: _selectCompactDestination,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.hearing_outlined),
                selectedIcon: Icon(Icons.hearing),
                label: 'Tests',
              ),
              NavigationDestination(
                icon: Icon(Icons.fitness_center_outlined),
                selectedIcon: Icon(Icons.fitness_center),
                label: 'Train',
              ),
              NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description),
                label: 'Reports',
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz),
                label: 'More',
              ),
            ],
          ),
        );
      },
    );
  }

  int get _compactNavigationIndex => switch (_tabIndex) {
        0 => 0,
        1 => 1,
        2 => 2,
        4 => 3,
        _ => 4,
      };

  void _selectCompactDestination(int index) {
    switch (index) {
      case 0:
        setState(() => _tabIndex = 0);
      case 1:
        setState(() => _tabIndex = 1);
      case 2:
        setState(() => _tabIndex = 2);
      case 3:
        setState(() => _tabIndex = 4);
      case 4:
        _showCompactMore();
    }
  }

  Future<void> _showCompactMore() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.spa_outlined),
              title: const Text('Tinnitus and sound comfort'),
              onTap: () => Navigator.of(context).pop(3),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () => Navigator.of(context).pop(5),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Introduction'),
              onTap: () => Navigator.of(context).pop(6),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 6) {
      _openIntroduction();
    } else {
      setState(() => _tabIndex = selected);
    }
  }

  /// Home tab: the hero, quick-start row and the full module + training grids.
  Widget _buildHomeTab() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HearBloom'),
        actions: [
          IconButton(
            tooltip: 'Clinician dashboard',
            icon: const Icon(Icons.medical_services_outlined),
            onPressed: () => _pushPage(const ClinicianDashboardPage()),
          ),
          IconButton(
            tooltip: 'Validation study protocol',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => _pushPage(const ValidationProtocolPage()),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => setState(() => _tabIndex = 5),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: _onMoreSelected,
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'reco',
                enabled: _lastProfileId != null,
                child: const ListTile(
                  leading: Icon(Icons.tips_and_updates_outlined),
                  title: Text('Suggested next step'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<String>(
                value: 'review',
                enabled: _lastProfileId != null,
                child: const ListTile(
                  leading: Icon(Icons.fact_check_outlined),
                  title: Text('Clinician review'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<String>(
                value: 'results',
                enabled: _lastProfileId != null,
                child: const ListTile(
                  leading: Icon(Icons.insights_outlined),
                  title: Text('View results'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'history',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Session history'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'compare',
                child: ListTile(
                  leading: Icon(Icons.compare_arrows),
                  title: Text('Compare sessions (A/B)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'questionnaires',
                child: ListTile(
                  leading: Icon(Icons.assignment_outlined),
                  title: Text('Questionnaires (SSQ12, APHAB…)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'bests',
                child: ListTile(
                  leading: Icon(Icons.emoji_events_outlined),
                  title: Text('Personal bests'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'guardian',
                child: ListTile(
                  leading: Icon(Icons.family_restroom),
                  title: Text('Guardian view (plain language)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'wordpools',
                child: ListTile(
                  leading: Icon(Icons.list_alt),
                  title: Text('Word recognition (CNC / NU-6)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Chip(label: Text('RESEARCH ONLY')),
          ),
        ],
      ),
      body: FutureBuilder<Catalog>(
        future: _catalogFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: 'Could not load protocol catalog.\n${snapshot.error}',
              onRetry: () => setState(() {
                _catalogFuture = _repository.load(forceReload: true);
              }),
            );
          }
          return _CatalogView(
            catalog: snapshot.data!,
            onOpenModule: _openModule,
            onStartComfortableCheck: _startComfortableCheck,
            onLaunchTraining: _launchTraining,
            onCapdScreening: _launchCapdScreening,
            onRandomTraining: _launchRandomTraining,
            onViewReport: _viewReport,
            onOpenPlanner: _openPlanner,
            onStartRecommended: _launchRecommended,
            onResume: _resumeSession,
          );
        },
      ),
    );
  }

  /// Tests tab: CAPD battery presets. Selecting a preset runs its sub-tests.
  Widget _buildTestsTab() {
    return CapdBatteryPresetsPage(onSelected: _runPreset);
  }

  /// Training tab: the adaptive-training exercise grid.
  Widget _buildTrainingTab() {
    return Scaffold(
      appBar: AppBar(title: const Text('Adaptive Training')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 1100
                ? 3
                : constraints.maxWidth > 700
                    ? 2
                    : 1;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (appSettings.value.kidsMode) ...[
                  const KidsModeBanner(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickStartCard(
                          icon: Icons.abc,
                          label: 'ABC worlds',
                          color: const Color(0xff22c55e),
                          onTap: () => _pushPage(KidsAbcPage(
                            audioPortBuilder: JustAudioPort.new,
                            onCompleted: (s) => _persistRun(
                                s.moduleId, s.groupId, s.mode.name, s.records,
                                session: s),
                          )),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickStartCard(
                          icon: Icons.auto_stories,
                          label: "Pip's journey",
                          color: const Color(0xfffbbf24),
                          onTap: () => _pushPage(const StoryPathPage()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Build your listening skills',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Difficulty adapts to you — master volume never changes.',
                  style: TextStyle(color: Color(0xff94a3b8), fontSize: 13),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.6,
                  children: [
                    for (var i = 0; i < _kTrainingModules.length; i++)
                      _TrainingCard(
                        module: _kTrainingModules[i],
                        onTap: () => _launchTraining(i),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Tinnitus & Hyperacusis tab: pitch/loudness match, MML, sound therapy, LDL.
  Widget _buildTinnitusTab() {
    Widget tile(IconData icon, Color color, String title, String subtitle,
            VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Semantics(
            button: true,
            label: title,
            child: Material(
              color: const Color(0x1affffff),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x33ffffff)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: color.withValues(alpha: 0.4)),
                        ),
                        child: Icon(icon, color: color),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    color: Color(0xffe2e8f0),
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(subtitle,
                                style: const TextStyle(
                                    color: Color(0xff94a3b8), fontSize: 12.5)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xff94a3b8)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Tinnitus & Hyperacusis')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Explore your tinnitus and sound tolerance, then relax with '
                  'sound therapy. Research/education tools — not a diagnosis. '
                  'Use wired headphones and keep the volume comfortably low.',
                  style: TextStyle(
                      color: Color(0xff94a3b8), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                tile(
                    Icons.graphic_eq,
                    const Color(0xff3b82f6),
                    'Pitch match',
                    'Find your tinnitus frequency (2AFC)',
                    () =>
                        _pushPage(PitchMatchPage(audioPort: JustAudioPort()))),
                tile(
                    Icons.volume_up,
                    const Color(0xff8b5cf6),
                    'Loudness match',
                    'Match your tinnitus loudness (dB SL)',
                    () => _pushPage(
                        LoudnessMatchPage(audioPort: JustAudioPort()))),
                tile(
                    Icons.blur_on,
                    const Color(0xff06b6d4),
                    'Minimum masking level',
                    'Find the noise level that covers it',
                    () => _pushPage(MmlPage(audioPort: JustAudioPort()))),
                tile(
                    Icons.spa,
                    const Color(0xff22c55e),
                    'Sound therapy',
                    'White/pink/brown noise, rain, ocean + notch',
                    () => _pushPage(
                        SoundTherapyPage(audioPort: JustAudioPort()))),
                tile(
                    Icons.warning_amber,
                    const Color(0xfffbbf24),
                    'Loudness discomfort (LDL)',
                    'Hyperacusis screen — safety-capped',
                    () => _pushPage(LdlPage(
                          audioPort: JustAudioPort(),
                          onCompleted: (s) => _persistRun(
                              s.moduleId, s.groupId, 'test', s.records,
                              session: s),
                        ))),
                tile(
                    Icons.timer_outlined,
                    const Color(0xfff87171),
                    'Residual inhibition',
                    'One-minute masker, then time the after-effect',
                    () => _pushPage(ResidualInhibitionPage(
                          audioPort: JustAudioPort(),
                          onCompleted: (s) => _persistRun(
                              s.moduleId, s.groupId, 'test', s.records,
                              session: s),
                        ))),
                tile(
                    Icons.trending_up,
                    const Color(0xff34d399),
                    'Sound comfort program',
                    '14-day graded desensitization below your LDL',
                    () => _pushPage(
                        DesensitizationPage(audioPort: JustAudioPort()))),
                tile(
                    Icons.menu_book_outlined,
                    const Color(0xff93c5fd),
                    'Understanding tinnitus',
                    'The habituation model behind TRT, in plain language',
                    () => _pushPage(const TrtEducationPage())),
                tile(
                    Icons.assignment_outlined,
                    const Color(0xffc4b5fd),
                    'THI questionnaire',
                    'Tinnitus Handicap Inventory (25 items)',
                    () => _pushPage(const ThiPage())),
                tile(
                    Icons.assignment_outlined,
                    const Color(0xff8b9bb4),
                    'Tinnitus impact (TFI-style)',
                    'Paraphrased 8-domain impact screen',
                    () => _pushPage(const TfiPage())),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Handles the overflow ("More") menu on the Home tab.
  void _onMoreSelected(String value) {
    switch (value) {
      case 'reco':
        _openRecommendation();
      case 'review':
        if (_lastProfileId != null) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ClinicianReviewPage(
                profileId: _lastProfileId!,
                api: _api,
              ),
            ),
          );
        }
      case 'results':
        if (_lastProfileId != null) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ResultsPage(profileId: _lastProfileId!, api: _api),
            ),
          );
        }
      case 'history':
        SessionHistorySheet.show(context);
      case 'compare':
        _pushPage(const SessionComparePage());
      case 'questionnaires':
        _pushPage(const QuestionnairesHubPage());
      case 'bests':
        _pushPage(const PersonalBestsPage());
      case 'guardian':
        _pushPage(const GuardianViewPage());
      case 'wordpools':
        _pushPage(_openWordPoolPage());
    }
  }

  /// Runs the sub-tests of [preset] in sequence (Tests tab), after showing the
  /// difficulty selector for the whole battery.
  Future<void> _runPreset(CapdBatteryPreset preset) async {
    final chosen = await _chooseDifficulty(
        title: 'Choose a level for the ${preset.name} battery');
    if (chosen == null || !mounted) return;
    final pages = <Widget>[];
    for (final code in preset.tests) {
      final page = _capdTestPage(code, chosen);
      if (page != null) pages.add(page);
    }
    if (pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No renderer available yet for the '
              '"${preset.name}" battery.'),
        ),
      );
      return;
    }
    _runSequence(pages, 0);
  }
}

class _CatalogView extends StatelessWidget {
  const _CatalogView({
    required this.catalog,
    required this.onOpenModule,
    required this.onStartComfortableCheck,
    required this.onLaunchTraining,
    required this.onCapdScreening,
    required this.onRandomTraining,
    required this.onViewReport,
    required this.onOpenPlanner,
    required this.onStartRecommended,
    required this.onResume,
  });

  final Catalog catalog;
  final void Function(Catalog catalog, Module module) onOpenModule;
  final VoidCallback onStartComfortableCheck;
  final void Function(int index) onLaunchTraining;
  final VoidCallback onCapdScreening;
  final VoidCallback onRandomTraining;
  final VoidCallback onViewReport;
  final VoidCallback onOpenPlanner;
  final void Function(ExercisePriority pick) onStartRecommended;
  final void Function(SessionRecord record) onResume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1100
            ? 3
            : constraints.maxWidth > 700
                ? 2
                : 1;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const _HeroHeader(),
            const SizedBox(height: 22),
            const GamificationOverlay(),
            const SizedBox(height: 22),
            _ResumeCard(onResume: onResume),
            _ReminderCard(onStart: onRandomTraining),
            const _PracticeHeatmapCard(),
            _TodayCard(onStart: onStartComfortableCheck),
            const SizedBox(height: 22),
            _QuickStartRow(
              onCapdScreening: onCapdScreening,
              onRandomTraining: onRandomTraining,
              onViewReport: onViewReport,
            ),
            const SizedBox(height: 22),
            _PlannerHomeCard(
              onOpen: onOpenPlanner,
              onStart: onStartRecommended,
            ),
            const SizedBox(height: 24),
            _HomeSearch(
              catalog: catalog,
              onOpenModule: onOpenModule,
              onLaunchTraining: onLaunchTraining,
            ),
            const SizedBox(height: 18),
            _FavoritesRow(
              catalog: catalog,
              onOpenModule: onOpenModule,
              onLaunchTraining: onLaunchTraining,
            ),
            Row(
              children: [
                Text(
                  'Complete laboratory',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${catalog.modules.length} modules · ${catalog.groupCount} groups',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xff94a3b8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.35,
              children: [
                for (final module in catalog.modules)
                  _ModuleCard(
                    module: module,
                    onTap: () => onOpenModule(catalog, module),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'Adaptive Training',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Build your listening skills with targeted exercises',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xff94a3b8),
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.6,
              children: [
                for (var i = 0; i < _kTrainingModules.length; i++)
                  _TrainingCard(
                    module: _kTrainingModules[i],
                    favoriteIndex: i,
                    onTap: () => onLaunchTraining(i),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Compact row of three quick-start actions above the module grid.
class _QuickStartRow extends StatelessWidget {
  const _QuickStartRow({
    required this.onCapdScreening,
    required this.onRandomTraining,
    required this.onViewReport,
  });

  final VoidCallback onCapdScreening;
  final VoidCallback onRandomTraining;
  final VoidCallback onViewReport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickStartCard(
            icon: Icons.hearing,
            label: 'CAPD Screening',
            color: const Color(0xff3b82f6),
            onTap: onCapdScreening,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickStartCard(
            icon: Icons.fitness_center,
            label: 'Training Session',
            color: const Color(0xff8b5cf6),
            onTap: onRandomTraining,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickStartCard(
            icon: Icons.description_outlined,
            label: 'View Report',
            color: const Color(0xff06b6d4),
            onTap: onViewReport,
          ),
        ),
      ],
    );
  }
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x1affffff), Color(0x0dffffff)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x33ffffff)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xffe2e8f0),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

/// "Recommended for you" home card: loads session history, shows the single
/// highest-priority exercise from the planner, and links to the full planner.
class _PlannerHomeCard extends StatefulWidget {
  const _PlannerHomeCard({required this.onOpen, required this.onStart});

  final VoidCallback onOpen;
  final void Function(ExercisePriority pick) onStart;

  @override
  State<_PlannerHomeCard> createState() => _PlannerHomeCardState();
}

class _PlannerHomeCardState extends State<_PlannerHomeCard> {
  ExercisePriority? _top;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<ExercisePriority> ranked = const [];
    try {
      final records = await SessionHistory().load();
      ranked = SessionPlanner.recommend(records, n: 1);
    } catch (_) {
      // History unavailable → show the prompt state.
    }
    if (!mounted) return;
    setState(() {
      _top = ranked.isEmpty ? null : ranked.first;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = _top;
    return Semantics(
      button: true,
      label: 'Recommended for you',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onOpen,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x1affffff), Color(0x0dffffff)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x553b82f6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: Color(0xff3b82f6), size: 18),
                    const SizedBox(width: 8),
                    Text('RECOMMENDED FOR YOU',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xff7dd3fc),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        )),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: Color(0xff94a3b8)),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_loaded)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('Analysing your history…',
                        style: TextStyle(color: Color(0xff94a3b8))),
                  )
                else if (top == null)
                  const Text(
                    'Complete a session and we’ll suggest what to practise '
                    'next, based on your scores and how long since you last '
                    'tried each exercise.',
                    style: TextStyle(color: Color(0xff94a3b8), height: 1.35),
                  )
                else ...[
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: statusColor(top.status),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: statusColor(top.status)
                                    .withValues(alpha: 0.5),
                                blurRadius: 8),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(top.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xffe2e8f0))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(top.reason,
                      style: const TextStyle(color: Color(0xff94a3b8))),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const Key('home-start-recommended'),
                    onPressed: () => widget.onStart(top),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start recommended'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Card for a single adaptive-training exercise in the Training grid.
class _TrainingCard extends StatelessWidget {
  const _TrainingCard(
      {required this.module, required this.onTap, this.favoriteIndex});

  final _TrainingModule module;
  final VoidCallback onTap;

  /// When set, a favourites star is shown for `training:<favoriteIndex>`.
  final int? favoriteIndex;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: module.title,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0x338b5cf6),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(module.icon,
                      color: const Color(0xffc4b5fd), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xffe2e8f0),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        module.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff94a3b8),
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (favoriteIndex != null)
                  _FavoriteStar(id: trainingFavoriteId(favoriteIndex!)),
                const Icon(Icons.chevron_right, color: Color(0xff94a3b8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff1c5fbf), Color(0xff2f80ed), Color(0xff27a3c4)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0x33ffffff),
                  borderRadius: BorderRadius.circular(13),
                ),
                child:
                    const Icon(Icons.graphic_eq, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 13),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HearBloom',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1.05,
                          fontWeight: FontWeight.w800)),
                  Text('Auditory-training research lab',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          letterSpacing: 0.3)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Train what everyday listening demands.',
              style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  height: 1.1,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Adaptive speech-in-noise, temporal processing, dichotic listening '
            'and auditory memory — driven by a deterministic, volume-locked '
            'engine.',
            style: TextStyle(color: Colors.white, height: 1.35, fontSize: 14.5),
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroChip(Icons.tune, 'Adaptive difficulty'),
              _HeroChip(Icons.graphic_eq, 'Adaptive noise (SNR)'),
              _HeroChip(Icons.lock_outline, 'Volume locked · ANSD-safe'),
              _HeroChip(Icons.science_outlined, 'Research only · no diagnosis'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x29ffffff),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: const Color(0xff1e293b),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x333b82f6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TODAY · 30 MINUTES',
              style: TextStyle(
                letterSpacing: 1.3,
                fontWeight: FontWeight.bold,
                color: Color(0xff7dd3fc),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Speech in noise → rest → dichotic attention → rest → temporal '
              'processing',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xffe2e8f0),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start comfortable-level check'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.onTap});

  final Module module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = _presentation[module.id] ?? _fallbackPresentation;
    final groupCount = module.groups.isNotEmpty ? module.groups.length : null;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // Painted per-module thumbnail (motif chosen by module id).
              SizedBox(
                width: 54,
                height: 54,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: CustomPaint(
                        painter: ModuleThumbnailPainter(moduleId: module.id),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Text(
                      p.glyph,
                      style: TextStyle(
                        fontSize: 20,
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.name,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xffe2e8f0),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      p.tagline,
                      style: const TextStyle(
                        color: Color(0xff94a3b8),
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                    if (groupCount != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xff293548),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '$groupCount protocol groups',
                          style: const TextStyle(
                            color: Color(0xff94a3b8),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ] else if (module.inheritsAnother) ...[
                      const SizedBox(height: 6),
                      Text(
                        'inherits ${module.inherits}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _FavoriteStar(id: moduleFavoriteId(module.id)),
              const Icon(Icons.chevron_right, color: Color(0xff94a3b8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Your favorites" quick-access chips: the starred modules and trainings,
/// hidden while nothing is starred.
class _FavoritesRow extends StatelessWidget {
  const _FavoritesRow({
    required this.catalog,
    required this.onOpenModule,
    required this.onLaunchTraining,
  });

  final Catalog catalog;
  final void Function(Catalog catalog, Module module) onOpenModule;
  final void Function(int index) onLaunchTraining;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: favoriteIds,
      builder: (context, favorites, _) {
        final chips = <Widget>[];
        for (final module in catalog.modules) {
          if (favorites.contains(moduleFavoriteId(module.id))) {
            chips.add(ActionChip(
              key: Key('favchip-module-${module.id}'),
              avatar:
                  const Icon(Icons.star, size: 16, color: Color(0xfffbbf24)),
              label: Text(module.name),
              onPressed: () => onOpenModule(catalog, module),
            ));
          }
        }
        for (var i = 0; i < _kTrainingModules.length; i++) {
          if (favorites.contains(trainingFavoriteId(i))) {
            chips.add(ActionChip(
              key: Key('favchip-training-$i'),
              avatar:
                  const Icon(Icons.star, size: 16, color: Color(0xfffbbf24)),
              label: Text(_kTrainingModules[i].title),
              onPressed: () => onLaunchTraining(i),
            ));
          }
        }
        if (chips.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your favorites',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: chips),
            ],
          ),
        );
      },
    );
  }
}

/// A small star toggle bound to the shared favourites set.
class _FavoriteStar extends StatelessWidget {
  const _FavoriteStar({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: favoriteIds,
      builder: (context, favorites, _) {
        final isFav = favorites.contains(id);
        return IconButton(
          key: Key('fav-$id'),
          tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
          visualDensity: VisualDensity.compact,
          onPressed: () => FavoritesStore().toggle(id),
          icon: Icon(
            isFav ? Icons.star : Icons.star_border,
            size: 20,
            color: isFav ? const Color(0xfffbbf24) : const Color(0xff8b9bb4),
          ),
        );
      },
    );
  }
}

/// Painted decorative thumbnail for a module card: a per-module gradient with
/// a themed motif (waveform, scatter dots, note stems, bars…). Purely
/// decorative; deterministic per module id.
class ModuleThumbnailPainter extends CustomPainter {
  ModuleThumbnailPainter({required this.moduleId});

  final String moduleId;

  static const Map<String, List<Color>> _palettes = <String, List<Color>>{
    'auditory': [Color(0xff1e3a5f), Color(0xff3b82f6)],
    'noise': [Color(0xff312e81), Color(0xff8b5cf6)],
    'music': [Color(0xff164e63), Color(0xff06b6d4)],
    'memory': [Color(0xff14532d), Color(0xff22c55e)],
    'learning': [Color(0xff713f12), Color(0xfffbbf24)],
    'openset': [Color(0xff7f1d1d), Color(0xfff87171)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final colors =
        _palettes[moduleId] ?? const [Color(0xff1e293b), Color(0xff475569)];
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors[0], colors[1].withValues(alpha: 0.55)],
        ).createShader(rect),
    );
    final motif = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    switch (moduleId) {
      case 'auditory': // sine waveform
        final path = Path();
        for (var x = 0.0; x <= size.width; x += 1) {
          final y = size.height / 2 +
              sin(x / size.width * 4 * pi) * size.height * 0.22;
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, motif);
      case 'noise': // scatter dots (deterministic)
        final rng = Random(7);
        final dot = Paint()..color = Colors.white.withValues(alpha: 0.3);
        for (var i = 0; i < 14; i++) {
          canvas.drawCircle(
            Offset(
                rng.nextDouble() * size.width, rng.nextDouble() * size.height),
            1.6,
            dot,
          );
        }
      case 'music': // two note stems
        final fill = Paint()..color = Colors.white.withValues(alpha: 0.35);
        for (final dx in [size.width * 0.35, size.width * 0.62]) {
          final head = Offset(dx, size.height * 0.68);
          canvas.drawCircle(head, 3.4, fill);
          canvas.drawLine(head.translate(3.2, 0),
              Offset(dx + 3.2, size.height * 0.28), motif);
        }
      case 'memory': // stacked recall blocks
        for (var i = 0; i < 3; i++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(size.width * (0.25 + i * 0.06),
                  size.height * (0.62 - i * 0.18), size.width * 0.4, 7),
              const Radius.circular(2),
            ),
            motif,
          );
        }
      default: // rising level bars
        for (var i = 0; i < 4; i++) {
          final h = size.height * (0.2 + i * 0.16);
          canvas.drawLine(
            Offset(size.width * (0.28 + i * 0.15), size.height * 0.8),
            Offset(size.width * (0.28 + i * 0.15), size.height * 0.8 - h),
            motif,
          );
        }
    }
  }

  @override
  bool shouldRepaint(ModuleThumbnailPainter oldDelegate) =>
      oldDelegate.moduleId != moduleId;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// "Continue where you left off" card: relaunches the most recent exercise.
/// Hidden until at least one session exists; refreshes when history changes.
/// In-app daily practice reminder: when the reminder is enabled, the chosen
/// hour has passed, nothing was practised today and it hasn't been snoozed,
/// a gentle banner offers to start a session. Honest scope: an in-app
/// banner only — there is no OS push-notification plumbing.
class _ReminderCard extends StatefulWidget {
  const _ReminderCard({required this.onStart});

  final VoidCallback onStart;

  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _check();
    sessionHistoryRevision.addListener(_check);
  }

  @override
  void dispose() {
    sessionHistoryRevision.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final store = ReminderStore();
      final settings = await store.load();
      final now = DateTime.now();
      if (!settings.enabled ||
          now.hour < settings.hour ||
          await store.isDismissedFor(now)) {
        if (mounted) setState(() => _show = false);
        return;
      }
      final history = await SessionHistory().load();
      final practisedToday = history.any((r) =>
          r.timestamp.year == now.year &&
          r.timestamp.month == now.month &&
          r.timestamp.day == now.day);
      if (mounted) setState(() => _show = !practisedToday);
    } catch (_) {
      if (mounted) setState(() => _show = false);
    }
  }

  Future<void> _dismiss() async {
    try {
      await ReminderStore().dismissFor(DateTime.now());
    } catch (_) {}
    if (mounted) setState(() => _show = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x33fbbf24), Color(0x1afbbf24)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x66fbbf24)),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_active_outlined,
                color: Color(0xfffbbf24)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No listening practice yet today — a short session keeps '
                'the streak alive.',
                style: TextStyle(
                    color: Color(0xffe2e8f0),
                    fontWeight: FontWeight.w600,
                    height: 1.35),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('reminder-start'),
              onPressed: widget.onStart,
              child: const Text('Start'),
            ),
            IconButton(
              key: const Key('reminder-dismiss'),
              tooltip: 'Not today',
              onPressed: _dismiss,
              icon: const Icon(Icons.close, color: Color(0xff8b9bb4)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeCard extends StatefulWidget {
  const _ResumeCard({required this.onResume});

  final void Function(SessionRecord record) onResume;

  @override
  State<_ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends State<_ResumeCard> {
  SessionRecord? _latest;

  @override
  void initState() {
    super.initState();
    _load();
    sessionHistoryRevision.addListener(_load);
  }

  @override
  void dispose() {
    sessionHistoryRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final history = await SessionHistory().load();
    if (mounted) {
      setState(() => _latest = history.isEmpty ? null : history.first);
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) {
    final r = _latest;
    if (r == null) return const SizedBox.shrink();
    final score = r.metric ?? '${(r.accuracy * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Semantics(
        button: true,
        label: 'Resume ${r.title}, last result $score, ${_ago(r.timestamp)}',
        child: Material(
          color: const Color(0x1a3b82f6),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: const Key('resume-card'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => widget.onResume(r),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x553b82f6)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0x333b82f6),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.play_circle_outline,
                        color: Color(0xff60a5fa), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Continue where you left off',
                            style: TextStyle(
                                color: Color(0xffe2e8f0),
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('${r.title} · $score · ${_ago(r.timestamp)}',
                            style: const TextStyle(
                                color: Color(0xff94a3b8), fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xff94a3b8)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// GitHub-style practice calendar: one cell per day for the last ten weeks,
/// tinted by how many sessions were completed that day. Purely motivational.
class _PracticeHeatmapCard extends StatefulWidget {
  const _PracticeHeatmapCard();

  @override
  State<_PracticeHeatmapCard> createState() => _PracticeHeatmapCardState();
}

class _PracticeHeatmapCardState extends State<_PracticeHeatmapCard> {
  Map<String, int> _perDay = const {};
  int _total = 0;

  static const int _weeks = 10;

  @override
  void initState() {
    super.initState();
    _load();
    sessionHistoryRevision.addListener(_load);
  }

  @override
  void dispose() {
    sessionHistoryRevision.removeListener(_load);
    super.dispose();
  }

  static String _dayKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final history = await SessionHistory().load();
    final perDay = <String, int>{};
    for (final r in history) {
      final k = _dayKey(r.timestamp);
      perDay[k] = (perDay[k] ?? 0) + 1;
    }
    if (mounted) {
      setState(() {
        _perDay = perDay;
        _total = history.length;
      });
    }
  }

  Color _cellColor(int count) => switch (count) {
        0 => const Color(0x14ffffff),
        1 => const Color(0x5522c55e),
        2 => const Color(0x9922c55e),
        _ => const Color(0xff22c55e),
      };

  @override
  Widget build(BuildContext context) {
    if (_total == 0) return const SizedBox.shrink();
    final today = DateTime.now();
    // Columns are weeks (oldest -> newest); rows Monday..Sunday.
    final start =
        today.subtract(Duration(days: (_weeks - 1) * 7 + (today.weekday - 1)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x1affffff),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x33ffffff)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_month_outlined,
                    size: 18, color: Color(0xff22c55e)),
                SizedBox(width: 8),
                Text('Practice calendar',
                    style: TextStyle(
                        color: Color(0xffe2e8f0),
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Spacer(),
                Text('last $_weeks weeks',
                    style: TextStyle(color: Color(0xff94a3b8), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Practice calendar, $_total sessions recorded',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cell =
                      ((constraints.maxWidth - (_weeks - 1) * 3) / _weeks)
                          .clamp(8.0, 16.0);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var w = 0; w < _weeks; w++)
                        Column(
                          children: [
                            for (var d = 0; d < 7; d++)
                              Builder(builder: (_) {
                                final day =
                                    start.add(Duration(days: w * 7 + d));
                                final after = day.isAfter(today);
                                final count =
                                    after ? 0 : (_perDay[_dayKey(day)] ?? 0);
                                return Container(
                                  width: cell,
                                  height: cell,
                                  margin: const EdgeInsets.only(bottom: 3),
                                  decoration: BoxDecoration(
                                    color: after
                                        ? Colors.transparent
                                        : _cellColor(count),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                );
                              }),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One entry in the home search results.
class _SearchHit {
  const _SearchHit(this.kind, this.title, this.subtitle, this.onOpen);

  final String kind; // 'Module' or 'Training'
  final String title;
  final String subtitle;
  final VoidCallback onOpen;
}

/// Search across catalog modules/groups and adaptive-training exercises.
class _HomeSearch extends StatefulWidget {
  const _HomeSearch({
    required this.catalog,
    required this.onOpenModule,
    required this.onLaunchTraining,
  });

  final Catalog catalog;
  final void Function(Catalog catalog, Module module) onOpenModule;
  final void Function(int index) onLaunchTraining;

  @override
  State<_HomeSearch> createState() => _HomeSearchState();
}

class _HomeSearchState extends State<_HomeSearch> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_SearchHit> get _hits {
    final q = _query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final hits = <_SearchHit>[];
    for (final module in widget.catalog.modules) {
      final groupNames = module.groups.map((g) => g.name).join(' ');
      final haystack = '${module.name} $groupNames'.toLowerCase();
      if (haystack.contains(q)) {
        final matching = module.groups
            .where((g) => g.name.toLowerCase().contains(q))
            .map((g) => g.name)
            .take(3)
            .join(' · ');
        hits.add(_SearchHit(
          'Module',
          module.name,
          matching.isEmpty ? '${module.groups.length} groups' : matching,
          () => widget.onOpenModule(widget.catalog, module),
        ));
      }
    }
    for (var i = 0; i < _kTrainingModules.length; i++) {
      final t = _kTrainingModules[i];
      if ('${t.title} ${t.subtitle}'.toLowerCase().contains(q)) {
        hits.add(_SearchHit(
          'Training',
          t.title,
          t.subtitle,
          () => widget.onLaunchTraining(i),
        ));
      }
    }
    return hits.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          textField: true,
          label: 'Search tests and training',
          child: TextField(
            key: const Key('home-search'),
            controller: _controller,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search tests & training…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: const Color(0x14ffffff),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0x33ffffff)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0x33ffffff)),
              ),
            ),
          ),
        ),
        if (_query.trim().length >= 2) ...[
          const SizedBox(height: 8),
          if (hits.isEmpty)
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text('No matches. Try "noise", "pitch", "dichotic"…',
                  style: TextStyle(color: Color(0xff94a3b8), fontSize: 13)),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: const Color(0x14ffffff),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x33ffffff)),
              ),
              child: Column(
                children: [
                  for (final hit in hits)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        hit.kind == 'Module'
                            ? Icons.hearing_outlined
                            : Icons.fitness_center,
                        size: 20,
                        color: hit.kind == 'Module'
                            ? const Color(0xff60a5fa)
                            : const Color(0xff34d399),
                      ),
                      title: Text(hit.title,
                          style: const TextStyle(
                              color: Color(0xffe2e8f0),
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      subtitle: Text(hit.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xff94a3b8), fontSize: 12)),
                      trailing: Text(hit.kind,
                          style: const TextStyle(
                              color: Color(0xff8b9bb4), fontSize: 11)),
                      onTap: () {
                        _controller.clear();
                        setState(() => _query = '');
                        hit.onOpen();
                      },
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
