"""Accounts, consent and right-to-erasure endpoints (J5/J8).

All endpoints stay anonymous-capable; accounts only LINK profiles. Tokens are
HMAC-signed and expiring; passwords are PBKDF2-hashed with per-account salts.
"""
import os, tempfile
from pathlib import Path

os.environ['HEARBLOOM_DB'] = str(
    Path(tempfile.gettempdir()) / 'hearbloom_accounts_test.db')

from fastapi.testclient import TestClient  # noqa: E402
from services.api.main import (  # noqa: E402
    CONSENT_VERSION, DB, _issue_token, _verify_token, app)

c = TestClient(app)


def _fresh_db():
    if DB.exists():
        DB.unlink()


def _register(email='user@example.com', password='correct-horse-9'):
    return c.post('/accounts/register',
                  json={'email': email, 'password': password})


def test_register_login_me_flow():
    _fresh_db()
    r = _register()
    assert r.status_code == 200
    token = r.json()['token']
    # Duplicate email refused; email is normalised (case/whitespace).
    assert _register(email='  USER@Example.com ').status_code == 409
    # Wrong password → 401; right password → fresh token.
    assert c.post('/accounts/login', json={
        'email': 'user@example.com', 'password': 'wrong-password-1'
    }).status_code == 401
    login = c.post('/accounts/login', json={
        'email': 'User@example.com', 'password': 'correct-horse-9'})
    assert login.status_code == 200
    me = c.get('/accounts/me',
               headers={'Authorization': f"Bearer {login.json()['token']}"})
    assert me.status_code == 200
    assert me.json()['email'] == 'user@example.com'
    assert me.json()['profiles'] == []
    # Bad/absent tokens are rejected.
    assert c.get('/accounts/me').status_code == 401
    assert c.get('/accounts/me',
                 headers={'Authorization': f'Bearer {token}x'}).status_code == 401


def test_register_validation():
    _fresh_db()
    assert _register(email='not-an-email').status_code == 400
    assert _register(password='short').status_code == 422  # pydantic min_length


def test_token_roundtrip_and_tamper():
    tok = _issue_token('abc-123')
    assert _verify_token(tok) == 'abc-123'
    try:
        _verify_token(tok[:-2] + 'zz')
        raised = False
    except Exception:
        raised = True
    assert raised


def test_link_consent_and_profile_deletion():
    _fresh_db()
    token = _register().json()['token']
    hdr = {'Authorization': f'Bearer {token}'}
    p = c.post('/profiles', json={}).json()
    # Consent is recorded with version + timestamp inside the profile.
    consent = c.post(f"/profiles/{p['id']}/consent",
                     json={'consented': True})
    assert consent.status_code == 200
    assert consent.json()['consented'] is True
    assert consent.json()['consent_version'] == CONSENT_VERSION
    assert 'at' in consent.json()
    # Link is idempotent and appears under /accounts/me.
    assert c.post(f"/profiles/{p['id']}/link", headers=hdr).status_code == 200
    assert c.post(f"/profiles/{p['id']}/link", headers=hdr).status_code == 200
    assert c.get('/accounts/me', headers=hdr).json()['profiles'] == [p['id']]
    # A second account cannot claim or delete the linked profile.
    other = _register(email='other@example.com').json()['token']
    other_hdr = {'Authorization': f'Bearer {other}'}
    assert c.post(f"/profiles/{p['id']}/link",
                  headers=other_hdr).status_code == 403
    assert c.delete(f"/profiles/{p['id']}",
                    headers=other_hdr).status_code == 403
    # Owner deletion cascades sessions + trials.
    s = c.post('/sessions', json={'profile_id': p['id']}).json()
    t = {'session_id': s['id'], 'module_id': 'noise',
         'group_id': 'sentence_noise', 'mode': 'training', 'target': 'one',
         'response': 'one', 'correct': True, 'latency_ms': 500}
    assert c.post('/trials', json=t).status_code == 200
    d = c.delete(f"/profiles/{p['id']}", headers=hdr)
    assert d.status_code == 200
    assert d.json()['sessions_deleted'] == 1
    assert d.json()['trials_deleted'] == 1
    assert c.get(f"/profiles/{p['id']}/results").json()['total_trials'] == 0


def test_anonymous_profile_deletable_by_id():
    _fresh_db()
    p = c.post('/profiles', json={}).json()
    assert c.delete(f"/profiles/{p['id']}").status_code == 200
    assert c.delete(f"/profiles/{p['id']}").status_code == 404


def test_delete_account_cascades_everything():
    _fresh_db()
    token = _register().json()['token']
    hdr = {'Authorization': f'Bearer {token}'}
    p = c.post('/profiles', json={}).json()
    c.post(f"/profiles/{p['id']}/link", headers=hdr)
    s = c.post('/sessions', json={'profile_id': p['id']}).json()
    t = {'session_id': s['id'], 'module_id': 'noise',
         'group_id': 'sentence_noise', 'mode': 'training', 'target': 'one',
         'response': 'one', 'correct': True, 'latency_ms': 500}
    c.post('/trials', json=t)
    d = c.delete('/accounts/me', headers=hdr)
    assert d.status_code == 200
    assert d.json() == {'deleted': True, 'account_id': d.json()['account_id'],
                        'profiles_deleted': 1, 'sessions_deleted': 1,
                        'trials_deleted': 1}
    # Token now points at a deleted account.
    assert c.get('/accounts/me', headers=hdr).status_code == 401
