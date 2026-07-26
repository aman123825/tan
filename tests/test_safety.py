import json
from pathlib import Path

def test_research_status_and_workflow():
 c=json.loads(Path('protocols/catalog.json').read_text());assert c['status']=='research_specification'
 for m in c['modules']:
  for g in m['groups']:
   assert g['validation_status']=='unvalidated'
   assert g['modes']==['introduction','preview','training','test','results']

def test_no_auto_volume_configuration():
 text=Path('services/api/main.py').read_text();assert "'auto_volume':False" in text;assert "'absolute_thresholds':False" in text
