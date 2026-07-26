# Tier 3+4 build progress (working memory)

Root: apps/flutter_app. SDKs: flutter/dart at %LOCALAPPDATA%\hearbloom-flutter\flutter\bin\*.bat
Before flutter test: delete **/ephemeral + build/unit_test_assets (OneDrive lock). No new pub deps.
Deps available: http, shared_preferences, just_audio, fl_chart, intl, google_fonts, cryptography.

## Key patterns learned
- TrialScaffold(title, subtitle, instruction, instructionIcon, pills:[MetaPill], child, transport:[TransportAction], statusLeft, statusRight, onStop, footer, enableShortcuts, showCountdown, onCountdownComplete). TransportColors.play/stop/replay.
- AudioPort.playWav(Uint8List)+stop(); SilentAudioPort (tests), JustAudioPort (real). Pages take AudioPort? default SilentAudioPort().
- pcm_synth.dart: tone(seconds,freqHz,amp,fadeMs), whiteNoise(seconds,amp,seed), amNoise, silence, concat, mixAtSnr, encodeWav16, encodeWavStereo16, decodeWav16, modulationDepthLinear, shiftSemitones, rms. kSampleRate=48000.
- AdaptiveTrack(value,min,max,step,...).submit(bool)->value; .threshold,.thresholdSd,.complete,.reversals. Named ctors .snr/.gap/.modulation/.frequency.
- TrialRecord(target,response,correct,latencyMs,replays,parameters). ProtocolMode from core/speech_in_noise.dart.
- Session pattern: moduleId,groupId,records[],submit(),isComplete,accuracy,threshold; page onCompleted(session).
- Safety: never raise master volume; amplitude cap <=0.7 for LDL.
- Home: _maybeOpenPreview() switch (?preview=); kTrainingModules list + _launchTraining(index) switch; IndexedStack tabs + NavigationBar; _persistRun(moduleId,groupId,mode,records); _pushPage(page).
- SessionRecord in data/session_history.dart (add synced bool). SessionHistory load/add/clear.
- Api in data/api.dart (http). RemoteSyncPage _syncNow snackbar; keys: sync-now-button, pending-sessions-value, clinician-code-field.
- OpenSetPage(itemPool, itemBuilder, ...) needs pool selector. EnhancedReportPage(tests:[ReportTest]) add Export FHIR btn.
- web/manifest.json needs start_url '/tan/', name/short_name.

## Tasks & status
T3-1 cloud_sync.dart + SessionRecord.synced + wire RemoteSync  : DONE
T3-2 core/fhir_export.dart + Export FHIR btn on report          : DONE
T3-3 web/manifest.json + install_prompt.dart + Settings btn     : DONE
T3-4 tools/generate_multilang.py + config json + README         : DONE
T3-5 core/word_lists.dart + OpenSetPage selector + launcher     : DONE
T4-1 core/tinnitus/pitch_match.dart + page                      : DONE
T4-2 core/tinnitus/loudness_match.dart + page                   : DONE
T4-3 core/tinnitus/mml.dart + page                              : DONE
T4-4 features/tinnitus/sound_therapy_page.dart                  : DONE
T4-5 core/tinnitus/ldl.dart + page (amp cap 0.7)                : DONE
T4-6 core/training/phonological.dart + page (3 games)           : DONE
T4-7 core/training/scene_training.dart + page (3 scenes)        : DONE
T4-8 core/training/interhemispheric.dart + page                 : DONE
T4-9 features/training/speech_tracking_page.dart                : DONE
T4-10 core/training/sentence_closure.dart + page                : DONE
INT wire home_page (previews+training+tinnitus tab+nav)         : DONE
VERIFY dart analyze / flutter test / build web / deploy         : ALL DONE

## FINAL VERIFICATION (evidence)
- dart analyze lib -> EXIT 0 (no errors/warnings; only pre-existing info lints)
- flutter test -> "All tests passed!" 309 tests (was 278; +31 new), EXIT 0
- flutter build web --base-href '/tan/' -> "Built build\web", EXIT 0
- gh-pages deploy -> "gh-pages -> gh-pages (forced update)", PUSH_EXIT:0 to github.com/aman123825/tan.git
- Reminder: delete **/ephemeral before every flutter invocation (OneDrive regenerates it)

## Notes
- NavigationBar -> 6 tabs: Home/Tests/Training/Tinnitus/Report/Settings. Update _viewReport (was index 3) and settings icon (was 4).
- Added test file: test/tier3_4_test.dart
