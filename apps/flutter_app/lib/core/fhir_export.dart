/// FHIR R4 Observation export (pure Dart, no Flutter / no plugin).
///
/// Turns HearBloom research test results into HL7 FHIR R4 `Observation`
/// resources and a `Bundle` (type `collection`) that any FHIR-compliant EHR can
/// import. Kept dependency-free so it can be unit-tested headlessly and reused
/// from the report page.
///
/// IMPORTANT: These are research measurements taken on uncalibrated audio — the
/// exported resources are for interoperability/demonstration and are NOT a
/// clinical diagnosis. LOINC codes are best-effort mappings to the nearest
/// audiological concept; where no close code exists a generic audiology code is
/// used and the human-readable test name is always carried in `code.text`.
library;

/// The LOINC system URI.
const String kLoincSystem = 'http://loinc.org';

/// UCUM (Unified Code for Units of Measure) system URI — used for
/// `valueQuantity.system`.
const String kUcumSystem = 'http://unitsofmeasure.org';

/// HL7 observation-interpretation code system.
const String kInterpretationSystem =
    'http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation';

/// A single measured result to export as one FHIR `Observation`.
class FhirObservationInput {
  const FhirObservationInput({
    required this.testName,
    required this.value,
    required this.unit,
    this.ear = '—',
    this.interpretation,
    this.loincCode,
    this.loincDisplay,
    this.status = 'final',
    this.note,
  });

  /// Human-readable test name (always placed in `code.text`).
  final String testName;

  /// Numeric measured value, or null if it could not be parsed (a
  /// `valueString` is emitted instead so nothing is lost).
  final num? value;

  /// Unit string (e.g. `ms`, `dB`, `%`). Empty when unitless.
  final String unit;

  /// "Left", "Right", "Both", or "—" (not ear-specific). Non-"—" ears are
  /// emitted as an ear-specific `component`.
  final String ear;

  /// Optional interpretation label, e.g. "Normal" / "Below" / "Borderline".
  final String? interpretation;

  /// Optional explicit LOINC code; when null it is looked up from [testName].
  final String? loincCode;

  /// Optional explicit LOINC display; when null it is looked up from [testName].
  final String? loincDisplay;

  /// FHIR observation status (default `final`).
  final String status;

  /// Optional free-text annotation.
  final String? note;
}

/// A best-effort LOINC coding for a HearBloom test name.
class LoincCoding {
  const LoincCoding(this.code, this.display);
  final String code;
  final String display;
}

/// Maps a HearBloom test name to the nearest LOINC coding. Falls back to a
/// generic audiology-study code (`28621-3`, "Audiology study") so every
/// observation still carries a coded concept; the exact test is always in
/// `code.text`.
LoincCoding loincForTest(String testName) {
  final n = testName.toLowerCase();
  if (n.contains('gap')) {
    // Temporal resolution / gap detection.
    return const LoincCoding('80289-6', 'Auditory temporal resolution');
  }
  if (n.contains('dichotic')) {
    return const LoincCoding('80290-4', 'Dichotic listening');
  }
  if (n.contains('phoneme') || n.contains('word recognition')) {
    return const LoincCoding('79319-4', 'Speech recognition');
  }
  if (n.contains('noise') || n.contains('snr') || n.contains('sin')) {
    return const LoincCoding('100904-2', 'Speech in noise');
  }
  if (n.contains('pattern') || n.contains('duration') || n.contains('pitch')) {
    return const LoincCoding('80291-2', 'Auditory pattern / temporal ordering');
  }
  if (n.contains('digit span') || n.contains('memory')) {
    return const LoincCoding('72133-2', 'Auditory memory / digit span');
  }
  if (n.contains('tinnitus') && n.contains('pitch')) {
    return const LoincCoding('101321-8', 'Tinnitus pitch match');
  }
  if (n.contains('tinnitus') && n.contains('loud')) {
    return const LoincCoding('101322-6', 'Tinnitus loudness match');
  }
  if (n.contains('masking')) {
    return const LoincCoding('101323-4', 'Minimum masking level');
  }
  if (n.contains('loudness discomfort') || n.contains('ldl') ||
      n.contains('uncomfortable')) {
    return const LoincCoding('101324-2', 'Loudness discomfort level');
  }
  return const LoincCoding('28621-3', 'Audiology study');
}

/// HL7 interpretation coding (code + display) for a human label.
Map<String, String>? _interpretationCoding(String? label) {
  if (label == null) return null;
  final l = label.toLowerCase();
  if (l.startsWith('norm')) return {'code': 'N', 'display': 'Normal'};
  if (l.startsWith('below') || l.startsWith('abnorm') || l.startsWith('low')) {
    return {'code': 'A', 'display': 'Abnormal'};
  }
  if (l.startsWith('border') || l.startsWith('inter')) {
    return {'code': 'I', 'display': 'Intermediate'};
  }
  return {'code': 'IND', 'display': label};
}

/// A parsed numeric value + unit from a display string like `"7.5 ms"`,
/// `"+1.2 dB"`, `"78%"`, or `"5 digits"`.
class ParsedScore {
  const ParsedScore(this.value, this.unit);
  final num? value;
  final String unit;
}

/// Extracts the leading (optionally signed/decimal) number and trailing unit
/// from a score string. Returns a null value when no number is present.
ParsedScore parseScore(String score) {
  final m = RegExp(r'([+-]?\d+(?:\.\d+)?)\s*(.*)$').firstMatch(score.trim());
  if (m == null) return ParsedScore(null, score.trim());
  final value = num.tryParse(m.group(1)!);
  var unit = (m.group(2) ?? '').trim();
  if (unit == '%') unit = '%';
  return ParsedScore(value, unit);
}

/// UCUM code for a display unit (best-effort). Empty units map to `1`.
String _ucumCode(String unit) {
  switch (unit.trim()) {
    case '%':
      return '%';
    case 'dB':
    case 'dB SNR':
    case 'dB SL':
    case 'dB HL':
      return 'dB';
    case 'ms':
      return 'ms';
    case 'Hz':
      return 'Hz';
    case '':
      return '1';
    default:
      return unit.trim();
  }
}

/// Builds a single FHIR R4 `Observation` resource as a JSON-ready map.
Map<String, dynamic> fhirObservation(
  FhirObservationInput input, {
  DateTime? effective,
  String patientName = '(patient name)',
}) {
  final coding = (input.loincCode != null)
      ? LoincCoding(input.loincCode!, input.loincDisplay ?? input.testName)
      : loincForTest(input.testName);
  final ts = (effective ?? DateTime.now()).toUtc().toIso8601String();

  final obs = <String, dynamic>{
    'resourceType': 'Observation',
    'status': input.status,
    'category': <dynamic>[
      {
        'coding': <dynamic>[
          {
            'system':
                'http://terminology.hl7.org/CodeSystem/observation-category',
            'code': 'exam',
            'display': 'Exam',
          }
        ],
      }
    ],
    'code': <String, dynamic>{
      'coding': <dynamic>[
        {
          'system': kLoincSystem,
          'code': coding.code,
          'display': coding.display,
        }
      ],
      'text': input.testName,
    },
    'effectiveDateTime': ts,
    'subject': <String, dynamic>{'display': patientName},
  };

  // Value: quantity when numeric, otherwise a value string so nothing is lost.
  if (input.value != null) {
    obs['valueQuantity'] = <String, dynamic>{
      'value': input.value,
      'unit': input.unit.isEmpty ? '1' : input.unit,
      'system': kUcumSystem,
      'code': _ucumCode(input.unit),
    };
  } else {
    obs['valueString'] = input.unit.isEmpty ? input.testName : input.unit;
  }

  // Ear-specific component (Left / Right / Both).
  if (input.ear.isNotEmpty && input.ear != '—') {
    final earComponent = <String, dynamic>{
      'code': <String, dynamic>{
        'coding': <dynamic>[
          {
            'system': 'http://snomed.info/sct',
            'code': _earSnomed(input.ear),
            'display': '${input.ear} ear',
          }
        ],
        'text': '${input.ear} ear',
      },
    };
    if (input.value != null) {
      earComponent['valueQuantity'] = <String, dynamic>{
        'value': input.value,
        'unit': input.unit.isEmpty ? '1' : input.unit,
        'system': kUcumSystem,
        'code': _ucumCode(input.unit),
      };
    } else {
      earComponent['valueString'] = input.ear;
    }
    obs['component'] = <dynamic>[earComponent];
  }

  final interp = _interpretationCoding(input.interpretation);
  if (interp != null) {
    obs['interpretation'] = <dynamic>[
      {
        'coding': <dynamic>[
          {
            'system': kInterpretationSystem,
            'code': interp['code'],
            'display': interp['display'],
          }
        ],
        'text': input.interpretation,
      }
    ];
  }

  if (input.note != null && input.note!.isNotEmpty) {
    obs['note'] = <dynamic>[
      {'text': input.note}
    ];
  }

  return obs;
}

/// SNOMED CT laterality-ish code for an ear label (best-effort).
String _earSnomed(String ear) {
  switch (ear.toLowerCase()) {
    case 'left':
      return '7771000'; // Left (qualifier value)
    case 'right':
      return '24028007'; // Right (qualifier value)
    case 'both':
      return '51440002'; // Right and left (qualifier value)
    default:
      return '261665006'; // Unknown (qualifier value)
  }
}

/// Builds a FHIR R4 `Bundle` (type `collection`) wrapping one `Observation`
/// per input. Every FHIR-compliant system can ingest a collection bundle.
Map<String, dynamic> fhirBundle(
  List<FhirObservationInput> inputs, {
  DateTime? effective,
  String patientName = '(patient name)',
}) {
  final ts = (effective ?? DateTime.now()).toUtc().toIso8601String();
  return <String, dynamic>{
    'resourceType': 'Bundle',
    'type': 'collection',
    'timestamp': ts,
    'entry': <dynamic>[
      for (final input in inputs)
        {
          'resource': fhirObservation(
            input,
            effective: effective,
            patientName: patientName,
          ),
        }
    ],
  };
}
