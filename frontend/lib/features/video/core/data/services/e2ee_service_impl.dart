import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:vayug/core/interfaces/i_e2ee_service.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/exceptions/app_exceptions.dart';

/// Concrete implementation of IE2eeService for Vayug.
/// Handles RSA key generation, storage, and E2EE key distribution/chunk operations.
class E2eeServiceImpl implements IE2eeService {
  final FlutterSecureStorage _secureStorage;
  static const String _privateKeyStorageKey = 'e2ee_private_key';
  static const String _publicKeyStorageKey = 'e2ee_public_key';

  E2eeServiceImpl({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
        );

  // ─────────────────────────────────────────────────
  // CRYPTOGRAPHIC HELPER FUNCTIONS
  // ─────────────────────────────────────────────────

  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _generateRSAKeyPair() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
      pair.publicKey as RSAPublicKey,
      pair.privateKey as RSAPrivateKey,
    );
  }

  Uint8List _rsaEncrypt(RSAPublicKey myPublic, Uint8List data) {
    final encryptor = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(myPublic));
    return encryptor.process(data);
  }

  Uint8List _rsaDecrypt(RSAPrivateKey myPrivate, Uint8List cipherText) {
    final decryptor = OAEPEncoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(myPrivate));
    return decryptor.process(cipherText);
  }

  String _serializePublicKey(RSAPublicKey key) {
    return jsonEncode({
      'modulus': key.modulus.toString(),
      'exponent': key.exponent.toString(),
    });
  }

  RSAPublicKey _deserializePublicKey(String publicKeyStr) {
    final map = jsonDecode(publicKeyStr);
    final modulus = BigInt.parse(map['modulus']);
    final exponent = BigInt.parse(map['exponent']);
    return RSAPublicKey(modulus, exponent);
  }

  String _serializePrivateKey(RSAPrivateKey key) {
    return jsonEncode({
      'modulus': key.modulus.toString(),
      'privateExponent': key.privateExponent.toString(),
      'p': key.p.toString(),
      'q': key.q.toString(),
    });
  }

  RSAPrivateKey _deserializePrivateKey(String privateKeyStr) {
    final map = jsonDecode(privateKeyStr);
    final modulus = BigInt.parse(map['modulus']);
    final privateExponent = BigInt.parse(map['privateExponent']);
    final p = BigInt.parse(map['p']);
    final q = BigInt.parse(map['q']);
    return RSAPrivateKey(modulus, privateExponent, p, q);
  }

  // ─────────────────────────────────────────────────
  // KEY PAIR MANAGEMENT
  // ─────────────────────────────────────────────────

  @override
  Future<String> generateAndStoreKeyPair() async {
    try {
      AppLogger.log('🔐 E2EE: Generating new RSA key pair...');
      final pair = _generateRSAKeyPair();
      
      final pubStr = _serializePublicKey(pair.publicKey);
      final privStr = _serializePrivateKey(pair.privateKey);

      await _secureStorage.write(key: _publicKeyStorageKey, value: pubStr);
      await _secureStorage.write(key: _privateKeyStorageKey, value: privStr);

      AppLogger.log('🔐 E2EE: Key pair successfully stored in Secure Storage.');
      return pubStr;
    } catch (e) {
      AppLogger.log('❌ E2EE: Error generating/storing key pair: $e');
      rethrow;
    }
  }

  @override
  Future<String?> getPublicKey() async {
    return await _secureStorage.read(key: _publicKeyStorageKey);
  }

  @override
  Future<bool> uploadPublicKey(String publicKey) async {
    try {
      AppLogger.log('🔐 E2EE: Uploading public key to backend...');
      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.apiBaseUrl}/e2ee/public-key'),
        body: {'publicKey': publicKey},
      );

      if (response.statusCode == 200) {
        AppLogger.log('✅ E2EE: Public key uploaded successfully.');
        return true;
      } else {
        AppLogger.log('❌ E2EE: Failed to upload public key. Status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      AppLogger.log('❌ E2EE: Network error uploading public key: $e');
      return false;
    }
  }

  @override
  Future<bool> hasKeyPair() async {
    final pubKey = await getPublicKey();
    return pubKey != null && pubKey.isNotEmpty;
  }


  @override
  Uint8List generateSymmetricKey() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  @override
  Future<Uint8List> encryptChunk(Uint8List chunk, Uint8List symmetricKey) async {
    try {
      // AES-CBC requires IV (16 bytes)
      final iv = Uint8List.fromList(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
      
      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      )..init(
          true,
          PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, CipherParameters?>(
            ParametersWithIV<KeyParameter>(KeyParameter(symmetricKey), iv),
            null,
          ),
        );

      final encrypted = cipher.process(chunk);

      // Append IV to the beginning of the encrypted payload: [IV (16 bytes)] + [Encrypted Chunk]
      final result = Uint8List(iv.length + encrypted.length);
      result.setAll(0, iv);
      result.setAll(iv.length, encrypted);

      return result;
    } catch (e) {
      AppLogger.log('❌ E2EE: Error encrypting chunk: $e');
      rethrow;
    }
  }

  @override
  Future<String> encryptSymmetricKeyForSubscriber(
    Uint8List symmetricKey,
    String subscriberPublicKey,
  ) async {
    try {
      final pubKey = _deserializePublicKey(subscriberPublicKey);
      final encryptedBytes = _rsaEncrypt(pubKey, symmetricKey);
      return base64Encode(encryptedBytes);
    } catch (e) {
      AppLogger.log('❌ E2EE: Error encrypting symmetric key for subscriber: $e');
      rethrow;
    }
  }

  @override
  Future<List<SubscriberKeyInfo>> fetchSubscriberPublicKeys() async {
    try {
      AppLogger.log('🔐 E2EE: Fetching subscriber public keys...');
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/e2ee/subscribers-keys'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['subscribers'] as List;
        return list.map((item) => SubscriberKeyInfo(
          subscriberId: item['subscriberId'] as String,
          publicKey: item['publicKey'] as String,
        )).toList();
      } else {
        AppLogger.log('❌ E2EE: Failed to fetch subscriber keys: ${response.statusCode}');
        throw Exception('Failed to fetch subscriber public keys');
      }
    } catch (e) {
      AppLogger.log('❌ E2EE: Error fetching subscriber keys: $e');
      rethrow;
    }
  }

  @override
  Future<bool> uploadEncryptedVideoKeys({
    required String videoId,
    required List<EncryptedKeyEntry> encryptedKeys,
  }) async {
    try {
      AppLogger.log('🔐 E2EE: Uploading ${encryptedKeys.length} encrypted keys for video $videoId...');
      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.apiBaseUrl}/e2ee/video-keys'),
        body: {
          'videoId': videoId,
          'keys': encryptedKeys.map((e) => e.toJson()).toList(),
        },
      );

      if (response.statusCode == 200) {
        AppLogger.log('✅ E2EE: Encrypted video keys uploaded successfully.');
        return true;
      } else {
        AppLogger.log('❌ E2EE: Failed to upload encrypted video keys: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      AppLogger.log('❌ E2EE: Error uploading encrypted video keys: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────
  // VIDEO DECRYPTION (Subscriber Side)
  // ─────────────────────────────────────────────────

  @override
  Future<String?> fetchEncryptedVideoKey(String videoId) async {
    try {
      // AuthService clears the JWT on sign-out, but an already-running
      // preload can still reach this method after that happens.
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) {
        throw const E2eeVideoAccessException(
          'Please sign in to watch this encrypted video.',
          code: 'authentication_required',
        );
      }
      AppLogger.log('🔐 E2EE: Fetching encrypted video key for $videoId...');
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/e2ee/video-key/$videoId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['hasAccess'] == true) {
          final encryptedKey = data['encryptedSymmetricKey'];
          if (encryptedKey is String && encryptedKey.isNotEmpty) {
            return encryptedKey;
          }
          throw const E2eeVideoAccessException(
            'The decryption key for this video is unavailable.',
            code: 'key_unavailable',
          );
        }
      }
      final serverMessage = _readErrorMessage(response.body);
      if (response.statusCode == 401 || response.statusCode == 404) {
        throw E2eeVideoAccessException(
          'Please sign in again to watch this encrypted video.',
          code: 'authentication_required',
          details: response.statusCode,
        );
      }
      if (response.statusCode == 403) {
        throw E2eeVideoAccessException(
          serverMessage ?? 'You do not have access to this encrypted video.',
          code: 'access_denied',
          details: response.statusCode,
        );
      }
      throw E2eeVideoAccessException(
        serverMessage ?? 'The encrypted video is temporarily unavailable.',
        code: response.statusCode >= 500 ? 'server_error' : 'key_unavailable',
        details: response.statusCode,
      );
    } on E2eeVideoAccessException {
      rethrow;
    } catch (e) {
      AppLogger.log('❌ E2EE: Error fetching encrypted video key: $e');
      throw E2eeVideoAccessException(
        'The encrypted video could not be prepared. Please try again.',
        code: 'network_error',
        details: e,
      );
    }
  }

  String? _readErrorMessage(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['error'] ?? decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      // Keep the exception message user-safe when the server response is not JSON.
    }
    return null;
  }

  @override
  Future<Uint8List> decryptSymmetricKey(String encryptedSymmetricKey) async {
    try {
      final privKeyStr = await _secureStorage.read(key: _privateKeyStorageKey);
      if (privKeyStr == null) {
        throw const E2eeVideoAccessException(
          'This device does not have the encryption key needed for this video.',
          code: 'device_key_missing',
        );
      }
      final privKey = _deserializePrivateKey(privKeyStr);
      final encryptedBytes = base64Decode(encryptedSymmetricKey);
      return _rsaDecrypt(privKey, encryptedBytes);
    } catch (e) {
      if (e is E2eeVideoAccessException) rethrow;
      AppLogger.log('❌ E2EE: Error decrypting symmetric key: $e');
      throw E2eeVideoAccessException(
        'This device encryption key does not match the key used for this video. '
        'Try the original device or contact support.',
        code: 'device_key_changed',
        details: e,
      );
    }
  }

  @override
  Future<Uint8List> decryptChunk(Uint8List encryptedChunk, Uint8List symmetricKey) async {
    try {
      if (encryptedChunk.length < 16) {
        throw Exception('Invalid encrypted chunk: too short');
      }

      return await Isolate.run(() {
        // Extract IV (first 16 bytes)
        final iv = encryptedChunk.sublist(0, 16);
        final ciphertext = encryptedChunk.sublist(16);

        final cipher = PaddedBlockCipherImpl(
          PKCS7Padding(),
          CBCBlockCipher(AESEngine()),
        )..init(
            false,
            PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, CipherParameters?>(
              ParametersWithIV<KeyParameter>(KeyParameter(symmetricKey), iv),
              null,
            ),
          );

        return cipher.process(ciphertext);
      });
    } catch (e) {
      AppLogger.log('❌ E2EE: Error decrypting chunk: $e');
      rethrow;
    }
  }
}
