from __future__ import annotations
import base64, csv, hashlib, hmac, io, json, os, secrets, sqlite3, time, uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from fastapi import FastAPI, Header, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from ml.recommender import recommend
from packages.protocol_engine.engine import Score, Trial

ROOT=Path(__file__).parents[2]
DB=Path(os.getenv('HEARBLOOM_DB',ROOT/'data/hearbloom.db'))
DB.parent.mkdir(parents=True,exist_ok=True)
app=FastAPI(title='HearBloom Research API',version='0.1.0',description='Non-diagnostic auditory training research API')
# Web clients on another origin need CORS; default is permissive for research/
# dev, restrict via a comma-separated HEARBLOOM_CORS_ORIGINS in production.
app.add_middleware(CORSMiddleware,
                   allow_origins=[o.strip() for o in os.getenv('HEARBLOOM_CORS_ORIGINS','*').split(',')],
                   allow_methods=['*'],allow_headers=['*'])

SCHEMA='''
CREATE TABLE IF NOT EXISTS profiles(id TEXT PRIMARY KEY, created_at TEXT, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY, profile_id TEXT, started_at TEXT, ended_at TEXT, condition TEXT, output_device TEXT, fatigue_before INTEGER, fatigue_after INTEGER, comfortable_level REAL, reviewed_by TEXT, reviewed_at TEXT, review_status TEXT, review_note TEXT);
CREATE TABLE IF NOT EXISTS trials(id TEXT PRIMARY KEY, session_id TEXT, at TEXT, module_id TEXT, group_id TEXT, mode TEXT, target TEXT, response TEXT, correct INTEGER, latency_ms INTEGER, replay_count INTEGER, parameters TEXT, app_version TEXT, protocol_version TEXT, stimulus_version TEXT);
CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY, created_at TEXT, email TEXT UNIQUE NOT NULL, pass_salt TEXT NOT NULL, pass_hash TEXT NOT NULL);
'''
@contextmanager
def conn():
    c=sqlite3.connect(DB);c.row_factory=sqlite3.Row;c.executescript(SCHEMA)
    # Defensive migration for databases created before newer columns existed.
    cols={r[1] for r in c.execute('PRAGMA table_info(sessions)').fetchall()}
    for col,ddl in (('comfortable_level','REAL'),('reviewed_by','TEXT'),('reviewed_at','TEXT'),('review_status','TEXT'),('review_note','TEXT')):
        if col not in cols:
            c.execute(f'ALTER TABLE sessions ADD COLUMN {col} {ddl}')
    pcols={r[1] for r in c.execute('PRAGMA table_info(profiles)').fetchall()}
    if 'account_id' not in pcols:
        c.execute('ALTER TABLE profiles ADD COLUMN account_id TEXT')
    try:
        yield c
        c.commit()  # commit writes on clean exit; skipped when an exception (e.g. HTTPException) propagates
    finally:
        c.close()   # always release the file handle (Windows locks it otherwise)

def now():return datetime.now(timezone.utc).isoformat()

# --- Safety enforcement (see docs/SAFETY.md) --------------------------------
# Ear-presentation conditions are stored separately and never pooled.
ALLOWED_CONDITIONS={'binaural','left','right'}
SEPARATE_EAR_CONDITIONS={'left','right'}
# Output devices are kept separate; temporal/dichotic results are not pooled
# across them (enforced when results are aggregated).
ALLOWED_OUTPUT_DEVICES={'wired_headphones','bluetooth','speaker'}
# The five canonical protocol workflow stages a trial may belong to.
WORKFLOW_STAGES={'introduction','preview','training','test','results'}

# Current released content versions (kept in sync with TrialIn defaults and the
# Dart client's core/versions.dart).
APP_VERSION='0.1.0'
PROTOCOL_VERSION='1.0.0'
STIMULUS_VERSION='demo-0.1'
# Retired protocol versions are refused: data must not be collected under a
# withdrawn/immutable assessment version (research-integrity requirement).
RETIRED_PROTOCOL_VERSIONS={'0.0.1-alpha'}
# HMAC-SHA256 key used to sign the content manifest. Dev default; override in
# production via the HEARBLOOM_CONTENT_KEY environment variable.
CONTENT_SIGNING_KEY=os.getenv('HEARBLOOM_CONTENT_KEY','dev-content-signing-key').encode()
# Clinician review outcomes for a session (annotation only; never changes
# locked assessment scoring).
REVIEW_STATUSES={'approved','flagged','pending'}

def enforce_profile_safety(safety:dict[str,Any])->dict[str,Any]:
    """Coerce/validate the non-negotiable safety flags for a stored profile.

    auto_volume and absolute_thresholds may never be true and research_only is
    always true. An explicit unsafe request is rejected with HTTP 400.
    """
    s=dict(safety or {})
    if s.get('auto_volume') is True:
        raise HTTPException(400,'auto_volume must be false (safety invariant)')
    if s.get('absolute_thresholds') is True:
        raise HTTPException(400,'absolute_thresholds must be false; home audio never reports dB HL')
    s['auto_volume']=False
    s['absolute_thresholds']=False
    s['research_only']=True
    s.setdefault('separate_ear_approved',False)
    return s
class Profile(BaseModel):
    id:str|None=None
    locale:str='en-IN'
    conditions:list[str]=Field(default_factory=lambda:['binaural'])
    diagnoses:list[str]=Field(default_factory=list)
    primary_goal:str='speech_in_noise'
    safety:dict[str,Any]=Field(default_factory=lambda:{'auto_volume':False,'absolute_thresholds':False,'research_only':True})
class SessionIn(BaseModel):
    profile_id:str; condition:str='binaural'; output_device:str='wired_headphones'; fatigue_before:int=Field(ge=0,le=10,default=0)
    comfortable_level:float|None=Field(default=None,ge=0.0,le=1.0)
class TrialIn(BaseModel):
    session_id:str; module_id:str=Field(min_length=1); group_id:str=Field(min_length=1); mode:str=Field(min_length=1)
    target:str; response:str; correct:bool; latency_ms:int=Field(ge=0); replay_count:int=Field(ge=0,default=0)
    parameters:dict[str,Any]=Field(default_factory=dict)
    app_version:str=Field(default='0.1.0',min_length=1);protocol_version:str=Field(default='1.0.0',min_length=1);stimulus_version:str=Field(default='demo-0.1',min_length=1)
class EndIn(BaseModel):fatigue_after:int=Field(ge=0,le=10)
class ReviewIn(BaseModel):
    reviewed_by:str=Field(min_length=1); status:str='approved'; note:str=''

@app.get('/health')
def health():return {'ok':True,'research_only':True,'db':str(DB)}
@app.get('/catalog')
def catalog():return json.loads((ROOT/'protocols/catalog.json').read_text())
@app.post('/profiles')
def create_profile(p:Profile):
    pid=p.id or str(uuid.uuid4());d=p.model_dump();d['id']=pid
    d['safety']=enforce_profile_safety(d.get('safety',{}))
    with conn() as c:c.execute('INSERT INTO profiles(id,created_at,data) VALUES(?,?,?)',(pid,now(),json.dumps(d)))
    return d
@app.post('/sessions')
def create_session(s:SessionIn):
    if s.condition not in ALLOWED_CONDITIONS:
        raise HTTPException(400,f'condition must be one of {sorted(ALLOWED_CONDITIONS)}')
    if s.output_device not in ALLOWED_OUTPUT_DEVICES:
        raise HTTPException(400,f'output_device must be one of {sorted(ALLOWED_OUTPUT_DEVICES)}')
    sid=str(uuid.uuid4())
    with conn() as c:
        row=c.execute('SELECT data FROM profiles WHERE id=?',(s.profile_id,)).fetchone()
        if not row:raise HTTPException(404,'profile not found')
        # Separate-ear presentation requires explicit clinician approval.
        if s.condition in SEPARATE_EAR_CONDITIONS:
            safety=(json.loads(row['data']).get('safety') or {})
            if safety.get('separate_ear_approved') is not True:
                raise HTTPException(403,'separate-ear presentation requires clinician approval in the profile')
        c.execute('INSERT INTO sessions(id,profile_id,started_at,ended_at,condition,output_device,fatigue_before,fatigue_after,comfortable_level) VALUES(?,?,?,?,?,?,?,?,?)',(sid,s.profile_id,now(),None,s.condition,s.output_device,s.fatigue_before,None,s.comfortable_level))
    return {'id':sid,**s.model_dump()}
@app.post('/trials')
def add_trial(t:TrialIn):
    if t.mode not in WORKFLOW_STAGES:
        raise HTTPException(400,f'mode must be one of {sorted(WORKFLOW_STAGES)}')
    if t.protocol_version in RETIRED_PROTOCOL_VERSIONS:
        raise HTTPException(400,f'protocol_version {t.protocol_version} is retired')
    tid=str(uuid.uuid4())
    with conn() as c:
        if not c.execute('SELECT 1 FROM sessions WHERE id=?',(t.session_id,)).fetchone():raise HTTPException(404,'session not found')
        c.execute('INSERT INTO trials(id,session_id,at,module_id,group_id,mode,target,response,correct,latency_ms,replay_count,parameters,app_version,protocol_version,stimulus_version) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',(tid,t.session_id,now(),t.module_id,t.group_id,t.mode,t.target,t.response,int(t.correct),t.latency_ms,t.replay_count,json.dumps(t.parameters),t.app_version,t.protocol_version,t.stimulus_version))
    return {'id':tid,**t.model_dump()}
@app.post('/sessions/{sid}/end')
def end_session(sid:str,e:EndIn):
    with conn() as c:
        cur=c.execute('UPDATE sessions SET ended_at=?,fatigue_after=? WHERE id=?',(now(),e.fatigue_after,sid))
        if not cur.rowcount:raise HTTPException(404,'session not found')
    return {'id':sid,'ended':True,'fatigue_after':e.fatigue_after}
@app.post('/sessions/{sid}/review')
def review_session(sid:str,r:ReviewIn):
    """Clinician annotation of a session. Never alters trial scoring — the
    locked deterministic results are immutable; this only records a review."""
    if r.status not in REVIEW_STATUSES:
        raise HTTPException(400,f'status must be one of {sorted(REVIEW_STATUSES)}')
    with conn() as c:
        cur=c.execute('UPDATE sessions SET reviewed_by=?,reviewed_at=?,review_status=?,review_note=? WHERE id=?',(r.reviewed_by,now(),r.status,r.note,sid))
        if not cur.rowcount:raise HTTPException(404,'session not found')
        row=dict(c.execute('SELECT * FROM sessions WHERE id=?',(sid,)).fetchone())
    return row
@app.get('/profiles/{pid}/recommendation')
def recommendation(pid:str):
    with conn() as c:
        rows=[dict(r) for r in c.execute('SELECT t.*,s.fatigue_after FROM trials t JOIN sessions s ON s.id=t.session_id WHERE s.profile_id=? ORDER BY t.at',(pid,))]
    return recommend(rows)
@app.get('/profiles/{pid}/results')
def results(pid:str):
    with conn() as c:
        rows=[dict(r) for r in c.execute('SELECT t.*,s.condition,s.output_device,s.fatigue_after FROM trials t JOIN sessions s ON s.id=t.session_id WHERE s.profile_id=? ORDER BY t.at',(pid,))]
    total=len(rows);correct=sum(r['correct'] for r in rows)
    return {'total_trials':total,'accuracy':correct/total if total else None,
            'pooling_policy':'not_pooled_across_condition_or_device',
            'separated':_separate_results(rows),'trials':rows}

def _summarize(rows:list[dict])->dict:
    """Reuses the deterministic engine's Score for accuracy + reliability."""
    score=Score()
    for r in rows:
        score.add(Trial(r['target'],r['response'],bool(r['correct']),r['latency_ms'],r.get('replay_count') or 0))
    n=len(rows)
    return {'n':n,
            'accuracy':score.accuracy if n else None,
            'mean_latency_ms':(sum(r['latency_ms'] for r in rows)/n) if n else None,
            'reliability':score.reliability()}

def _separate_results(rows:list[dict])->list[dict]:
    """Buckets trials by (condition, output_device, module, group, mode).

    SAFETY: results are never pooled across ear-condition or output device —
    temporal/dichotic thresholds must not mix wired/Bluetooth/speaker or
    left/right/binaural. Training and test modes are also kept separate.
    """
    buckets:dict[tuple,list[dict]]={}
    for r in rows:
        key=(r.get('condition'),r.get('output_device'),r['module_id'],r['group_id'],r['mode'])
        buckets.setdefault(key,[]).append(r)
    out=[]
    for (cond,dev,mod,grp,mode),rs in buckets.items():
        out.append({'condition':cond,'output_device':dev,'module_id':mod,'group_id':grp,'mode':mode,**_summarize(rs)})
    out.sort(key=lambda x:(str(x['condition']),str(x['output_device']),x['module_id'],x['group_id'],x['mode']))
    return out



# --- Content integrity & export (KIRO handoff #9, #10) ----------------------
def _file_digest(path:Path)->dict:
    data=path.read_bytes()
    return {'file':str(path.relative_to(ROOT)).replace('\\','/'),
            'sha256':hashlib.sha256(data).hexdigest(),
            'bytes':len(data)}

def _sign_manifest(payload:dict)->str:
    """HMAC-SHA256 over a canonical JSON serialization of [payload]."""
    canonical=json.dumps(payload,sort_keys=True,separators=(',',':')).encode()
    return hmac.new(CONTENT_SIGNING_KEY,canonical,hashlib.sha256).hexdigest()

@app.get('/content/manifest')
def content_manifest():
    """Content-pack manifest: SHA-256 file hashes + versions + retired versions,
    plus an HMAC-SHA256 signature over the whole manifest so a client can verify
    integrity and authenticity of its bundled content pack."""
    files={'catalog':_file_digest(ROOT/'protocols/catalog.json')}
    stim=ROOT/'stimuli/demo/manifest.json'
    if stim.exists():
        files['stimulus_manifest']=_file_digest(stim)
    manifest={'research_only':True,
              'app_version':APP_VERSION,
              'protocol_version':PROTOCOL_VERSION,
              'stimulus_version':STIMULUS_VERSION,
              'retired_protocol_versions':sorted(RETIRED_PROTOCOL_VERSIONS),
              'files':files,
              'signature_algorithm':'HMAC-SHA256'}
    # Sign everything except the signature field itself.
    manifest['signature']=_sign_manifest(manifest)
    return manifest

EXPORT_COLUMNS=['at','session_id','condition','output_device','module_id','group_id','mode','target','response','correct','latency_ms','replay_count','parameters','app_version','protocol_version','stimulus_version']

@app.get('/profiles/{pid}/export.json')
def export_json(pid:str):
    with conn() as c:
        prow=c.execute('SELECT data FROM profiles WHERE id=?',(pid,)).fetchone()
        if not prow:raise HTTPException(404,'profile not found')
        sessions=[dict(r) for r in c.execute('SELECT * FROM sessions WHERE profile_id=? ORDER BY started_at',(pid,))]
        trials=[dict(r) for r in c.execute('SELECT t.*,s.condition,s.output_device FROM trials t JOIN sessions s ON s.id=t.session_id WHERE s.profile_id=? ORDER BY t.at',(pid,))]
    return {'research_only':True,'exported_at':now(),'profile':json.loads(prow['data']),
            'sessions':sessions,'trials':trials}

@app.get('/profiles/{pid}/export.csv')
def export_csv(pid:str):
    with conn() as c:
        if not c.execute('SELECT 1 FROM profiles WHERE id=?',(pid,)).fetchone():raise HTTPException(404,'profile not found')
        rows=[dict(r) for r in c.execute('SELECT t.*,s.condition,s.output_device FROM trials t JOIN sessions s ON s.id=t.session_id WHERE s.profile_id=? ORDER BY t.at',(pid,))]
    buf=io.StringIO();w=csv.DictWriter(buf,fieldnames=EXPORT_COLUMNS,extrasaction='ignore');w.writeheader()
    for r in rows:w.writerow({k:r.get(k) for k in EXPORT_COLUMNS})
    return Response(content=buf.getvalue(),media_type='text/csv',
                    headers={'Content-Disposition':f'attachment; filename="hearbloom_{pid}.csv"'})

# --- Accounts, consent & deletion (J5 / J8) ---------------------------------
# Opt-in accounts: every existing endpoint stays anonymous-capable; an account
# only LINKS profiles so they can be found again and deleted together.
# Stdlib crypto only: PBKDF2-HMAC-SHA256 passwords, HMAC-signed expiring
# bearer tokens (same signing approach as the content manifest).
AUTH_KEY=os.getenv('HEARBLOOM_AUTH_KEY','dev-auth-signing-key').encode()
TOKEN_TTL_SECONDS=int(os.getenv('HEARBLOOM_TOKEN_TTL','2592000'))  # 30 days
PBKDF2_ITERATIONS=200_000
# Version string of the research-consent text a participant agrees to; bump
# when docs/CONSENT.md changes so stale consents are detectable.
CONSENT_VERSION='2026-07-research-v1'

def _hash_password(password:str,salt_hex:str)->str:
    return hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt_hex),PBKDF2_ITERATIONS).hex()

def _issue_token(account_id:str)->str:
    payload=f'{account_id}.{int(time.time())+TOKEN_TTL_SECONDS}'
    sig=hmac.new(AUTH_KEY,payload.encode(),hashlib.sha256).hexdigest()
    return base64.urlsafe_b64encode(payload.encode()).decode()+'.'+sig

def _verify_token(token:str)->str:
    """Returns the account id or raises 401 (bad signature / expired)."""
    try:
        payload_b64,sig=token.rsplit('.',1)
        payload=base64.urlsafe_b64decode(payload_b64.encode()).decode()
        expected=hmac.new(AUTH_KEY,payload.encode(),hashlib.sha256).hexdigest()
        if not hmac.compare_digest(sig,expected):raise ValueError('bad signature')
        account_id,expiry=payload.rsplit('.',1)
        if int(expiry)<time.time():raise ValueError('expired')
        return account_id
    except (ValueError,TypeError,IndexError):
        raise HTTPException(401,'invalid or expired token')

def _require_account(authorization:str|None)->str:
    if not authorization or not authorization.lower().startswith('bearer '):
        raise HTTPException(401,'missing bearer token')
    return _verify_token(authorization.split(' ',1)[1])

class AccountIn(BaseModel):
    email:str=Field(min_length=3,max_length=200)
    password:str=Field(min_length=8,max_length=200)
class ConsentIn(BaseModel):
    consented:bool
    consent_version:str=CONSENT_VERSION

def _norm_email(email:str)->str:
    e=email.strip().lower()
    if '@' not in e or e.startswith('@') or e.endswith('@'):
        raise HTTPException(400,'invalid email')
    return e

@app.post('/accounts/register')
def register(a:AccountIn):
    email=_norm_email(a.email)
    aid=str(uuid.uuid4());salt=secrets.token_hex(16)
    with conn() as c:
        if c.execute('SELECT 1 FROM accounts WHERE email=?',(email,)).fetchone():
            raise HTTPException(409,'an account with this email already exists')
        c.execute('INSERT INTO accounts(id,created_at,email,pass_salt,pass_hash) VALUES(?,?,?,?,?)',
                  (aid,now(),email,salt,_hash_password(a.password,salt)))
    return {'id':aid,'email':email,'token':_issue_token(aid)}

@app.post('/accounts/login')
def login(a:AccountIn):
    email=_norm_email(a.email)
    with conn() as c:
        row=c.execute('SELECT * FROM accounts WHERE email=?',(email,)).fetchone()
    # Constant-shape response path: hash even when the account is missing so
    # timing does not reveal which emails exist.
    salt=row['pass_salt'] if row else secrets.token_hex(16)
    calc=_hash_password(a.password,salt)
    if not row or not hmac.compare_digest(calc,row['pass_hash']):
        raise HTTPException(401,'wrong email or password')
    return {'id':row['id'],'email':email,'token':_issue_token(row['id'])}

@app.get('/accounts/me')
def me(authorization:str|None=Header(default=None)):
    aid=_require_account(authorization)
    with conn() as c:
        row=c.execute('SELECT id,created_at,email FROM accounts WHERE id=?',(aid,)).fetchone()
        if not row:raise HTTPException(401,'account no longer exists')
        profiles=[r['id'] for r in c.execute('SELECT id FROM profiles WHERE account_id=?',(aid,))]
    return {**dict(row),'profiles':profiles}

@app.post('/profiles/{pid}/link')
def link_profile(pid:str,authorization:str|None=Header(default=None)):
    """Attaches an anonymous profile to the calling account (idempotent)."""
    aid=_require_account(authorization)
    with conn() as c:
        row=c.execute('SELECT account_id FROM profiles WHERE id=?',(pid,)).fetchone()
        if not row:raise HTTPException(404,'profile not found')
        if row['account_id'] and row['account_id']!=aid:
            raise HTTPException(403,'profile is linked to a different account')
        c.execute('UPDATE profiles SET account_id=? WHERE id=?',(aid,pid))
    return {'profile_id':pid,'account_id':aid,'linked':True}

@app.post('/profiles/{pid}/consent')
def record_consent(pid:str,body:ConsentIn):
    """Records the participant's research consent (or its withdrawal) with a
    timestamp and the consent-text version, inside the profile document."""
    with conn() as c:
        row=c.execute('SELECT data FROM profiles WHERE id=?',(pid,)).fetchone()
        if not row:raise HTTPException(404,'profile not found')
        data=json.loads(row['data'])
        data['consent']={'consented':body.consented,'consent_version':body.consent_version,'at':now()}
        c.execute('UPDATE profiles SET data=? WHERE id=?',(json.dumps(data),pid))
    return data['consent']

@app.delete('/profiles/{pid}')
def delete_profile(pid:str,authorization:str|None=Header(default=None)):
    """Right-to-erasure: removes the profile and ALL its sessions and trials.
    An anonymous profile is deletable by anyone holding its id (the id is the
    capability); a linked profile additionally requires its account's token."""
    with conn() as c:
        row=c.execute('SELECT account_id FROM profiles WHERE id=?',(pid,)).fetchone()
        if not row:raise HTTPException(404,'profile not found')
        if row['account_id']:
            if _require_account(authorization)!=row['account_id']:
                raise HTTPException(403,'profile belongs to a different account')
        sids=[r['id'] for r in c.execute('SELECT id FROM sessions WHERE profile_id=?',(pid,))]
        trials=0
        for sid in sids:
            trials+=c.execute('DELETE FROM trials WHERE session_id=?',(sid,)).rowcount
        sessions=c.execute('DELETE FROM sessions WHERE profile_id=?',(pid,)).rowcount
        c.execute('DELETE FROM profiles WHERE id=?',(pid,))
    return {'deleted':True,'profile_id':pid,'sessions_deleted':sessions,'trials_deleted':trials}

@app.delete('/accounts/me')
def delete_account(authorization:str|None=Header(default=None)):
    """Deletes the account AND every linked profile with all its data."""
    aid=_require_account(authorization)
    with conn() as c:
        pids=[r['id'] for r in c.execute('SELECT id FROM profiles WHERE account_id=?',(aid,))]
        totals={'profiles_deleted':0,'sessions_deleted':0,'trials_deleted':0}
        for pid in pids:
            sids=[r['id'] for r in c.execute('SELECT id FROM sessions WHERE profile_id=?',(pid,))]
            for sid in sids:
                totals['trials_deleted']+=c.execute('DELETE FROM trials WHERE session_id=?',(sid,)).rowcount
            totals['sessions_deleted']+=c.execute('DELETE FROM sessions WHERE profile_id=?',(pid,)).rowcount
            totals['profiles_deleted']+=c.execute('DELETE FROM profiles WHERE id=?',(pid,)).rowcount
        deleted=c.execute('DELETE FROM accounts WHERE id=?',(aid,)).rowcount
    if not deleted:raise HTTPException(401,'account no longer exists')
    return {'deleted':True,'account_id':aid,**totals}
