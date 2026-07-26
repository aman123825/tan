/// Phoneme feature-error analysis (pure Dart, Flutter-free).
///
/// Given a confusion matrix from a vowel/consonant identification run, this
/// classifies each consonant confusion by the single distinctive feature that
/// changed — voicing (b↔p), place of articulation (b↔d) or manner (t↔s,
/// m↔b) — and summarizes where errors concentrate:
///
///   "Primary deficit: voicing distinctions (42% of errors).
///    Place-of-articulation intact."
///
/// This is a research summary, not a diagnosis.
library;

import 'confusion_matrix.dart';

/// The distinctive feature that changed in a confusion.
enum PhonemeFeatureError { voicing, place, manner, mixed }

/// A consonant's three-way phonetic description.
class Phone {
  const Phone(this.id, this.voiced, this.place, this.manner);

  final String id;
  final bool voiced;
  final String place;
  final String manner;
}

/// English-consonant feature table (voicing / place / manner). Digraph ids
/// (sh, ch, th, dh, ng, zh, jh) cover the common orthographic clusters.
const Map<String, Phone> kPhonemeFeatures = <String, Phone>{
  'b': Phone('b', true, 'bilabial', 'stop'),
  'p': Phone('p', false, 'bilabial', 'stop'),
  'd': Phone('d', true, 'alveolar', 'stop'),
  't': Phone('t', false, 'alveolar', 'stop'),
  'g': Phone('g', true, 'velar', 'stop'),
  'k': Phone('k', false, 'velar', 'stop'),
  'm': Phone('m', true, 'bilabial', 'nasal'),
  'n': Phone('n', true, 'alveolar', 'nasal'),
  'ng': Phone('ng', true, 'velar', 'nasal'),
  'f': Phone('f', false, 'labiodental', 'fricative'),
  'v': Phone('v', true, 'labiodental', 'fricative'),
  'th': Phone('th', false, 'dental', 'fricative'),
  'dh': Phone('dh', true, 'dental', 'fricative'),
  's': Phone('s', false, 'alveolar', 'fricative'),
  'z': Phone('z', true, 'alveolar', 'fricative'),
  'sh': Phone('sh', false, 'postalveolar', 'fricative'),
  'zh': Phone('zh', true, 'postalveolar', 'fricative'),
  'ch': Phone('ch', false, 'postalveolar', 'affricate'),
  'jh': Phone('jh', true, 'postalveolar', 'affricate'),
  'h': Phone('h', false, 'glottal', 'fricative'),
  'l': Phone('l', true, 'alveolar', 'liquid'),
  'r': Phone('r', true, 'postalveolar', 'liquid'),
  'w': Phone('w', true, 'bilabial', 'glide'),
  'y': Phone('y', true, 'palatal', 'glide'),
};

/// Extracts a consonant id from a token label (e.g. "ba" → b, "sha" → sh,
/// "P" → p). Returns null when no known onset consonant is found.
String? phoneIdFromToken(String token) {
  final t = token.trim().toLowerCase();
  if (t.isEmpty) return null;
  const digraphs = <String>['sh', 'ch', 'th', 'ng', 'zh', 'dh', 'jh'];
  for (final d in digraphs) {
    if (t.startsWith(d)) return d;
  }
  final first = t[0];
  // Map a few orthographic onsets to feature ids.
  const onset = <String, String>{'j': 'jh', 'y': 'y'};
  final id = onset[first] ?? first;
  return kPhonemeFeatures.containsKey(id) ? id : null;
}

/// Classifies a single confusion by the distinctive feature that changed.
/// Returns null when either token isn't a recognized consonant.
PhonemeFeatureError? classifyConfusion(String target, String response) {
  final a = kPhonemeFeatures[phoneIdFromToken(target) ?? ''];
  final b = kPhonemeFeatures[phoneIdFromToken(response) ?? ''];
  if (a == null || b == null || a.id == b.id) return null;
  final dV = a.voiced != b.voiced;
  final dP = a.place != b.place;
  final dM = a.manner != b.manner;
  final diffs = (dV ? 1 : 0) + (dP ? 1 : 0) + (dM ? 1 : 0);
  if (diffs == 1) {
    if (dV) return PhonemeFeatureError.voicing;
    if (dP) return PhonemeFeatureError.place;
    return PhonemeFeatureError.manner;
  }
  return PhonemeFeatureError.mixed;
}

/// The tallied result of a phoneme feature-error analysis.
class PhonemeErrorAnalysis {
  PhonemeErrorAnalysis({
    required this.voicing,
    required this.place,
    required this.manner,
    required this.mixed,
    required this.unclassified,
  });

  final int voicing;
  final int place;
  final int manner;
  final int mixed;

  /// Errors whose tokens weren't recognized consonants (excluded from %).
  final int unclassified;

  /// Builds the analysis from a list of [ConfusionPair]s (off-diagonal only).
  factory PhonemeErrorAnalysis.fromConfusions(Iterable<ConfusionPair> pairs) {
    var v = 0, p = 0, m = 0, x = 0, u = 0;
    for (final pair in pairs) {
      final kind = classifyConfusion(pair.target, pair.response);
      switch (kind) {
        case PhonemeFeatureError.voicing:
          v += pair.count;
        case PhonemeFeatureError.place:
          p += pair.count;
        case PhonemeFeatureError.manner:
          m += pair.count;
        case PhonemeFeatureError.mixed:
          x += pair.count;
        case null:
          u += pair.count;
      }
    }
    return PhonemeErrorAnalysis(
        voicing: v, place: p, manner: m, mixed: x, unclassified: u);
  }

  /// Builds the analysis directly from a [ConfusionMatrix] (uses every
  /// off-diagonal confusion, not just the top few).
  factory PhonemeErrorAnalysis.fromMatrix(ConfusionMatrix matrix) {
    final pairs = <ConfusionPair>[];
    for (final entry in matrix.counts.entries) {
      final target = entry.key;
      for (final resp in entry.value.entries) {
        if (resp.key == target) continue; // diagonal = correct
        pairs.add(ConfusionPair(target, resp.key, resp.value));
      }
    }
    return PhonemeErrorAnalysis.fromConfusions(pairs);
  }

  /// Total feature-classified errors (voicing + place + manner + mixed).
  int get classifiedTotal => voicing + place + manner + mixed;

  /// Count for a single feature category.
  int countFor(PhonemeFeatureError e) => switch (e) {
        PhonemeFeatureError.voicing => voicing,
        PhonemeFeatureError.place => place,
        PhonemeFeatureError.manner => manner,
        PhonemeFeatureError.mixed => mixed,
      };

  /// Percentage (0..100) of classified errors in category [e].
  double percentFor(PhonemeFeatureError e) =>
      classifiedTotal == 0 ? 0 : countFor(e) / classifiedTotal * 100;

  static String _label(PhonemeFeatureError e) => switch (e) {
        PhonemeFeatureError.voicing => 'voicing',
        PhonemeFeatureError.place => 'place-of-articulation',
        PhonemeFeatureError.manner => 'manner-of-articulation',
        PhonemeFeatureError.mixed => 'mixed-feature',
      };

  static String _intactLabel(PhonemeFeatureError e) => switch (e) {
        PhonemeFeatureError.voicing => 'Voicing intact.',
        PhonemeFeatureError.place => 'Place-of-articulation intact.',
        PhonemeFeatureError.manner => 'Manner-of-articulation intact.',
        PhonemeFeatureError.mixed => '',
      };

  /// A human-readable text summary, e.g.:
  /// "Primary deficit: voicing distinctions (42% of errors).
  ///  Place-of-articulation intact."
  ///
  /// [intactThreshold] is the percentage below which a dimension is reported
  /// as intact.
  String summary({double intactThreshold = 15}) {
    if (classifiedTotal == 0) {
      return 'No systematic phoneme feature errors detected'
          '${unclassified > 0 ? ' (errors were not consonant confusions)' : ''}.';
    }
    const dims = <PhonemeFeatureError>[
      PhonemeFeatureError.voicing,
      PhonemeFeatureError.place,
      PhonemeFeatureError.manner,
    ];
    // Primary deficit is the single feature with the most errors.
    var primary = dims.first;
    for (final d in dims) {
      if (countFor(d) > countFor(primary)) primary = d;
    }
    final b = StringBuffer();
    b.write('Primary deficit: ${_label(primary)} distinctions '
        '(${percentFor(primary).round()}% of errors).');
    // Note any dimension that is essentially intact.
    for (final d in dims) {
      if (d == primary) continue;
      if (percentFor(d) <= intactThreshold) {
        b.write(' ${_intactLabel(d)}');
      }
    }
    if (mixed > 0) {
      b.write(' ${percentFor(PhonemeFeatureError.mixed).round()}% of errors '
          'crossed multiple features.');
    }
    return b.toString();
  }
}
