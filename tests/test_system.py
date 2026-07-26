import json,os,tempfile
from pathlib import Path
os.environ['HEARBLOOM_DB']=str(Path(tempfile.gettempdir())/'hearbloom_test.db')
from fastapi.testclient import TestClient
from services.api.main import app,DB
from packages.protocol_engine.engine import snr_staircase,Score,Trial
from ml.recommender import recommend

def test_catalog():
 c=json.loads(Path('protocols/catalog.json').read_text());assert len(c['modules'])==9;assert sum(len(m['groups']) for m in c['modules'])==56

def test_staircase_and_score():
 s=snr_staircase();assert s.submit(True)==12;assert s.submit(True)==10;assert s.submit(False)==12;assert s.reversals==[10]
 score=Score();[score.add(Trial('a','a' if i%2==0 else 'b',i%2==0,500)) for i in range(20)];assert score.accuracy==.5;assert score.confusion()['a']['b']==10

def test_recommender():
 r=recommend([]);assert r['group_id']=='sentence_noise';assert 'reason' in r

def test_api_flow():
 if DB.exists():DB.unlink()
 c=TestClient(app);assert c.get('/health').status_code==200
 p=c.post('/profiles',json={'diagnoses':['ANSD','CAPD']}).json();s=c.post('/sessions',json={'profile_id':p['id'],'output_device':'wired_headphones'}).json()
 t={'session_id':s['id'],'module_id':'noise','group_id':'sentence_noise','mode':'training','target':'one','response':'one','correct':True,'latency_ms':900}
 assert c.post('/trials',json=t).status_code==200;assert c.post(f"/sessions/{s['id']}/end",json={'fatigue_after':3}).status_code==200
 assert c.get(f"/profiles/{p['id']}/results").json()['total_trials']==1
