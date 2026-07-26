import json,sys,wave
from pathlib import Path
ROOT=Path(__file__).parents[1];sys.path.insert(0,str(ROOT))
from packages.protocol_engine.engine import snr_staircase,gap_staircase,Score,Trial
from ml.recommender import recommend
checks=[]
def ok(name,value):
 checks.append((name,bool(value)));assert value,name
c=json.loads((ROOT/'protocols/catalog.json').read_text());ok('nine modules',len(c['modules'])==9);ok('56 explicit groups',sum(len(m['groups']) for m in c['modules'])==56)
ok('five workflow states',all(g['modes']==['introduction','preview','training','test','results'] for m in c['modules'] for g in m['groups']))
s=snr_staircase();ok('2-down no move',s.submit(True)==12);ok('2-down harder',s.submit(True)==10);ok('1-up easier',s.submit(False)==12);ok('reversal recorded',s.reversals==[10])
g=gap_staircase();ok('gap bounds',g.minimum==.5 and g.maximum==100)
score=Score();[score.add(Trial('a','a' if i%2==0 else 'b',i%2==0,500)) for i in range(20)];ok('accuracy',score.accuracy==.5);ok('confusion matrix',score.confusion()['a']['b']==10)
r=recommend([]);ok('explainable recommendation',r['group_id']=='sentence_noise' and bool(r['reason']))
manifest=json.loads((ROOT/'stimuli/demo/manifest.json').read_text());ok('generated psychoacoustic stimuli',len(manifest)>=26)
for x in manifest:
 if x['file'].endswith('.wav'):
  with wave.open(str(ROOT/'stimuli/demo'/x['file'])) as w:ok('48k '+x['file'],w.getframerate()==48000 and w.getnchannels()==1)
api=(ROOT/'services/api/main.py').read_text();ok('no auto volume',"'auto_volume':False" in api);ok('research only',"'research_only':True" in api)
print(f'PASS {len(checks)}/{len(checks)} checks')
