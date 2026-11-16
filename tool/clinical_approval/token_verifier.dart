import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'approval.dart';

/// Trusted server configuration supplies Google Secure Token JWKs, never requests.
/// Verifies RS256 before reading admin claims. No emulator unsigned-token bypass.
class TokenVerifier {
  TokenVerifier(this.project, this.loadKeys, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final String project;
  final Future<List<Map<String, dynamic>>> Function() loadKeys;
  final DateTime Function() now;
  Future<String> admin(String token) async {
    try {
      if (token.length > 16000) throw const FormatException();
      final parts = token.split('.');
      if (parts.length != 3) throw const FormatException();
      final header = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
      ) as Map;
      if (header['alg'] != 'RS256' || header['kid'] is! String) {
        throw const FormatException();
      }
      final keys = await loadKeys();
      final key = keys.singleWhere(
        (k) => k['kid'] == header['kid'] && k['kty'] == 'RSA',
      );
      final modulus = _integer(_decode(key['n'] as String));
      final exponent = _integer(_decode(key['e'] as String));
      final bytes = (modulus.bitLength + 7) ~/ 8;
      final signature = _decode(parts[2]);
      if (bytes < 256 ||
          signature.length != bytes ||
          exponent < BigInt.from(3)) {
        throw const FormatException();
      }
      final integer = _integer(signature);
      if (integer >= modulus) throw const FormatException();
      final encoded = integer
          .modPow(exponent, modulus)
          .toRadixString(16)
          .padLeft(bytes * 2, '0');
      const prefix = '3031300d060960864801650304020105000420';
      final digest = sha256
          .convert(utf8.encode('${parts[0]}.${parts[1]}'))
          .toString();
      final tail = '$prefix$digest';
      final expected = '0001${'ff' * (bytes - tail.length ~/ 2 - 3)}00$tail';
      if (encoded != expected) throw const FormatException();
      final claims = jsonDecode(utf8.decode(_decode(parts[1]))) as Map;
      final seconds = now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (claims['aud'] != project ||
          claims['iss'] != 'https://securetoken.google.com/$project' ||
          claims['sub'] is! String ||
          (claims['sub'] as String).isEmpty ||
          (claims['sub'] as String).length > 128 ||
          claims['exp'] is! int ||
          claims['exp'] <= seconds ||
          claims['iat'] is! int ||
          claims['iat'] > seconds ||
          claims['auth_time'] is! int ||
          claims['auth_time'] > seconds ||
          claims['admin'] != true) {
        throw const FormatException();
      }
      return claims['sub'] as String;
    } catch (_) {
      throw const ApprovalRejected('UNAUTHORIZED');
    }
  }

  static Uint8List _decode(String s) =>
      base64Url.decode(base64Url.normalize(s));
  static BigInt _integer(List<int> bytes) => BigInt.parse(
    bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join(),
    radix: 16,
  );
}
