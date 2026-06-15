import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/features/video/core/data/services/e2ee_service_impl.dart';

void main() {
  test('E2EE Isolate Decryption Test', () async {
    final e2ee = E2eeServiceImpl();
    
    // 1. Generate a random symmetric key (32 bytes)
    final symmetricKey = e2ee.generateSymmetricKey();
    expect(symmetricKey.length, 32);

    // 2. Create some sample plaintext data
    final plaintext = Uint8List.fromList(List<int>.generate(100, (i) => i % 256));

    // 3. Encrypt the chunk
    final encryptedChunk = await e2ee.encryptChunk(plaintext, symmetricKey);
    expect(encryptedChunk.length, greaterThan(16)); // IV (16) + ciphertext

    // 4. Decrypt the chunk
    final decrypted = await e2ee.decryptChunk(encryptedChunk, symmetricKey);

    // 5. Verify the plaintext matches
    expect(decrypted, equals(plaintext));
    print('✅ E2EE Isolate Decryption verification passed!');
  });
}
