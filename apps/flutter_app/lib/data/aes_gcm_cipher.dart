import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../core/trial_queue.dart';

/// AES-GCM-256 [QueueCipher] for encrypting local records at rest.
///
/// Each [encrypt] uses a fresh random nonce; the serialized envelope carries
/// the nonce, ciphertext and authentication tag (MAC). GCM is authenticated,
/// so tampering with the stored bytes fails decryption rather than yielding
/// garbage. The 32-byte key is supplied by the caller (in production, from
/// platform secure storage — never hard-coded).
class AesGcmQueueCipher implements QueueCipher {
  AesGcmQueueCipher(List<int> keyBytes)
      : assert(keyBytes.length == 32, 'AES-256 requires a 32-byte key'),
        _secretKey = SecretKey(keyBytes);

  final SecretKey _secretKey;
  final AesGcm _algorithm = AesGcm.with256bits();

  @override
  Future<String> encrypt(String plaintext) async {
    final box = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: _secretKey,
    );
    return jsonEncode(<String, String>{
      'v': '1',
      'n': base64.encode(box.nonce),
      'c': base64.encode(box.cipherText),
      'm': base64.encode(box.mac.bytes),
    });
  }

  @override
  Future<String> decrypt(String ciphertext) async {
    final envelope = jsonDecode(ciphertext) as Map<String, dynamic>;
    final box = SecretBox(
      base64.decode(envelope['c'] as String),
      nonce: base64.decode(envelope['n'] as String),
      mac: Mac(base64.decode(envelope['m'] as String)),
    );
    final clear = await _algorithm.decrypt(box, secretKey: _secretKey);
    return utf8.decode(clear);
  }
}
