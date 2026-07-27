import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin HTTP client for the HearBloom research API.
///
/// [postTrial] intentionally matches the `TrialQueue.flush` sender signature
/// (`Future<bool> Function(Map<String,dynamic>)`) so the offline queue can sync
/// directly through it.
class Api {
  Api({
    this.baseUrl = 'http://127.0.0.1:8000',
    this.timeout = const Duration(seconds: 8),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  static const Map<String, String> _jsonHeaders = {
    'content-type': 'application/json',
  };

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<http.Response> _get(
    String path, {
    Map<String, String>? headers,
  }) =>
      _client.get(_u(path), headers: headers).timeout(timeout);

  Future<http.Response> _post(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _client.post(_u(path), headers: headers, body: body).timeout(timeout);

  Future<http.Response> _delete(
    String path, {
    Map<String, String>? headers,
  }) =>
      _client.delete(_u(path), headers: headers).timeout(timeout);

  Future<Map<String, dynamic>> health() async {
    final r = await _get('/health');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> catalog() async {
    final r = await _get('/catalog');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createProfile(Map<String, dynamic> body) async {
    final r = await _post(
      '/profiles',
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createSession(Map<String, dynamic> body) async {
    final r = await _post(
      '/sessions',
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Posts a single trial. Returns true on HTTP 200 so it can be used directly
  /// as the [TrialQueue.flush] sender.
  Future<bool> postTrial(Map<String, dynamic> payload) async {
    final r = await _post(
      '/trials',
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );
    return r.statusCode == 200;
  }

  /// Uploads a batch of completed session-history records under a linked
  /// clinician code. Returns true on HTTP 2xx. Network / server errors throw
  /// (the caller treats a throw or false as "stay offline, keep queued").
  Future<bool> postSessions(
    String clinicianCode,
    List<Map<String, dynamic>> sessions,
  ) async {
    final r = await _post(
      '/sync/sessions',
      headers: _jsonHeaders,
      body: jsonEncode(<String, dynamic>{
        'clinician_code': clinicianCode,
        'sessions': sessions,
      }),
    );
    return r.statusCode >= 200 && r.statusCode < 300;
  }

  Future<Map<String, dynamic>> endSession(
    String sessionId,
    int fatigueAfter,
  ) async {
    final r = await _post(
      '/sessions/$sessionId/end',
      headers: _jsonHeaders,
      body: jsonEncode({'fatigue_after': fatigueAfter}),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> results(String profileId) async {
    final r = await _get('/profiles/$profileId/results');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> recommendation(String profileId) async {
    final r = await _get('/profiles/$profileId/recommendation');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Content-pack manifest (SHA-256 hashes, versions, retired versions).
  Future<Map<String, dynamic>> contentManifest() async {
    final r = await _get('/content/manifest');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Structured JSON export (profile + sessions + trials).
  Future<Map<String, dynamic>> exportJson(String profileId) async {
    final r = await _get('/profiles/$profileId/export.json');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// CSV export of all trials for a profile (returns the raw CSV text).
  Future<String> exportCsv(String profileId) async {
    final r = await _get('/profiles/$profileId/export.csv');
    return r.body;
  }

  /// Records a clinician review of a session (annotation only).
  Future<Map<String, dynamic>> reviewSession(
    String sessionId, {
    required String reviewedBy,
    String status = 'approved',
    String note = '',
  }) async {
    final r = await _post(
      '/sessions/$sessionId/review',
      headers: _jsonHeaders,
      body: jsonEncode({
        'reviewed_by': reviewedBy,
        'status': status,
        'note': note,
      }),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // --- Accounts, consent & erasure (J5/J8) ---------------------------------

  Map<String, String> _authHeaders(String token) => <String, String>{
        ..._jsonHeaders,
        'authorization': 'Bearer $token',
      };

  /// Registers an account; returns `{id, email, token}`. Throws on non-200
  /// with the server's message so the UI can show it.
  Future<Map<String, dynamic>> register(String email, String password) =>
      _account('/accounts/register', email, password);

  /// Logs in; returns `{id, email, token}`.
  Future<Map<String, dynamic>> login(String email, String password) =>
      _account('/accounts/login', email, password);

  Future<Map<String, dynamic>> _account(
      String path, String email, String password) async {
    final r = await _post(
      path,
      headers: _jsonHeaders,
      body: jsonEncode({'email': email, 'password': password}),
    );
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, body['detail']?.toString() ?? r.body);
    }
    return body;
  }

  /// The calling account + its linked profile ids.
  Future<Map<String, dynamic>> me(String token) async {
    final r = await _get('/accounts/me', headers: _authHeaders(token));
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, 'not signed in');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Attaches an anonymous profile to the calling account (idempotent).
  Future<bool> linkProfile(String profileId, String token) async {
    final r = await _post(
      '/profiles/$profileId/link',
      headers: _authHeaders(token),
    );
    return r.statusCode == 200;
  }

  /// Records research consent (or its withdrawal) on a profile.
  Future<Map<String, dynamic>> recordConsent(
    String profileId, {
    required bool consented,
    required String consentVersion,
  }) async {
    final r = await _post(
      '/profiles/$profileId/consent',
      headers: _jsonHeaders,
      body: jsonEncode(
          {'consented': consented, 'consent_version': consentVersion}),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Right-to-erasure: deletes the profile and all its sessions/trials.
  Future<bool> deleteProfile(String profileId, {String? token}) async {
    final r = await _delete(
      '/profiles/$profileId',
      headers: token == null ? _jsonHeaders : _authHeaders(token),
    );
    return r.statusCode == 200;
  }

  void close() => _client.close();
}

/// Non-200 API response with the server's detail message.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
