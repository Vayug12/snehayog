import 'dart:typed_data';

/// Contract for E2EE (End-to-End Encryption) operations.
///
/// This interface defines the cryptographic operations needed for
/// subscriber-only video encryption. Implementations can be swapped
/// (e.g., from AES-GCM to ChaCha20) without touching any other code.
///
/// **Architecture**: Follows the same decoupled plug-play pattern as
/// IVideoUploadService, IDubbingService, etc.
abstract class IE2eeService {
  // ─────────────────────────────────────────────────
  // KEY PAIR MANAGEMENT (One-time setup per device)
  // ─────────────────────────────────────────────────

  /// Generates an asymmetric key pair (Ed25519/X25519) and stores
  /// the private key securely on the device.
  /// Returns the public key as a Base64 string.
  Future<String> generateAndStoreKeyPair();

  /// Retrieves the stored public key for this device.
  /// Returns null if no key pair has been generated yet.
  Future<String?> getPublicKey();

  /// Uploads the public key to the Vayug backend.
  Future<bool> uploadPublicKey(String publicKey);

  /// Checks if a key pair already exists on this device.
  Future<bool> hasKeyPair();

  // ─────────────────────────────────────────────────
  // VIDEO ENCRYPTION (Creator Side)
  // ─────────────────────────────────────────────────

  /// Generates a random symmetric key (AES-256) for encrypting a video.
  /// Returns the key as raw bytes (Uint8List).
  Uint8List generateSymmetricKey();

  /// Encrypts a video file chunk using the symmetric key.
  /// Returns the encrypted bytes.
  Future<Uint8List> encryptChunk(Uint8List chunk, Uint8List symmetricKey);

  /// Encrypts the symmetric video key with a subscriber's public key.
  /// Returns the encrypted key as a Base64 string.
  Future<String> encryptSymmetricKeyForSubscriber(
    Uint8List symmetricKey,
    String subscriberPublicKey,
  );

  /// Fetches all subscribers' public keys from the backend.
  Future<List<SubscriberKeyInfo>> fetchSubscriberPublicKeys();

  /// Uploads the encrypted symmetric keys for all subscribers to the backend.
  Future<bool> uploadEncryptedVideoKeys({
    required String videoId,
    required List<EncryptedKeyEntry> encryptedKeys,
  });

  // ─────────────────────────────────────────────────
  // VIDEO DECRYPTION (Subscriber Side)
  // ─────────────────────────────────────────────────

  /// Fetches the encrypted symmetric key for a specific video.
  /// Returns null if the user doesn't have access.
  Future<String?> fetchEncryptedVideoKey(String videoId);

  /// Decrypts the symmetric video key using the device's private key.
  /// Returns the raw symmetric key bytes.
  Future<Uint8List> decryptSymmetricKey(String encryptedSymmetricKey);

  /// Decrypts a video chunk using the symmetric key.
  /// Returns the decrypted bytes.
  Future<Uint8List> decryptChunk(Uint8List encryptedChunk, Uint8List symmetricKey);
}

// ─────────────────────────────────────────────────
// DATA CLASSES (used by the interface)
// ─────────────────────────────────────────────────

/// Holds a subscriber's ID and their public key.
class SubscriberKeyInfo {
  final String subscriberId;
  final String publicKey;

  SubscriberKeyInfo({
    required this.subscriberId,
    required this.publicKey,
  });
}

/// Holds the encrypted symmetric key mapped to a specific subscriber.
class EncryptedKeyEntry {
  final String subscriberId;
  final String encryptedSymmetricKey;

  EncryptedKeyEntry({
    required this.subscriberId,
    required this.encryptedSymmetricKey,
  });

  Map<String, dynamic> toJson() => {
    'subscriberId': subscriberId,
    'encryptedSymmetricKey': encryptedSymmetricKey,
  };
}
