/// Version lineage stamped onto every trial event (pure Dart).
///
/// Kept in sync with the backend defaults in `services/api/main.py`
/// (TrialIn.app_version / protocol_version / stimulus_version). Every stored
/// trial carries these so results are always attributable to an exact app,
/// protocol and stimulus build — a research-integrity requirement from the
/// KIRO handoff ("Store app, protocol, stimulus ... versions with every
/// trial").
library;

/// Application build version.
const String kAppVersion = '0.1.0';

/// Deterministic protocol-engine/spec version. Assessment scoring is immutable
/// within a released protocol version.
const String kProtocolVersion = '1.0.0';

/// Stimulus content-pack version. Generated demo speech remains `demo-*` until
/// linguist/audiologist review.
const String kStimulusVersion = 'demo-0.1';
