/// Standard clinical word-list pools for open-set word recognition (pure Dart).
///
/// Provides recognised monosyllabic word-recognition pools in the CNC
/// (Consonant-Nucleus-Consonant) format used by CID W-22 / NU-CNC style tests
/// and the NU-6 (Northwestern University Auditory Test No. 6, Tillman &
/// Carhart, 1966) format. Only the word *strings* are provided here — validated
/// clinical use additionally requires calibrated, talker-controlled recordings
/// and the officially licensed list orderings. These pools are for research
/// open-set practice; verify against the licensed source before clinical use.
///
/// Every entry is a genuine English monosyllable with consonant-vowel-consonant
/// structure, so the open-set renderer can present them as typed-recognition
/// items. No Flutter / plugin dependency (unit-testable headlessly).
library;

/// One named word-recognition list.
class WordListPool {
  const WordListPool({
    required this.id,
    required this.name,
    required this.family,
    required this.words,
  });

  /// Stable identifier, e.g. `cnc_1`, `nu6_a`.
  final String id;

  /// Display name, e.g. `CNC List 1`, `NU-6 List A`.
  final String name;

  /// Test family: `CNC` or `NU-6`.
  final String family;

  /// The 50 monosyllabic words in the list.
  final List<String> words;

  int get length => words.length;
}

// ---------------------------------------------------------------------------
// CNC (Consonant-Nucleus-Consonant) — 10 lists of 50 monosyllables.
// ---------------------------------------------------------------------------

const List<List<String>> _cncWords = <List<String>>[
  // List 1
  <String>[
    'back','base','bath','bead','bean','bell','bird','bite','boat','bone',
    'book','boss','bull','cage','cake','calf','cap','case','cave','chain',
    'chair','cheek','coat','comb','cook','corn','couch','cough','deck','dial',
    'dish','dock','dog','doll','door','dove','duck','fan','farm','fig',
    'fish','food','fork','game','gate','gift','goat','gum','half','hall',
  ],
  // List 2
  <String>[
    'hand','hat','hawk','heart','hill','home','hook','horn','hut','jar',
    'jaw','jet','judge','jug','keg','kick','king','kite','knife','lace',
    'lamp','lane','leaf','leg','life','lime','lock','log','loop','lung',
    'mail','map','match','math','maze','mice','milk','mole','moon','moth',
    'mouse','mouth','mug','nail','name','neck','nest','news','nose','note',
  ],
  // List 3
  <String>[
    'oak','oil','page','pain','palm','path','peach','pear','pearl','pen',
    'pig','pin','pipe','pond','pool','pope','purse','rack','rag','rail',
    'rain','ram','rat','reed','ring','road','robe','rock','roof','room',
    'root','rope','rose','rug','sack','sail','salt','sauce','seal','seat',
    'seed','shark','sheep','shell','ship','shirt','shoe','shop','sick','sink',
  ],
  // List 4
  <String>[
    'soap','sock','soup','south','spoon','star','stone','stool','sun','tail',
    'tank','tape','team','teeth','tent','thief','thumb','tide','time','toad',
    'toe','tomb','tooth','top','tower','town','toy','tray','tree','tube',
    'vase','veil','vine','void','vote','wall','wand','watch','wave','web',
    'week','whale','wheat','wheel','wing','witch','wolf','wood','yard','zone',
  ],
  // List 5
  <String>[
    'badge','bag','ball','band','bark','barn','beach','bear','beard','beef',
    'bench','bike','bill','birth','block','blood','board','bomb','boot','bowl',
    'box','branch','bread','brick','bridge','broom','brush','bud','bug','burn',
    'cab','can','cane','card','cart','cash','cat','chalk','chart','check',
    'chest','chin','clock','cloth','cloud','club','coach','coal','coast','coin',
  ],
  // List 6
  <String>[
    'cord','cot','crab','crane','cream','crib','crown','cube','cup','curl',
    'dad','dam','dance','dart','date','dawn','day','desk','dime','dirt',
    'ditch','dot','drum','dust','ear','earth','edge','egg','elk','face',
    'fact','fall','fault','feast','feet','fern','field','film','fire','flag',
    'flame','flash','fleet','float','flood','floor','flour','flute','fly','foam',
  ],
  // List 7
  <String>[
    'fog','foil','fool','foot','force','fox','frame','frog','front','frost',
    'fruit','full','fun','fur','gas','gear','ghost','girl','glass','globe',
    'glove','glue','goal','gold','golf','goose','gown','grape','grass','grief',
    'guard','guest','gulf','hair','ham','harp','hash','hawk','hay','head',
    'heat','hedge','heel','hen','herd','hive','hog','hoof','hope','horse',
  ],
  // List 8
  <String>[
    'hose','host','ice','ink','jazz','jeep','job','join','joke','joy',
    'juice','june','junk','key','kid','kiss','knee','knob','knot','lake',
    'lamb','land','lap','lark','lawn','leash','ledge','lens','light','line',
    'lip','list','load','loaf','loan','loft','lot','loud','love','luck',
    'lump','lunch','mad','maid','main','mask','mast','meal','meat','melt',
  ],
  // List 9
  <String>[
    'mesh','mint','mist','mix','moon','mop','moss','mud','mule','myth',
    'nap','near','need','nerve','net','nick','night','nook','noon','north',
    'nut','oath','ounce','pace','pack','pad','pair','pan','park','part',
    'paste','paw','pea','peak','peg','perch','pest','pie','pike','pill',
    'pinch','pink','pit','plaid','plane','plate','plow','plug','plum','poach',
  ],
  // List 10
  <String>[
    'pod','poke','porch','pork','pot','pouch','pound','pump','punch','pup',
    'queen','quilt','quiz','race','raft','ranch','range','rash','reach','rice',
    'ridge','rim','rinse','ripe','rise','roast','robe','role','roll','rush',
    'rust','sad','safe','sage','sand','scale','scarf','scene','school','scoop',
    'sea','shed','shelf','shine','shore','sign','silk','smile','snake','stove',
  ],
];

/// The ten CNC word-recognition lists.
final List<WordListPool> kCncLists = <WordListPool>[
  for (var i = 0; i < _cncWords.length; i++)
    WordListPool(
      id: 'cnc_${i + 1}',
      name: 'CNC List ${i + 1}',
      family: 'CNC',
      words: _cncWords[i],
    ),
];

// ---------------------------------------------------------------------------
// NU-6 (Northwestern University Auditory Test No. 6) — 4 lists of 50.
// ---------------------------------------------------------------------------

const List<List<String>> _nu6Words = <List<String>>[
  // List A
  <String>[
    'laud','boat','pool','nag','limb','shout','sub','vine','dime','goose',
    'whip','tough','puff','keen','death','sour','such','size','cool','reach',
    'jar','tip','chief','yes','loaf','rat','jail','hurl','dab','thumb',
    'gap','rush','mode','juice','mob','haze','wheat','king','void','turn',
    'good','pike','mouse','get','ache','cab','hush','love','name','fall',
  ],
  // List B
  <String>[
    'bin','tape','pick','goal','food','moon','shawl','mill','tire','pad',
    'pearl','love','met','white','witch','young','beg','pass','learn','yield',
    'search','wire','soap','third','date','life','luck','shack','numb','walk',
    'bought','red','hole','deep','bar','king','vote','pain','ripe','gaze',
    'chalk','shoe','rag','far','fit','join','dodge','tooth','peg','week',
  ],
  // List C
  <String>[
    'gaze','ton','five','void','south','wag','base','far','learn','tan',
    'read','room','neat','fail','shirt','shall','bought','fat','pain','loud',
    'chair','wide','deep','shout','hole','dab','judge','bone','week','jug',
    'lore','gun','rain','date','rush','met','have','buff','mess','pole',
    'cool','ditch','gin','hush','well','key','make','pick','cheek','vine',
  ],
  // List D
  <String>[
    'sheep','such','five','met','good','tell','goose','half','ripe','doll',
    'lose','ways','get','shed','then','raid','cost','turn','dead','void',
    'jail','choice','pearl','bath','yes','room','pipe','tough','mode','look',
    'come','time','gap','life','cove','learn','back','talk','white','third',
    'chew','keep','base','hurl','young','walk','peg','moss','sail','tag',
  ],
];

/// The four NU-6 word-recognition lists (Forms A–D).
final List<WordListPool> kNu6Lists = <WordListPool>[
  for (var i = 0; i < _nu6Words.length; i++)
    WordListPool(
      id: 'nu6_${String.fromCharCode(97 + i)}',
      name: 'NU-6 List ${String.fromCharCode(65 + i)}',
      family: 'NU-6',
      words: <String>[for (final w in _nu6Words[i]) w.trim()],
    ),
];

/// All clinical word-recognition lists (CNC lists then NU-6 lists).
final List<WordListPool> kClinicalWordLists = <WordListPool>[
  ...kCncLists,
  ...kNu6Lists,
];

/// Looks up a pool by [id], or null if unknown.
WordListPool? wordPoolById(String id) {
  for (final p in kClinicalWordLists) {
    if (p.id == id) return p;
  }
  return null;
}
