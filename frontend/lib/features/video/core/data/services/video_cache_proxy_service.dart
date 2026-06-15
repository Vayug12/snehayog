import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:pointycastle/export.dart';
import 'package:vayug/shared/services/video_player_config_service.dart';

/// Tracks download progress for an E2EE video prefetch.
class E2eeDownloadProgress {
  final int downloadedBytes;
  final int? totalBytes;
  final Duration? estimatedTimeRemaining;
  final bool isComplete;

  const E2eeDownloadProgress({
    required this.downloadedBytes,
    this.totalBytes,
    this.estimatedTimeRemaining,
    this.isComplete = false,
  });

  double get fraction {
    if (totalBytes != null && totalBytes! > 0) {
      return downloadedBytes / totalBytes!;
    }
    return 0.0;
  }

  String get downloadedFormatted {
    if (downloadedBytes < 1024 * 1024) {
      return '${(downloadedBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String? get totalFormatted {
    if (totalBytes == null) return null;
    if (totalBytes! < 1024 * 1024) {
      return '${(totalBytes! / 1024).toStringAsFixed(0)} KB';
    }
    return '${(totalBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String? get estimatedTimeFormatted {
    if (estimatedTimeRemaining == null) return null;
    final seconds = estimatedTimeRemaining!.inSeconds;
    if (seconds < 60) return '~$seconds seconds';
    return '~${(seconds / 60).toStringAsFixed(0)} min';
  }
}

/// **VideoCacheProxyService: Industry-standard persistent caching**
/// Runs a local HTTP proxy to intercept video requests and serve fragments from disk.
class VideoCacheProxyService {
  static final VideoCacheProxyService _instance =
      VideoCacheProxyService._internal();
  factory VideoCacheProxyService() => _instance;
  VideoCacheProxyService._internal();

  HttpServer? _server;
  int? _port;
  String? _cachePath;
  final Map<String, http.Client> _activeDownloads = {};
  // **NEW: Track active streaming clients (requests from player)**
  final Map<String, http.Client> _activeProxyStreams = {};

  // **NEW: Performance Flags**
  bool _isLowEndDevice = false;
  int _maxCacheSizeBytes = 200 * 1024 * 1024; // Default 200MB

  // **NEW: E2EE Symmetric keys registered for decryption**
  final Map<String, Uint8List> _symmetricKeys = {};

  // **NEW: E2EE URLs that are decrypted and playable**
  final Set<String> _playableE2eeUrls = {};

  // **DOWNLOAD PROGRESS: Per-URL progress notifiers for UI feedback**
  final Map<String, ValueNotifier<E2eeDownloadProgress>> _downloadProgress = {};
  final Map<String, DateTime> _downloadStartTimes = {};

  /// Mark an E2EE video URL as decrypted and playable, protecting it from cancellation.
  void markUrlAsPlayable(String url) {
    if (url.isEmpty) return;
    _playableE2eeUrls.add(url);
    AppLogger.log('🔐 Proxy: E2EE URL marked playable and protected: $url');
  }

  /// Get the download progress notifier for a URL. Returns null if no download is tracked.
  ValueNotifier<E2eeDownloadProgress>? getDownloadProgress(String url) {
    if (url.isEmpty) return null;
    final fileKey = md5.convert(utf8.encode(url)).toString();
    return _downloadProgress[fileKey];
  }

  /// Check if an E2EE download is actively running for this URL.
  bool isDownloadActive(String url) {
    if (url.isEmpty) return false;
    final fileKey = md5.convert(utf8.encode(url)).toString();
    return _e2eeActiveDownloads.contains(fileKey);
  }

  void _updateDownloadProgress(String fileKey, int downloadedBytes, int? totalBytes) {
    final elapsed = _downloadStartTimes[fileKey] != null
        ? DateTime.now().difference(_downloadStartTimes[fileKey]!)
        : Duration.zero;

    Duration? estimatedRemaining;
    if (totalBytes != null && totalBytes > 0 && downloadedBytes > 0 && elapsed.inMilliseconds > 500) {
      final bytesPerMs = downloadedBytes / elapsed.inMilliseconds;
      final remaining = (totalBytes - downloadedBytes) / bytesPerMs;
      estimatedRemaining = Duration(milliseconds: remaining.toInt());
    }

    final progress = E2eeDownloadProgress(
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      estimatedTimeRemaining: estimatedRemaining,
    );

    _downloadProgress[fileKey]?.value = progress;
  }

  void _completeDownloadProgress(String fileKey, {bool success = true}) {
    final notifier = _downloadProgress[fileKey];
    if (notifier != null) {
      if (success) {
        final finalValue = notifier.value;
        notifier.value = E2eeDownloadProgress(
          downloadedBytes: finalValue.downloadedBytes,
          totalBytes: finalValue.totalBytes ?? finalValue.downloadedBytes,
          estimatedTimeRemaining: Duration.zero,
          isComplete: true,
        );
      }
      // Clean up after a delay so UI can read the final value
      Future.delayed(const Duration(seconds: 3), () {
        _downloadProgress.remove(fileKey);
        _downloadStartTimes.remove(fileKey);
      });
    }
  }

  // **PERSISTENT KEY STORAGE: Survives app kill**
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const String _symmetricKeysStorageKey = 'e2ee_proxy_symmetric_keys';
  bool _keysRestored = false;

  /// Synchronous guard — set before any await so concurrent player requests
  /// never delete a partial cache or start a second full download.
  final Set<String> _e2eeActiveDownloads = {};

  /// Completers that signal when enough decrypted bytes are on disk
  /// for ExoPlayer to start reading without timing out.
  final Map<String, Completer<bool>> _e2eePrebufferCompleters = {};

  /// Set of fileKeys currently being background-decrypted from .chunk → .dec
  final Set<String> _e2eeActiveDecrypts = {};

  /// Encrypted Content-Length captured from the primary CDN response.
  final Map<String, int> _e2eeEncryptedLengths = {};

  /// Decrypted plaintext length per file (exact after full decrypt, estimated before).
  final Map<String, int> _e2eePlaintextLengths = {};

  /// E2EE upload format: 2 MiB plaintext chunks, each stored as 16-byte IV + ciphertext + PKCS7.
  static const int _e2eePlainChunkSize = 2 * 1024 * 1024;
  static const int _e2eeEncChunkSize = 2097184; // 16 + 2097152 + 16 PKCS7 block

  void _recordE2eeEncryptedSize(String fileKey, int encryptedTotal) {
    _e2eeEncryptedLengths[fileKey] = encryptedTotal;
    _e2eePlaintextLengths.putIfAbsent(
      fileKey,
      () => _estimatePlainLengthFromEncrypted(encryptedTotal),
    );
  }

  void _recordE2eeExactPlainSize(String fileKey, int plainTotal) {
    _e2eePlaintextLengths[fileKey] = plainTotal;
    // Persist to disk so it survives app kill
    _persistPlainLength(fileKey, plainTotal);
  }

  Future<void> _persistPlainLength(String fileKey, int plainTotal) async {
    if (_cachePath == null) return;
    try {
      final metaFile = File('$_cachePath/$fileKey.plainlen');
      await metaFile.writeAsString(plainTotal.toString());
    } catch (_) {}
  }

  int _getE2eePlainLength(String fileKey, {int? encryptedHint}) {
    final cached = _e2eePlaintextLengths[fileKey];
    if (cached != null && cached > 0) return cached;
    final enc = encryptedHint ?? _e2eeEncryptedLengths[fileKey];
    if (enc != null) return _estimatePlainLengthFromEncrypted(enc);
    return 0;
  }

  /// Upper-bound estimate before the tail PKCS7 padding is known.
  int _estimatePlainLengthFromEncrypted(int encryptedTotal) {
    if (encryptedTotal <= 16) return 0;
    final fullChunks = encryptedTotal ~/ _e2eeEncChunkSize;
    final remainder = encryptedTotal - (fullChunks * _e2eeEncChunkSize);
    var plain = fullChunks * _e2eePlainChunkSize;
    if (remainder > 16) {
      final lastCipherBytes = remainder - 16;
      plain += lastCipherBytes > 16 ? lastCipherBytes - 16 : 0;
    }
    return plain;
  }

  void _applyE2eeFullFileHeaders(HttpResponse response, int totalPlainLength) {
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add(HttpHeaders.contentTypeHeader, 'video/mp4');
    response.headers.add(HttpHeaders.transferEncodingHeader, 'chunked');
    response.statusCode = HttpStatus.ok;
  }

  void _applyE2eeRangeHeaders(
    HttpResponse response, {
    required int startPlain,
    required int endPlain,
    required int totalPlain,
    required int bodyLength,
  }) {
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.add(HttpHeaders.contentTypeHeader, 'video/mp4');
    response.statusCode = HttpStatus.partialContent;
    response.headers.add(
      HttpHeaders.contentRangeHeader,
      'bytes $startPlain-$endPlain/$totalPlain',
    );
    response.headers.add(HttpHeaders.contentLengthHeader, bodyLength);
  }

  /// Register a symmetric key for decrypting a video on-the-fly during playback.
  /// Also persists to secure storage so the key survives app kill.
  void registerSymmetricKey(String videoId, Uint8List key) {
    _symmetricKeys[videoId] = key;
    _persistSymmetricKeys();
    AppLogger.log(
        '🔐 Proxy: Registered symmetric decryption key for video $videoId');
  }

  /// Unregister a symmetric key after playback is complete
  void unregisterSymmetricKey(String videoId) {
    _symmetricKeys.remove(videoId);
    _persistSymmetricKeys();
    AppLogger.log(
        '🔐 Proxy: Unregistered symmetric decryption key for video $videoId');
  }

  /// Persist all symmetric keys to secure storage (fire-and-forget).
  Future<void> _persistSymmetricKeys() async {
    try {
      final map = <String, String>{};
      for (final entry in _symmetricKeys.entries) {
        map[entry.key] = base64Encode(entry.value);
      }
      await _secureStorage.write(
        key: _symmetricKeysStorageKey,
        value: jsonEncode(map),
      );
    } catch (e) {
      AppLogger.log('⚠️ Proxy: Failed to persist symmetric keys: $e');
    }
  }

  /// Restore symmetric keys from secure storage on proxy startup.
  Future<void> _restoreSymmetricKeys() async {
    try {
      final raw = await _secureStorage.read(key: _symmetricKeysStorageKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      int restored = 0;
      for (final entry in map.entries) {
        if (!_symmetricKeys.containsKey(entry.key)) {
          _symmetricKeys[entry.key] = base64Decode(entry.value as String);
          restored++;
        }
      }
      if (restored > 0) {
        AppLogger.log('🔐 Proxy: Restored $restored symmetric key(s) from secure storage');
      }
      // **DIAGNOSTIC: Log full E2EE metadata restore status**
      _logE2eeMetadataRestore();
    } catch (e) {
      AppLogger.log('⚠️ Proxy: Failed to restore symmetric keys: $e');
    }
  }

  /// Restore persisted plain text lengths from disk on proxy startup.
  /// This allows accurate Content-Range headers for cached E2EE videos.
  Future<void> _restorePersistedPlainLengths() async {
    if (_cachePath == null) return;
    try {
      final dir = Directory(_cachePath!);
      if (!await dir.exists()) return;
      int restored = 0;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.plainlen')) {
          try {
            final raw = await entity.readAsString();
            final len = int.tryParse(raw);
            if (len != null && len > 0) {
              final fileKey = entity.uri.pathSegments.last.replaceAll('.plainlen', '');
              _e2eePlaintextLengths[fileKey] = len;
              restored++;
            }
          } catch (_) {}
        }
      }
      if (restored > 0) {
        AppLogger.log('🔐 Proxy: Restored $restored plain text length(s) from disk');
      }
    } catch (e) {
      AppLogger.log('⚠️ Proxy: Failed to restore plain text lengths: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIAGNOSTIC LOGGING — Collects evidence for ExoPlayer restart failures
  // ═══════════════════════════════════════════════════════════════════════════

  /// Log the incoming Range request from ExoPlayer.
  void _logIncomingRangeRequest(String tag, HttpRequest request, {String? videoId}) {
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final ifRange = request.headers.value('if-range');
    final acceptEncoding = request.headers.value('accept-encoding');
    final userAgent = request.headers.value('user-agent');
    AppLogger.log(
      '🔍 DIAG-RANGE [$tag] video=$videoId '
      'Range=${rangeHeader ?? "none"}, '
      'If-Range=${ifRange ?? "none"}, '
      'Accept-Encoding=${acceptEncoding ?? "none"}, '
      'User-Agent=${userAgent ?? "none"}',
    );
  }

  /// Log the proxy response headers sent to ExoPlayer.
  void _logResponseHeaders(
    String tag, {
    required int statusCode,
    required String videoId,
    int? contentLength,
    String? contentRange,
    String? acceptRanges,
    String? transferEncoding,
    String? contentType,
  }) {
    AppLogger.log(
      '📡 DIAG-RESP [$tag] video=$videoId '
      'STATUS=$statusCode, '
      'Content-Length=${contentLength ?? "none"}, '
      'Content-Range=${contentRange ?? "none"}, '
      'Accept-Ranges=${acceptRanges ?? "none"}, '
      'Transfer-Encoding=${transferEncoding ?? "none"}, '
      'Content-Type=${contentType ?? "none"}',
    );
  }

  /// Log cache file validation (first/last 32 bytes in hex).
  Future<void> _logCacheFileValidation(String tag, File file, {String? videoId}) async {
    try {
      if (!await file.exists()) {
        AppLogger.log('🔍 DIAG-CACHE [$tag] video=$videoId — file does not exist: ${file.path}');
        return;
      }
      final length = await file.length();
      final raf = await file.open(mode: FileMode.read);

      // First 32 bytes
      final firstBytes = await raf.read(32);
      final firstHex = firstBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

      // Last 32 bytes
      List<int> lastBytes = [];
      if (length > 32) {
        await raf.setPosition(length - 32);
        lastBytes = await raf.read(32);
      }
      await raf.close();

      final lastHex = lastBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

      AppLogger.log(
        '🔍 DIAG-CACHE [$tag] video=$videoId '
        'path=${file.path}, size=$length bytes',
      );
      AppLogger.log(
        '🔍 DIAG-CACHE [$tag] START(first32): $firstHex',
      );
      AppLogger.log(
        '🔍 DIAG-CACHE [$tag] END(last32): $lastHex',
      );

      // Check for truncation markers
      if (length == 0) {
        AppLogger.log('⚠️ DIAG-CACHE [$tag] video=$videoId — FILE IS EMPTY (0 bytes)!');
      }
    } catch (e) {
      AppLogger.log('⚠️ DIAG-CACHE [$tag] Validation failed for ${file.path}: $e');
    }
  }

  /// Log E2EE metadata restore status (lengths only, no secrets).
  void _logE2eeMetadataRestore() {
    AppLogger.log(
      '🔐 DIAG-E2EE-RESTORE: Keys restored=${_symmetricKeys.length}, '
      'keys=[${_symmetricKeys.keys.join(", ")}]',
    );
    for (final entry in _symmetricKeys.entries) {
      AppLogger.log(
        '🔐 DIAG-E2EE-RESTORE: videoId=${entry.key}, '
        'keyLength=${entry.value.length} bytes',
      );
    }
    AppLogger.log(
      '🔐 DIAG-E2EE-RESTORE: Plaintext lengths restored=${_e2eePlaintextLengths.length}, '
      'entries=${_e2eePlaintextLengths.entries.map((e) => '${e.key}=${e.value}').join(", ")}',
    );
    AppLogger.log(
      '🔐 DIAG-E2EE-RESTORE: Encrypted lengths tracked=${_e2eeEncryptedLengths.length}, '
      'entries=${_e2eeEncryptedLengths.entries.map((e) => '${e.key}=${e.value}').join(", ")}',
    );
  }

  /// Log cache metadata for all cached files (call after restart).
  Future<void> _logAllCacheMetadata() async {
    if (_cachePath == null) return;
    try {
      final dir = Directory(_cachePath!);
      if (!await dir.exists()) return;

      int chunkCount = 0;
      int decCount = 0;
      int totalChunkSize = 0;
      int totalDecSize = 0;
      int completeCount = 0;

      await for (final entity in dir.list()) {
        if (entity is File) {
          if (entity.path.endsWith('.chunk') && !entity.path.endsWith('.chunk.complete')) {
            chunkCount++;
            totalChunkSize += await entity.length();
          } else if (entity.path.endsWith('.dec') && !entity.path.endsWith('.dec.complete')) {
            decCount++;
            totalDecSize += await entity.length();
          } else if (entity.path.endsWith('.chunk.complete')) {
            completeCount++;
          }
        }
      }

      AppLogger.log(
        '🔍 DIAG-CACHE-META: chunkFiles=$chunkCount, decFiles=$decCount, '
        'completeMarkers=$completeCount, '
        'totalChunkSize=${(totalChunkSize / 1024 / 1024).toStringAsFixed(2)}MB, '
        'totalDecSize=${(totalDecSize / 1024 / 1024).toStringAsFixed(2)}MB',
      );
    } catch (e) {
      AppLogger.log('⚠️ DIAG-CACHE-META: Failed to scan cache: $e');
    }
  }

  /// Delete all cache files for a specific videoId (for cache elimination test).
  /// Returns true if cache was found and deleted.
  Future<bool> deleteCacheForVideo(String videoId) async {
    if (_cachePath == null) return false;
    bool deleted = false;

    try {
      // Unregister key
      _symmetricKeys.remove(videoId);
      _persistSymmetricKeys();

      final dir = Directory(_cachePath!);
      if (!await dir.exists()) return false;

      // Find all files matching this videoId via .vid metadata files
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.vid')) {
          try {
            final storedVideoId = (await entity.readAsString()).trim();
            if (storedVideoId == videoId) {
              // This .vid file maps to our video — delete all related files
              final basePath = entity.path.replaceAll('.vid', '');
              for (final ext in ['.chunk', '.chunk.complete', '.dec', '.dec.complete', '.plainlen']) {
                final relatedFile = File('$basePath$ext');
                if (await relatedFile.exists()) {
                  await relatedFile.delete();
                  deleted = true;
                }
              }
              await entity.delete();
            }
          } catch (_) {}
        }
      }

      // Also clean in-memory maps
      _e2eeEncryptedLengths.removeWhere((key, _) => key.contains(videoId));
      _e2eePlaintextLengths.removeWhere((key, _) => key.contains(videoId));

      AppLogger.log(
        '🗑️ DIAG-DELETE-CACHE: video=$videoId, deleted=$deleted',
      );
    } catch (e) {
      AppLogger.log('⚠️ DIAG-DELETE-CACHE: Error deleting cache for $videoId: $e');
    }

    return deleted;
  }

  /// After keys are restored, trigger background decrypt for any cached .chunk
  /// files that don't have a .dec yet. This ensures .dec is ready for instant
  /// playback on the next play.
  Future<void> _proactiveBackgroundDecrypt() async {
    if (_cachePath == null || _symmetricKeys.isEmpty) return;
    try {
      final dir = Directory(_cachePath!);
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.chunk.complete')) {
          final chunkPath = entity.path.replaceAll('.complete', '');
          final fileKey = chunkPath.split(Platform.pathSeparator).last.replaceAll('.chunk', '');
          final decComplete = File('$chunkPath.dec.complete');
          if (await decComplete.exists()) continue;
          // Read videoId from .vid metadata file
          final vidFile = File('$chunkPath.vid');
          if (await vidFile.exists()) {
            final videoId = (await vidFile.readAsString()).trim();
            if (videoId.isNotEmpty && _symmetricKeys.containsKey(videoId)) {
              _backgroundDecryptToFile(fileKey, videoId: videoId);
            }
          }
        }
      }
    } catch (e) {
      AppLogger.log('⚠️ Proxy: Proactive background decrypt scan failed: $e');
    }
  }

  /// Persist videoId alongside a .chunk file so we can restore key→file mapping
  /// on app restart for proactive background decryption.
  Future<void> _persistVideoIdMapping(String fileKey, String videoId) async {
    if (_cachePath == null) return;
    try {
      final vidFile = File('$_cachePath/$fileKey.chunk.vid');
      await vidFile.writeAsString(videoId);
    } catch (_) {}
  }

  /// Wait until at least [minBytes] of encrypted data are on disk for [url].
  /// Returns true when ready, false on timeout.
  /// ExoPlayer should only call controller.initialize() after this returns true.
  Future<bool> waitForE2eePrebuffer(
    String url, {
    int minBytes = 512 * 1024,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (url.isEmpty || _cachePath == null) return false;

    final String fileKey = md5.convert(utf8.encode(url)).toString();

    // ── FAST PATH: Fully decrypted .dec file exists → nothing to wait for.
    final decComplete = File('$_cachePath/$fileKey.dec.complete');
    final decFile = File('$_cachePath/$fileKey.dec');
    if (await decComplete.exists() && await decFile.exists()) {
      AppLogger.log('🔐 Proxy: E2EE prebuffer — .dec already complete for $fileKey');
      return true;
    }

    // Encrypted .chunk file fully downloaded → proxy can decrypt on-the-fly.
    final String chunkPath = '$_cachePath/$fileKey.chunk';
    final completeMarker = File('$chunkPath.complete');
    if (await completeMarker.exists()) {
      AppLogger.log('🔐 Proxy: E2EE prebuffer — .chunk cache already complete for $fileKey');
      return true;
    }

    // Already have enough bytes on disk from a prior or ongoing prefetch?
    final file = File(chunkPath);
    if (await file.exists()) {
      final len = await file.length();
      if (len >= minBytes) {
        AppLogger.log('🔐 Proxy: E2EE prebuffer — disk already has ${(len / 1024).toStringAsFixed(0)}KB (need ${(minBytes / 1024).toStringAsFixed(0)}KB)');
        return true;
      }
    }

    // No active download running → nothing to wait for.
    final bool downloadActive = _e2eeActiveDownloads.contains(fileKey) ||
        _activeDownloads.containsKey(chunkPath);
    if (!downloadActive) {
      AppLogger.log('🔐 Proxy: E2EE prebuffer — no active download for $fileKey');
      return false;
    }

    // Wait for the Completer that prefetchFullFile will signal.
    AppLogger.log('🔐 Proxy: E2EE prebuffer — waiting for ${(minBytes / 1024).toStringAsFixed(0)}KB on disk for $fileKey');
    final completer = _e2eePrebufferCompleters.putIfAbsent(
      fileKey,
      () => Completer<bool>(),
    );

    try {
      final result = await completer.future.timeout(timeout, onTimeout: () {
        AppLogger.log('🔐 Proxy: E2EE prebuffer — timeout after ${timeout.inSeconds}s for $fileKey');
        return false;
      });
      return result;
    } catch (_) {
      return false;
    } finally {
      _e2eePrebufferCompleters.remove(fileKey);
    }
  }

  /// Non-blocking check: has the prebuffer Completer already completed?
  bool isE2eePrebufferReady(String url) {
    if (_cachePath == null || url.isEmpty) return false;
    final fileKey = md5.convert(utf8.encode(url)).toString();
    final completer = _e2eePrebufferCompleters[fileKey];
    return completer?.isCompleted ?? false;
  }

  /// Start the local proxy server
  Future<void> initialize() async {
    AppLogger.log(
        '🚀 VideoCacheProxyService: initialize() called. Current _server status is ${_server != null ? "active" : "null"}.');
    AppLogger.log(
        '═══════════════════════════════════════════════════════════════');
    AppLogger.log(
        '🔍 DIAG-SESSION: ExoPlayer Diagnostic Session Started');
    AppLogger.log(
        '═══════════════════════════════════════════════════════════════');

    // ALWAYS restore keys first, even if server is already running.
    // This is the critical fix — keys must be available before any proxy request.
    if (!_keysRestored) {
      await _restoreSymmetricKeys();
      await _restorePersistedPlainLengths();
      _keysRestored = true;
      // Start background decrypt for any cached .chunk files that have keys
      _proactiveBackgroundDecrypt();
    }

    if (_server != null) return;

    try {
      final dir = await getApplicationSupportDirectory();
      _cachePath = '${dir.path}/video_chunks';
      AppLogger.log('🚀 VideoCacheProxyService: Cache path set to $_cachePath');
      final cacheDir = Directory(_cachePath!);
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      // **DIAGNOSTIC: Log all cache metadata on startup (post-restart)**
      await _logAllCacheMetadata();

      AppLogger.log(
          '🚀 VideoCacheProxyService: Binding to loopback on port 0...');
      // Bind to any available port on localhost
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      AppLogger.log('🚀 VideoCacheProxyService: Started on port $_port');

      _server!.listen(_handleRequest, onError: (e) {
        AppLogger.log('❌ VideoCacheProxyService: Server error callback: $e');
      });
    } catch (e, stack) {
      AppLogger.log(
          '❌ VideoCacheProxyService: Initialization failed: $e\n$stack');
    }
  }

  /// Transform a remote URL into a local proxy URL
  String proxyUrl(String originalUrl, {String? videoId}) {
    AppLogger.log(
        '📡 ProxyService: proxyUrl() invoked. url: $originalUrl, videoId: $videoId. _port status: $_port');
    if (_port == null || originalUrl.isEmpty) {
      AppLogger.log(
          '⚠️ ProxyService: Returning original URL directly because _port is null or URL is empty');
      return originalUrl;
    }

    String targetUrl = originalUrl;

    // **IP REWRITE LOGIC: Correct any old/wrong local development IPs in absolute URLs to the current baseUrl**
    if (targetUrl.startsWith('http://192.168.') ||
        targetUrl.startsWith('http://10.') ||
        targetUrl.startsWith('http://172.') ||
        targetUrl.startsWith('http://localhost:5001') ||
        targetUrl.startsWith('http://127.0.0.1:5001')) {
      final currentBase = AppConfig.baseUrl;
      try {
        final uri = Uri.parse(targetUrl);
        final currentBaseUri = Uri.parse(currentBase);
        targetUrl = uri
            .replace(
              scheme: currentBaseUri.scheme,
              host: currentBaseUri.host,
              port: currentBaseUri.port,
            )
            .toString();
        AppLogger.log(
            '🔄 ProxyService: Rewrote local development IP from ${uri.host} to ${currentBaseUri.host}');
      } catch (e) {
        AppLogger.log('⚠️ ProxyService: Failed to rewrite local IP in URL: $e');
      }
    }

    // Don't proxy if already proxied or local
    if (targetUrl.contains('127.0.0.1:$_port') ||
        targetUrl.contains('localhost:$_port') ||
        targetUrl.startsWith('file://')) {
      return targetUrl;
    }

    final encodedUrl = Uri.encodeComponent(targetUrl);

    // **HLS SUPPORT: Use special route for manifests**
    if (targetUrl.contains('.m3u8')) {
      String path = 'http://127.0.0.1:$_port/proxy-hls?url=$encodedUrl';
      if (videoId != null) path += '&videoId=$videoId';
      AppLogger.log(
          '📡 ProxyService: Translating manifest URL to proxy-hls path: $path');
      return path;
    }

    String path = 'http://127.0.0.1:$_port/proxy?url=$encodedUrl';
    if (videoId != null) path += '&videoId=$videoId';
    AppLogger.log(
        '📡 ProxyService: Translating binary URL to proxy path: $path');
    return path;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    AppLogger.log(
        '📡 Proxy: _handleRequest entry point. uri: ${request.uri.path}, query: ${request.uri.query}. _cachePath is $_cachePath');
    // **GUARD: Reject all requests if proxy not yet fully initialized**
    // Without this, _cachePath is null and File('null/hash.chunk').openWrite() crashes.
    if (_cachePath == null) {
      AppLogger.log('⚠️ Proxy: Rejecting request because _cachePath is null');
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    AppLogger.log(
        '📡 Proxy: Received request ${request.uri.path} query: ${request.uri.query}');

    // **ROUTING**
    if (request.uri.path == '/proxy-hls') {
      await _handleHlsManifestRequest(request);
      return;
    }

    if (request.uri.path != '/proxy') {
      AppLogger.log('⚠️ Proxy: Route not found ${request.uri.path}');
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final url = request.uri.queryParameters['url'];
    if (url == null || url.isEmpty) {
      AppLogger.log('⚠️ Proxy: Missing url query parameter');
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final videoId = request.uri.queryParameters['videoId'];
    final symmetricKey = videoId != null ? _symmetricKeys[videoId] : null;
    if (symmetricKey != null) {
      markUrlAsPlayable(url);
    }

    final String fileKey = md5.convert(utf8.encode(url)).toString();
    final String filePath = '$_cachePath/$fileKey.chunk';
    final file = File(filePath);

    final String? rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final _PlayerRange playerRange = _parsePlayerRange(rangeHeader);

    // **DIAGNOSTIC: Log incoming request from ExoPlayer**
    _logIncomingRangeRequest('entry', request, videoId: videoId);

    try {
      if (symmetricKey != null) {
        // **E2EE Decryption Flow**
        final completeMarker = File('${file.path}.complete');
        final isComplete = await completeMarker.exists();
        final cacheExists = await file.exists();

        // Check for pre-decrypted .dec file (fastest path — 0ms decrypt).
        final decFile = File('$_cachePath/$fileKey.dec');
        final decComplete = File('$_cachePath/$fileKey.dec.complete');
        final hasDecryptedCache = await decComplete.exists() && await decFile.exists();

        final downloadActive = _e2eeActiveDownloads.contains(fileKey) ||
            _activeProxyStreams.containsKey(fileKey);

        AppLogger.log(
          '🔐 Proxy: E2EE request for $videoId. '
          'decCache=$hasDecryptedCache, encCache=$cacheExists, complete=$isComplete, '
          'range=${rangeHeader ?? "none"}, startPlain=${playerRange.startPlain}, '
          'downloadActive=$downloadActive',
        );

        if (hasDecryptedCache) {
          // FASTEST PATH: Pre-decrypted file exists → 0ms serve.
          await _serveDecryptedStream(
            url,
            file,
            request,
            symmetricKey,
            videoId: videoId,
            fileKey: fileKey,
          );
        } else if (cacheExists && isComplete) {
          await _serveDecryptedStream(
            url,
            file,
            request,
            symmetricKey,
            videoId: videoId,
            fileKey: fileKey,
          );
        } else if (downloadActive) {
          await _serveConcurrentE2eeRequest(
            url: url,
            file: file,
            request: request,
            symmetricKey: symmetricKey,
            fileKey: fileKey,
            videoId: videoId,
            playerRange: playerRange,
          );
        } else if (playerRange.isPresent) {
          final rangeStart = await _resolveRangeStartPlain(
            playerRange,
            fileKey: fileKey,
            cacheFile: file,
          );
          AppLogger.log(
            '🔐 Proxy: E2EE range request (cache incomplete). '
            'Serving remote decrypted range from plain offset $rangeStart',
          );
          await _serveRemoteDecryptedRange(
            url,
            request,
            symmetricKey,
            rangeStart,
            playerRange.endPlain,
            videoId: videoId,
            fileKey: fileKey,
          );
        } else if (!_e2eeActiveDownloads.add(fileKey)) {
          // Atomic lost-race: another request registered the download first.
          await _serveConcurrentE2eeRequest(
            url: url,
            file: file,
            request: request,
            symmetricKey: symmetricKey,
            fileKey: fileKey,
            videoId: videoId,
            playerRange: playerRange,
          );
        } else {
          try {
            if (cacheExists && !isComplete) {
              try {
                await file.delete();
              } catch (_) {}
            }
            if (await completeMarker.exists()) {
              try {
                await completeMarker.delete();
              } catch (_) {}
            }
            await _streamCacheAndDecrypt(
              url,
              file,
              request,
              symmetricKey,
              fileKey,
              videoId: videoId,
            );
          } finally {
            _e2eeActiveDownloads.remove(fileKey);
          }
        }
      } else {
        // **Standard Non-E2EE Flow**
        final completeMarker = File('${file.path}.complete');
        final isComplete = await completeMarker.exists();

        AppLogger.log(
            '📡 Proxy: Standard request. Cache exists: ${await file.exists()}, complete: $isComplete');

        if (await file.exists() && isComplete) {
          await _serveLocalFile(file, request);
        } else {
          // Delete incomplete cache file to start fresh stream
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (_) {}
          }
          if (await completeMarker.exists()) {
            try {
              await completeMarker.delete();
            } catch (_) {}
          }
          // **Updated: Pass fileKey for tracking**
          await _streamAndCache(url, file, request, fileKey);
        }
      }
    } catch (e, stack) {
      AppLogger.log('❌ Proxy: Request handling error: $e\n$stack');
      // **DIAGNOSTIC: Log the failed URL and videoId for correlation**
      final diagVideoId = request.uri.queryParameters['videoId'] ?? 'unknown';
      final diagUrl = request.uri.queryParameters['url'] ?? 'unknown';
      AppLogger.log(
        '🔴 DIAG-FAIL: video=$diagVideoId, url=$diagUrl, '
        'errorType=${e.runtimeType}, error=$e',
        isError: true,
      );
      try {
        if (request.response.connectionInfo != null) {
          request.response.statusCode = HttpStatus.internalServerError;
        }
      } catch (_) {}
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveLocalFile(File file, HttpRequest request) async {
    // **LRU UPDATE: Touch the file so it's marked as "Recently Used"**
    // This prevents the cleaner from deleting active videos.
    try {
      file.setLastModified(DateTime.now());
    } catch (_) {}

    // **DIAGNOSTIC: Validate cache file on serve**
    await _logCacheFileValidation('serve-local', file);

    final response = request.response;
    final int totalLength = await file.length();

    // **RANGE SUPPORT: Enable instant seeking and partial content**
    final String? rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.add(HttpHeaders.contentTypeHeader, 'video/mp4');

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      try {
        final parts = rangeHeader.substring(6).split('-');
        int start = int.parse(parts[0]);
        int? end = parts.length > 1 && parts[1].isNotEmpty
            ? int.parse(parts[1])
            : null; // Initialize as null if not specified

        // **OFFLINE FIX: Smart Partial Serving**
        // Player asks for bytes=0- (full file), but we only have 5MB of a 10MB file.
        // Instead of erroring or waiting for network, we serve the 5MB we have.
        // This allows the player to buffer and play that 5MB offline.

        // If end is unknown or beyond our file, cap it to what we actually have
        if (end == null || end >= totalLength) {
          end = totalLength - 1;
        }

        // If start is beyond what we have, that's a genuine error (we don't have that part yet)
        if (start >= totalLength) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers
              .add(HttpHeaders.contentRangeHeader, 'bytes */$totalLength');
          AppLogger.log(
            '📡 DIAG-RESP [serve-local] video=non-e2ee '
            'STATUS=416, Content-Range=bytes */$totalLength',
          );
          await response.close();
          return;
        }

        final int contentLength = end - start + 1;

        response.statusCode = HttpStatus.partialContent;
        response.headers.add(
            HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalLength');
        response.headers.add(HttpHeaders.contentLengthHeader, contentLength);

        // **DIAGNOSTIC: Log response headers for range request**
        _logResponseHeaders(
          'serve-local-range',
          statusCode: 206,
          videoId: 'non-e2ee',
          contentLength: contentLength,
          contentRange: 'bytes $start-$end/$totalLength',
          acceptRanges: 'bytes',
          contentType: 'video/mp4',
        );

        // AppLogger.log('📡 Proxy: Serving Range $start-$end / $totalLength');
        await response.addStream(file.openRead(start, end + 1));
      } catch (e) {
        response.statusCode = HttpStatus.badRequest;
      }
    } else {
      // Standard full file response
      response.statusCode = HttpStatus.ok;
      response.headers.add(HttpHeaders.contentLengthHeader, totalLength);

      // **DIAGNOSTIC: Log response headers for full request**
      _logResponseHeaders(
        'serve-local-full',
        statusCode: 200,
        videoId: 'non-e2ee',
        contentLength: totalLength,
        contentType: 'video/mp4',
      );

      await response.addStream(file.openRead());
    }

    await response.close();
  }

  /// **HLS MANIFEST REWRITER**
  /// Fetches the .m3u8, rewrites internal URLs to point to this proxy, and serves it.
  Future<void> _handleHlsManifestRequest(HttpRequest request) async {
    final url = request.uri.queryParameters['url'];
    AppLogger.log('📡 Proxy: _handleHlsManifestRequest started for url: $url');
    if (url == null || url.isEmpty) {
      AppLogger.log('⚠️ Proxy: HLS Manifest URL is missing or empty');
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final videoId = request.uri.queryParameters['videoId'];

    String originalManifest;

    try {
      // **NEVER cache HLS manifests** — they contain CDN segment URLs that expire
      // quickly. Serving a stale manifest causes ExoPlayer Source error because
      // segment URLs return 403/404. Manifests are tiny (~1KB) so always fetch fresh.
      AppLogger.log('📡 Proxy: Fetching HLS Manifest from remote: $url');
      final client = http.Client();
      final remoteUri = Uri.parse(url);

      // Copy incoming headers (like User-Agent) to remote request
      final Map<String, String> remoteHeaders = {};
      request.headers.forEach((name, values) {
        if (name != 'host' &&
            name != 'content-length' &&
            name != 'connection') {
          remoteHeaders[name] = values.join(', ');
        }
      });
      if (!remoteHeaders.containsKey('user-agent')) {
        remoteHeaders['user-agent'] = 'Vayug-App/1.0';
      }

      final response = await client.get(remoteUri, headers: remoteHeaders);
      client.close();

      AppLogger.log(
          '📡 Proxy: Remote HLS Manifest response status: ${response.statusCode}, length: ${response.body.length} bytes');

      if (response.statusCode != 200) {
        AppLogger.log(
            '⚠️ Proxy: Failed to fetch remote manifest. Status: ${response.statusCode}');
        request.response.statusCode = response.statusCode;
        await request.response.close();
        return;
      }
      originalManifest = response.body;

      final StringBuffer modifiedManifest = StringBuffer();

      // Determine base URL for resolving relative paths
      final String baseUrl = url.substring(0, url.lastIndexOf('/') + 1);

      // Simple parser: Iterate lines and rewrite URLs
      const LineSplitter splitter = LineSplitter();
      final List<String> lines = splitter.convert(originalManifest);
      AppLogger.log('📡 Proxy: Parsing $url. Total lines: ${lines.length}');

      bool skipNextLine = false;
      int rewrittenCount = 0;
      for (String line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          modifiedManifest.writeln(line);
          continue;
        }

        if (skipNextLine) {
          skipNextLine = false;
          continue;
        }

        if (line.startsWith('#')) {
          // **LOW-END OPTIMIZATION: Filter HD Variants**
          // Reject variants that are too heavy for lownd hardware
          if (_isLowEndDevice && line.contains('#EXT-X-STREAM-INF')) {
            bool isHD = line.contains('RESOLUTION=1920x1080') ||
                line.contains('RESOLUTION=1280x720') ||
                line.contains('BANDWIDTH=4000000'); // > 4Mbps

            // If RESOLUTION is missing but BANDWIDTH is high, also filter
            if (!isHD && line.contains('BANDWIDTH=')) {
              try {
                final reg = RegExp(r'BANDWIDTH=(\d+)');
                final match = reg.firstMatch(line);
                if (match != null) {
                  final bandwidth = int.parse(match.group(1)!);
                  if (bandwidth > 2500000) {
                    isHD = true; // > 2.5 Mbps is too much for 2GB RAM
                  }
                }
              } catch (_) {}
            }

            if (isHD) {
              skipNextLine = true; // Skip this tag AND the following URL
              continue;
            }
          }
          modifiedManifest.writeln(line);
        } else {
          // This line is a URL
          String segmentUrl = trimmed;

          // Resolve relative URLs
          if (!segmentUrl.startsWith('http')) {
            segmentUrl = Uri.parse(baseUrl).resolve(segmentUrl).toString();
          }

          final encodedSegmentUrl = Uri.encodeComponent(segmentUrl);
          String localUrl;

          if (segmentUrl.contains('.m3u8')) {
            // Recursively proxy sub-playlists (manifests must go through proxy
            // so their segment URLs also get rewritten).
            localUrl =
                'http://127.0.0.1:$_port/proxy-hls?url=$encodedSegmentUrl';
            if (videoId != null) localUrl += '&videoId=$videoId';
          } else {
            // Serve .ts segments DIRECTLY from CDN.
            // ExoPlayer handles HLS segments natively — proxying them causes
            // content-type mismatches (proxy sends video/mp4 but .ts is video/MP2T)
            // which results in ExoPlaybackException: Source error.
            localUrl = segmentUrl;
          }

          modifiedManifest.writeln(localUrl);
          rewrittenCount++;
        }
      }

      AppLogger.log(
          '📡 Proxy: Finished rewriting manifest. Rewrote $rewrittenCount URLs.');

      // Serve modified manifest
      request.response.headers
          .add(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl');
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.write(modifiedManifest.toString());
      await request.response.close();
      AppLogger.log(
          '📡 Proxy: Served rewritten HLS manifest response successfully.');
    } catch (e, stack) {
      AppLogger.log('❌ Proxy: HLS Manifest rewriting failed: $e\n$stack');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _streamAndCache(
      String url, File cacheFile, HttpRequest request, String fileKey) async {
    final client = http.Client();
    // **TRACKING: Register this stream so we can cancel it if needed**
    _activeProxyStreams[fileKey] = client;
    final localResponse = request.response;
    IOSink? fileSink;

    try {
      final remoteRequest = http.Request('GET', Uri.parse(url));

      // Copy incoming headers (like Range) to the remote request
      request.headers.forEach((name, values) {
        if (name != 'host' && name != 'content-length') {
          remoteRequest.headers[name] = values.join(', ');
        }
      });

      final remoteResponse = await client.send(remoteRequest);

      // **FIX: If remote returns error, forward status and close immediately**
      // Do NOT open a cache file or stream error body — causes corrupt cache + ExoPlayer Source error
      if (remoteResponse.statusCode != 200 &&
          remoteResponse.statusCode != 206) {
        AppLogger.log(
            '⚠️ Proxy: Remote returned ${remoteResponse.statusCode} for $url');
        localResponse.statusCode = remoteResponse.statusCode;
        await remoteResponse.stream.drain<void>();
        await localResponse.close();
        return;
      }

      localResponse.statusCode = remoteResponse.statusCode;
      remoteResponse.headers.forEach((name, value) {
        try {
          localResponse.headers.set(name, value);
        } catch (_) {}
      });

      int downloadedBytes = 0;
      final int? expectedLength = remoteResponse.contentLength;

      fileSink = cacheFile.openWrite();
      await for (final List<int> chunk in remoteResponse.stream) {
        localResponse.add(chunk);
        fileSink.add(chunk);
        downloadedBytes += chunk.length;
      }
      await fileSink.close();
      fileSink = null;

      // Log truncation but don't throw — partial cache is still valid.
      if (expectedLength != null && downloadedBytes != expectedLength) {
        AppLogger.log(
            '⚠️ Proxy: Download truncated for $url: '
            'got $downloadedBytes bytes, expected $expectedLength — keeping partial cache');
      }

      // Write complete marker for standard videos too!
      // Only write complete marker if the response is 200 (full download)
      if (remoteResponse.statusCode == 200) {
        try {
          final completeMarker = File('${cacheFile.path}.complete');
          await completeMarker.create();
        } catch (e) {
          AppLogger.log('⚠️ Proxy: Failed to create complete marker: $e');
        }
      }

      await localResponse.close();
    } catch (e) {
      AppLogger.log('❌ Proxy: Stream error for $url: $e');
      // Close the partial cache file
      try {
        await fileSink?.close();
      } catch (_) {}
      // Only delete cache on actual corruption, not transient network errors
      if (!_isTransientNetworkError(e)) {
        try {
          if (await cacheFile.exists()) await cacheFile.delete();
        } catch (_) {}
        try {
          final completeMarker = File('${cacheFile.path}.complete');
          if (await completeMarker.exists()) await completeMarker.delete();
        } catch (_) {}
        AppLogger.log('🧹 Proxy: Deleted cache for $url — error is data corruption');
      } else {
        AppLogger.log('🔄 Proxy: Preserving partial cache for $url — error is transient (network)');
      }
      // Send a proper error status to ExoPlayer so it can handle it cleanly
      try {
        localResponse.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      try {
        await localResponse.close();
      } catch (_) {}
    } finally {
      client.close();
      // **CLEANUP: Remove from tracker**
      _activeProxyStreams.remove(fileKey);
    }
  }

  /// **NEW: Proactively pre-fetch the first few MB of a video to disk (Resume Support)**
  /// Uses Range headers to continue buffering where the player left off.
  Future<void> prefetchChunk(String url, {int megabytes = 5}) async {
    if (url.isEmpty || _cachePath == null) return;

    // **HLS SPECIAL HANDLING**
    if (url.contains('.m3u8')) {
      await _prefetchHlsInitial(url);
      return;
    }

    final String fileKey = md5.convert(utf8.encode(url)).toString();
    final String filePath = '$_cachePath/$fileKey.chunk';
    final file = File(filePath);

    // Conflict check: Don't touch if already being written by proxy
    if (_activeDownloads.containsKey(filePath)) {
      AppLogger.log(
          '⚠️ Proxy: Skipping prefetch for $fileKey - currently being streamed');
      return;
    }

    int currentLength = 0;
    if (await file.exists()) {
      currentLength = await file.length();
      // If we already have enough (e.g. > 5MB), skip
      if (currentLength >= megabytes * 1024 * 1024) {
        // AppLogger.log('✅ Proxy: Skipping prefetch for $fileKey - already has ${(currentLength/1024/1024).toStringAsFixed(2)}MB');
        return;
      }
    }

    print(
        '📥 Proxy: Background buffering $fileKey (Current: ${(currentLength / 1024 / 1024).toStringAsFixed(2)}MB, Target: ${megabytes}MB)');

    final client = http.Client();
    _activeDownloads[filePath] = client; // Store client for cancellation

    try {
      final request = http.Request('GET', Uri.parse(url));

      // **RESUME LOGIC: Request only missing bytes**
      if (currentLength > 0) {
        request.headers['Range'] = 'bytes=$currentLength-';
      }

      final response = await client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        AppLogger.log(
            '⚠️ Proxy: Background buffer failed status ${response.statusCode}');
        return;
      }

      final IOSink fileSink = file.openWrite(mode: FileMode.append);
      int downloaded = 0;
      final int maxBytes = megabytes * 1024 * 1024;

      // Stream and append
      await for (final List<int> chunk in response.stream) {
        fileSink.add(chunk);
        downloaded += chunk.length;

        // Safety cap
        if ((currentLength + downloaded) >= maxBytes) break;
      }

      await fileSink.flush();
      await fileSink.close();
      AppLogger.log(
          '✅ Proxy: Background buffered +${(downloaded / 1024).toStringAsFixed(1)}KB for $fileKey');
    } catch (e) {
      // Silently handle cancellation and errors
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    } finally {
      client.close();
      _activeDownloads.remove(filePath);
    }
  }

  /// **NEW: Smart Initial Chunk Prefetch for Instant Playback (0.5s Buffer)**
  /// Downloads only the first 300-500KB of a video for instant playback start.
  /// The rest of the video is loaded by ExoPlayer in the background.

  void configureService({required bool isLowEndDevice}) {
    _isLowEndDevice = isLowEndDevice;
    if (isLowEndDevice) {
      _maxCacheSizeBytes = 100 * 1024 * 1024; // 100MB for Low End
      AppLogger.log(
          '📉 Proxy: Configured for Low-End Device (Quality capped to 480p/720p)');
    } else {
      _maxCacheSizeBytes = 300 * 1024 * 1024; // 300MB for High End
      AppLogger.log(
          '📈 Proxy: Configured for High-End Device (Full performance)');
    }
  }

  /// **NEW: Check if a URL is a proxy URL**
  bool isProxyUrl(String url) {
    return url.contains('127.0.0.1') || url.contains('localhost');
  }

  /// **NEW: Smart Initial Chunk Prefetch for Instant Playback (0.5s Buffer)**
  /// Downloads only the first 300-500KB of a video for instant playback start.
  /// The rest of the video is loaded by ExoPlayer in the background.
  Future<void> prefetchInitialChunk(String url, {int kilobytes = 400}) async {
    if (url.isEmpty || _cachePath == null) return;

    // **HLS SPECIAL HANDLING**
    // If it's an HLS playlist, we must download the manifest AND the first segment.
    if (url.contains('.m3u8')) {
      await _prefetchHlsInitial(url);
      return;
    }

    final String fileKey = md5.convert(utf8.encode(url)).toString();
    final String filePath = '$_cachePath/$fileKey.chunk';
    final file = File(filePath);

    // Skip if already being downloaded
    if (_activeDownloads.containsKey(filePath)) {
      return;
    }

    // Check if we already have the initial chunk
    int currentLength = 0;
    if (await file.exists()) {
      currentLength = await file.length();
      // If we already have the initial chunk (~400KB), skip
      if (currentLength >= kilobytes * 1024) {
        return;
      }
    }

    // AppLogger.log('⚡ Proxy: Prefetching initial ${kilobytes}KB chunk for instant playback');

    final client = http.Client();
    _activeDownloads[filePath] = client;

    try {
      final request = http.Request('GET', Uri.parse(url));

      // Request only the initial chunk using HTTP Range header
      // Range: bytes=0-409599 (for 400KB)
      final int endByte = (kilobytes * 1024) - 1;
      request.headers['Range'] = 'bytes=0-$endByte';

      final response = await client.send(request);

      // Accept both 200 (full response) and 206 (partial content)
      if (response.statusCode != 200 && response.statusCode != 206) {
        // AppLogger.log('⚠️ Proxy: Initial chunk prefetch failed with status ${response.statusCode}');
        return;
      }

      final IOSink fileSink = file.openWrite();
      int downloaded = 0;
      final int maxBytes = kilobytes * 1024;

      // Download the initial chunk
      await for (final List<int> chunk in response.stream) {
        fileSink.add(chunk);
        downloaded += chunk.length;

        // Stop after downloading requested chunk size
        if (downloaded >= maxBytes) break;
      }

      await fileSink.flush();
      await fileSink.close();

      // Mark as recently used
      try {
        file.setLastModified(DateTime.now());
      } catch (_) {}
    } catch (e) {
      // Silently handle cancellation
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    } finally {
      client.close();
      _activeDownloads.remove(filePath);
    }
  }

  /// Prefetch a file completely (no Range header) and write .complete marker.
  /// Downloads encrypted bytes to .chunk, then background-decrypts to .dec.
  /// Signals _e2eePrebufferCompleters when decrypted bytes are on disk.
  Future<void> prefetchFullFile(String url, {String? videoId}) async {
    if (url.isEmpty || _cachePath == null) return;
    final String fileKey = md5.convert(utf8.encode(url)).toString();
    final String chunkPath = '$_cachePath/$fileKey.chunk';
    final chunkFile = File(chunkPath);
    final chunkComplete = File('$chunkPath.complete');

    // ── FAST PATH: Already fully decrypted → nothing to do.
    final decFile = File('$_cachePath/$fileKey.dec');
    final decComplete = File('$_cachePath/$fileKey.dec.complete');
    if (await decComplete.exists() && await decFile.exists()) {
      _signalE2eePrebufferComplete(fileKey);
      AppLogger.log('🔐 Proxy: E2EE prefetch — .dec already complete for $fileKey');
      return;
    }

    // ── MEDIUM PATH: Encrypted file already on disk → just background-decrypt.
    if (await chunkComplete.exists() && await chunkFile.exists()) {
      if (!_e2eeActiveDecrypts.contains(fileKey)) {
        _backgroundDecryptToFile(fileKey, videoId: videoId);
      }
      _signalE2eePrebufferComplete(fileKey);
      return;
    }

    // ── SLOW PATH: Need to download encrypted bytes first.
    if (_e2eeActiveDownloads.contains(fileKey) || _activeDownloads.containsKey(chunkPath)) {
      return;
    }

    final client = http.Client();
    _e2eeActiveDownloads.add(fileKey);
    _activeDownloads[chunkPath] = client;

    // Initialize download progress tracking for UI
    _downloadProgress[fileKey] = ValueNotifier(const E2eeDownloadProgress(downloadedBytes: 0));
    _downloadStartTimes[fileKey] = DateTime.now();

    try {
      int currentLength = 0;
      if (await chunkFile.exists()) {
        currentLength = await chunkFile.length();
      }

      final request = http.Request('GET', Uri.parse(url));
      if (currentLength > 0) {
        request.headers['Range'] = 'bytes=$currentLength-';
        AppLogger.log('🔐 Proxy: Resuming E2EE prefetch for $fileKey from byte $currentLength');
      }

      // Disable CDN compression so Content-Length matches actual encrypted byte count.
      request.headers['accept-encoding'] = 'identity';

      final response = await client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        _signalE2eePrebufferComplete(fileKey, success: false);
        _completeDownloadProgress(fileKey, success: false);
        return;
      }

      final bool isResume = response.statusCode == 206 && currentLength > 0;
      final IOSink fileSink = chunkFile.openWrite(
        mode: isResume ? FileMode.append : FileMode.write,
      );

      final int? totalBytes = response.contentLength;
      int downloadedBytes = currentLength;

      await for (final List<int> chunk in response.stream) {
        fileSink.add(chunk);
        downloadedBytes += chunk.length;
        // Emit progress every ~256KB to avoid excessive UI rebuilds
        if (downloadedBytes % (256 * 1024) < chunk.length || totalBytes != null) {
          _updateDownloadProgress(fileKey, downloadedBytes, totalBytes != null ? currentLength + totalBytes : null);
        }
      }

      await fileSink.flush();
      await fileSink.close();

      // Create .complete marker based on ACTUAL bytes written to disk,
      // not CDN Content-Length (which may be null or wrong).
      // A substantial file (>1MB) means the download was meaningful.
      final int actualSize = await chunkFile.length();
      if (actualSize > 1024 * 1024) {
        await chunkComplete.create();
        // Persist videoId mapping for proactive background decrypt on restart
        if (videoId != null) _persistVideoIdMapping(fileKey, videoId);
      }

      AppLogger.log('🔐 Proxy: E2EE prefetch — downloaded ${(actualSize / 1024).toStringAsFixed(0)}KB encrypted for $fileKey');

      _completeDownloadProgress(fileKey, success: true);

      // Signal prebuffer so ExoPlayer can start (proxy will decrypt on-the-fly for first request)
      _signalE2eePrebufferComplete(fileKey);

      // Start background decrypt from .chunk → .dec
      _backgroundDecryptToFile(fileKey, videoId: videoId);
    } catch (e) {
      _completeDownloadProgress(fileKey, success: false);
      // Only delete cache on actual corruption, not transient network errors.
      // A partially downloaded .chunk is still useful — next request can resume.
      if (!_isTransientNetworkError(e)) {
        try {
          if (await chunkFile.exists()) await chunkFile.delete();
        } catch (_) {}
        try {
          if (await chunkComplete.exists()) await chunkComplete.delete();
        } catch (_) {}
      } else {
        AppLogger.log('🔄 Proxy: Preserving partial prefetch for $fileKey — error is transient (network)');
      }
      _signalE2eePrebufferComplete(fileKey, success: false);
    } finally {
      client.close();
      _activeDownloads.remove(chunkPath);
      _e2eeActiveDownloads.remove(fileKey);
    }
  }

  /// Background decrypt: reads encrypted .chunk → writes decrypted .dec.
  /// Runs in an Isolate for CPU-bound work. Creates .dec.complete when done.
  Future<void> _backgroundDecryptToFile(String fileKey, {String? videoId}) async {
    if (_cachePath == null) return;
    if (_e2eeActiveDecrypts.contains(fileKey)) return;

    final chunkFile = File('$_cachePath/$fileKey.chunk');
    final decFile = File('$_cachePath/$fileKey.dec');
    final decComplete = File('$_cachePath/$fileKey.dec.complete');

    if (!await chunkFile.exists()) return;
    if (await decComplete.exists() && await decFile.exists()) return;

    _e2eeActiveDecrypts.add(fileKey);

    try {
      final Uint8List? symmetricKey = _symmetricKeys[videoId];
      if (symmetricKey == null) {
        AppLogger.log('⚠️ Proxy: Background decrypt — no symmetric key for $fileKey (video=$videoId), will decrypt on-the-fly when served');
        return;
      }

      final chunkBytes = await chunkFile.readAsBytes();
      final int totalEncrypted = chunkBytes.length;

      AppLogger.log('🔐 Proxy: Background decrypt started for $fileKey — ${(totalEncrypted / 1024).toStringAsFixed(0)}KB encrypted');

      // Decrypt all chunks and write to .dec file
      final IOSink decSink = decFile.openWrite();
      int totalDecrypted = 0;

      // Process in 2MB encrypted-chunk increments
      for (int offset = 0; offset < totalEncrypted; offset += _e2eeEncChunkSize) {
        final int end = (offset + _e2eeEncChunkSize).clamp(0, totalEncrypted);
        final encChunk = Uint8List.fromList(chunkBytes.sublist(offset, end));

        final Uint8List plain = await Isolate.run(
          () => _decryptEncBytesFromOffset(encChunk, symmetricKey, 0, encChunk.length),
        );

        if (plain.isNotEmpty) {
          decSink.add(plain);
          totalDecrypted += plain.length;
        }
      }

      await decSink.flush();
      await decSink.close();

      await decComplete.create();
      _recordE2eeExactPlainSize(fileKey, totalDecrypted);

      AppLogger.log('🔐 Proxy: Background decrypt complete for $fileKey — ${(totalDecrypted / 1024).toStringAsFixed(0)}KB decrypted');
    } catch (e) {
      AppLogger.log('⚠️ Proxy: Background decrypt failed for $fileKey: $e');
      try {
        if (await decFile.exists()) await decFile.delete();
      } catch (_) {}
      try {
        if (await decComplete.exists()) await decComplete.delete();
      } catch (_) {}
    } finally {
      _e2eeActiveDecrypts.remove(fileKey);
    }
  }

  /// Signal the prebuffer Completer for [fileKey].
  void _signalE2eePrebufferComplete(String fileKey, {bool success = true}) {
    final completer = _e2eePrebufferCompleters[fileKey];
    if (completer != null && !completer.isCompleted) {
      completer.complete(success);
    }
  }

  /// **NEW: HLS Prefetch Helper**
  /// Downloads manifest + First Segment for successful offline start.
  Future<void> _prefetchHlsInitial(String url) async {
    try {
      // 1. Download Manifest
      final client = http.Client();
      final response = await client.get(
        Uri.parse(url),
        headers: VideoPlayerConfigService.getOptimizedHeaders(url),
      );
      client.close();

      if (response.statusCode != 200) return;

      // Save Manifest
      final String manifestKey = md5.convert(utf8.encode(url)).toString();
      if (_cachePath == null) return;
      final File manifestFile = File('$_cachePath/$manifestKey.chunk');
      await manifestFile.writeAsString(response.body);
      try {
        await File('${manifestFile.path}.complete').create();
      } catch (_) {}

      // 2. Parse for First Segment
      final lines = const LineSplitter().convert(response.body);
      String? firstSegmentUrl;

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
          firstSegmentUrl = trimmed;
          break; // Found first segment
        }
      }

      if (firstSegmentUrl != null) {
        // Resolve relative URL
        if (!firstSegmentUrl.startsWith('http')) {
          final baseUrl = url.substring(0, url.lastIndexOf('/') + 1);
          firstSegmentUrl =
              Uri.parse(baseUrl).resolve(firstSegmentUrl).toString();
        }

        // Download First Segment completely so it is cached and marked complete
        await prefetchFullFile(firstSegmentUrl);
      }
    } catch (e) {
      // AppLogger.log('❌ Proxy: HLS Prefetch error: $e');
    }
  }

  /// Classifies whether an error is a transient network issue (cache should be preserved)
  /// or an actual data corruption (cache should be deleted).
  static bool _isTransientNetworkError(Object error) {
    final msg = error.toString().toLowerCase();
    // Network/transport errors — cache is still valid, just CDN unreachable
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) return true;
    if (error is http.ClientException) return true;
    if (msg.contains('connection closed')) return true;
    if (msg.contains('connection reset')) return true;
    if (msg.contains('connection refused')) return true;
    if (msg.contains('connection timed out')) return true;
    if (msg.contains('socket')) return true;
    if (msg.contains('broken pipe')) return true;
    if (msg.contains('eof')) return true;
    if (msg.contains('httpexception')) return true;
    if (msg.contains('clientexception')) return true;
    if (msg.contains('os error')) return true;
    return false;
  }

  /// Clean up old cache files (LRU implementation)
  Future<void> cleanCache() async {
    if (_cachePath == null) return;
    final dir = Directory(_cachePath!);
    if (!await dir.exists()) return;

    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      // Clean both .chunk (encrypted) and .dec (decrypted) cache files
      final List<File> files = entities
          .whereType<File>()
          .where((f) => f.path.endsWith('.chunk') || f.path.endsWith('.dec'))
          .toList();

      // Sort oldest first
      files.sort(
          (a, b) => a.statSync().modified.compareTo(b.statSync().modified));

      int totalSize = 0;

      // **DYNAMIC CACHE LIMIT**
      // Default: 200MB. Can be updated via configure().
      final int maxSizeBytes = _maxCacheSizeBytes;

      for (var file in files) {
        totalSize += await file.length();
      }

      if (totalSize <= maxSizeBytes) return;

      int deletedCount = 0;
      for (var file in files) {
        if (totalSize <= maxSizeBytes) break;

        final length = await file.length();
        await file.delete();

        // Delete associated .complete marker
        final completeMarker = File('${file.path}.complete');
        if (await completeMarker.exists()) {
          try { await completeMarker.delete(); } catch (_) {}
        }

        // Also delete the paired .dec/.chunk file and its .complete marker
        if (file.path.endsWith('.chunk')) {
          final pairedDec = File(file.path.replaceAll('.chunk', '.dec'));
          if (await pairedDec.exists()) {
            try { totalSize -= await pairedDec.length(); await pairedDec.delete(); } catch (_) {}
          }
          final pairedDecComplete = File('${pairedDec.path}.complete');
          if (await pairedDecComplete.exists()) {
            try { await pairedDecComplete.delete(); } catch (_) {}
          }
        } else if (file.path.endsWith('.dec')) {
          final pairedChunk = File(file.path.replaceAll('.dec', '.chunk'));
          if (await pairedChunk.exists()) {
            try { totalSize -= await pairedChunk.length(); await pairedChunk.delete(); } catch (_) {}
          }
          final pairedChunkComplete = File('${pairedChunk.path}.complete');
          if (await pairedChunkComplete.exists()) {
            try { await pairedChunkComplete.delete(); } catch (_) {}
          }
        }

        totalSize -= length;
        deletedCount++;
      }
      AppLogger.log(
          '🧹 Proxy Cache: Cleaned up $deletedCount files (Limit: ${maxSizeBytes / 1024 / 1024}MB)');
    } catch (e) {
      AppLogger.log('❌ Proxy Cache: Cleanup error: $e');
    }
  }

  /// **NEW: Get a random available video URL from cache for instant splash screen**
  /// Returns null if no cached videos found.
  /// Smartly rotates videos to avoid showing same one every time.
  Future<String?> getRandomCachedVideoUrl() async {
    if (_cachePath == null) return null;
    final dir = Directory(_cachePath!);
    if (!await dir.exists()) return null;

    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      final List<File> files = entities.whereType<File>().toList();

      if (files.isEmpty) return null;

      // Filter for substantial files (e.g. > 1MB) to ensure it's playable
      final validFiles = <File>[];
      for (var file in files) {
        if (await file.length() > 1024 * 1024) {
          validFiles.add(file);
        }
      }

      if (validFiles.isEmpty) return null;

      // Smart Rotation: Pick a random one
      // In a real app, we could store 'lastShownSplash' in SharedPreferences
      // to ensure we cycle through them.
      validFiles.shuffle();
      final File selectedFile = validFiles.first;

      // We need to reverse-engineer the URL from the file hash if possible,
      // OR we just return the local file path directly if the player supports it.
      // Since VideoPlayerController.file() works, we can return the path.
      return selectedFile.path;
    } catch (e) {
      AppLogger.log('❌ Proxy: Error finding cached video: $e');
      return null;
    }
  }

  /// **NEW: Check if a URL is cached and playable (file exists and > 1MB)**
  Future<bool> isCached(String url) async {
    if (_cachePath == null || url.isEmpty) return false;

    try {
      final String fileKey = md5.convert(utf8.encode(url)).toString();
      final String filePath = '$_cachePath/$fileKey.chunk';
      final file = File(filePath);
      final completeMarker = File('$filePath.complete');

      AppLogger.log('🔍 ProxyDebug: Checking cache for URL: $url');
      AppLogger.log('   Key: $fileKey');
      AppLogger.log('   Path: $filePath');

      if (await file.exists() && await completeMarker.exists()) {
        final length = await file.length();
        final isSubstantial = length > 1024 * 1024;
        AppLogger.log(
            '   Result: File Exists and is Complete. Size: ${(length / 1024 / 1024).toStringAsFixed(2)} MB. Playable (>1MB)? $isSubstantial');

        // Return true if file is substantial enough to play (e.g. > 1MB)
        return isSubstantial;
      } else {
        AppLogger.log('   Result: File does NOT exist or is incomplete.');
      }
      return false;
    } catch (e) {
      AppLogger.log('❌ ProxyDebug: Error checking cache: $e');
      return false;
    }
  }

  /// **NEW: Get the local path if the URL is cached (substantial file), else null**
  Future<String?> getCachedFilePath(String url) async {
    if (_cachePath == null || url.isEmpty) return null;

    try {
      final String fileKey = md5.convert(utf8.encode(url)).toString();
      final String filePath = '$_cachePath/$fileKey.chunk';
      final file = File(filePath);
      final completeMarker = File('$filePath.complete');

      if (await file.exists() &&
          await completeMarker.exists() &&
          await file.length() > 1024 * 1024) {
        return filePath;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// **NEW: Check if the decrypted .dec file is ready for instant serve.**
  /// Returns true if .dec.complete + .dec exist (full decryption finished).
  Future<bool> isDecryptedReady(String url) async {
    if (_cachePath == null || url.isEmpty) return false;
    try {
      final String fileKey = md5.convert(utf8.encode(url)).toString();
      final decFile = File('$_cachePath/$fileKey.dec');
      final decComplete = File('$_cachePath/$fileKey.dec.complete');
      return await decComplete.exists() && await decFile.exists();
    } catch (_) {
      return false;
    }
  }

  /// **NEW: Global Cancel All Prefetches**
  /// Stops all background downloads immediately.
  void cancelAllPrefetches() {
    if (_activeDownloads.isEmpty) return;

    // final count = _activeDownloads.length;
    // AppLogger.log('🛑 Proxy: Cancelling $count active prefetch downloads...');

    for (final client in _activeDownloads.values) {
      try {
        client
            .close(); // Only closes the client, might not stop stream immediately if not handled
      } catch (_) {}
    }

    _activeDownloads.clear();
  }

  /// Cancel all prefetch downloads except specified URLs and playable E2EE URLs.
  void cancelAllPrefetchesExcept(List<String> urlsToKeep) {
    if (_activeDownloads.isEmpty) return;

    final Set<String> keysToKeep = urlsToKeep
        .where((u) => u.isNotEmpty)
        .map((url) => md5.convert(utf8.encode(url)).toString())
        .toSet();

    // Protect all decrypted/playable E2EE URLs
    for (final url in _playableE2eeUrls) {
      keysToKeep.add(md5.convert(utf8.encode(url)).toString());
    }

    final List<String> pathsToRemove = [];
    _activeDownloads.forEach((path, client) {
      bool keep = false;
      for (final key in keysToKeep) {
        if (path.contains(key)) {
          keep = true;
          break;
        }
      }
      if (!keep) {
        pathsToRemove.add(path);
      }
    });

    for (final path in pathsToRemove) {
      try {
        _activeDownloads[path]?.close();
        _activeDownloads.remove(path);
        AppLogger.log('🔐 Proxy: Cancelled background download for $path');
      } catch (_) {}
    }
  }

  /// **NEW: Whitelist-based Cancellation Strategy**
  /// "Cancel everything EXCEPT these specific URLs."
  /// Prevents Race Conditions by ensuring the Current/Next videos are NEVER killed.
  /// Performance: Hash checks are in-memory (microseconds), network bandwidth saved is massive (MBs).
  void cancelAllStreamingExcept(List<String> urlsToKeep) {
    if (_activeProxyStreams.isEmpty && _activeDownloads.isEmpty) return;

    // 1. Calculate Safe Keys (Hashes) of URLs to Keep
    //    We use a Set for O(1) lookup speed.
    final Set<String> keysToKeep = urlsToKeep
        .where((u) => u.isNotEmpty)
        .map((url) => md5.convert(utf8.encode(url)).toString())
        .toSet();

    // 2. Cancel Active Proxy Streams (The videos currently playing/buffering)
    final proxyKeysToRemove = _activeProxyStreams.keys
        .where((key) => !keysToKeep.contains(key))
        .toList();
    for (final key in proxyKeysToRemove) {
      try {
        _activeProxyStreams[key]?.close();
        _activeProxyStreams.remove(key);
      } catch (_) {}
    }

    // 3. Cancel Active Prefetches (Background downloads)
    //    _activeDownloads uses filePath as key, which contains the hashKey.
    final downloadPathsToRemove = _activeDownloads.keys.where((path) {
      for (final keptKey in keysToKeep) {
        // Path structure: .../video_chunks/<HASH>.chunk
        if (path.contains(keptKey)) return false; // Match found! Keep it.
      }
      return true; // No match found. Kill it.
    }).toList();

    for (final path in downloadPathsToRemove) {
      try {
        _activeDownloads[path]?.close();
        _activeDownloads.remove(path);
      } catch (_) {}
    }

    // Log if we actually saved resources
    if (proxyKeysToRemove.isNotEmpty || downloadPathsToRemove.isNotEmpty) {
      // AppLogger.log('✂️ Proxy: Instantly freed ${proxyKeysToRemove.length} streams & ${downloadPathsToRemove.length} prefetches. (Safe list size: ${keysToKeep.length})');
    }
  }

  /// Routes a second player request that arrived while the primary E2EE download
  /// is still caching. Never touches the partial cache file.
  Future<void> _serveConcurrentE2eeRequest({
    required String url,
    required File file,
    required HttpRequest request,
    required Uint8List symmetricKey,
    required String fileKey,
    required String? videoId,
    required _PlayerRange playerRange,
  }) async {
    AppLogger.log(
      '🔐 Proxy: [RACE-GUARD] Concurrent E2EE request for $videoId '
      '(fileKey=$fileKey, range=${playerRange.isPresent ? "yes" : "no"}) — '
      'primary download in progress, bypassing cache writer',
    );

    if (playerRange.isPresent) {
      final rangeStart = await _resolveRangeStartPlain(
        playerRange,
        fileKey: fileKey,
        cacheFile: file,
      );
      await _serveRemoteDecryptedRange(
        url,
        request,
        symmetricKey,
        rangeStart,
        playerRange.endPlain,
        videoId: videoId,
        fileKey: fileKey,
      );
    } else {
      await _serveDecryptedStream(
        url,
        file,
        request,
        symmetricKey,
        videoId: videoId,
        fileKey: fileKey,
        forceRemote: true,
      );
    }
  }

  _PlayerRange _parsePlayerRange(String? rangeHeader) {
    if (rangeHeader == null || !rangeHeader.startsWith('bytes=')) {
      return const _PlayerRange(isPresent: false, startPlain: 0);
    }

    final spec = rangeHeader.substring(6).trim();
    final dashIdx = spec.indexOf('-');
    if (dashIdx < 0) {
      return const _PlayerRange(isPresent: true, startPlain: 0);
    }

    final startPart = spec.substring(0, dashIdx);
    final endPart = spec.substring(dashIdx + 1);

    if (startPart.isEmpty && endPart.isNotEmpty) {
      return _PlayerRange(
        isPresent: true,
        startPlain: 0,
        isSuffixOnly: true,
        suffixLength: int.parse(endPart),
      );
    }

    final start = startPart.isEmpty ? 0 : int.parse(startPart);
    final int? end = endPart.isEmpty ? null : int.parse(endPart);
    return _PlayerRange(
      isPresent: true,
      startPlain: start,
      endPlain: end,
    );
  }

  Future<int> _resolveRangeStartPlain(
    _PlayerRange playerRange, {
    required String fileKey,
    required File cacheFile,
  }) async {
    if (!playerRange.isSuffixOnly || playerRange.suffixLength == null) {
      return playerRange.startPlain;
    }

    int? encryptedTotal = _e2eeEncryptedLengths[fileKey];
    if (encryptedTotal == null && await cacheFile.exists()) {
      encryptedTotal = await cacheFile.length();
      if (encryptedTotal > 0) {
        _recordE2eeEncryptedSize(fileKey, encryptedTotal);
      }
    }

    final plainTotal =
        _getE2eePlainLength(fileKey, encryptedHint: encryptedTotal);
    if (plainTotal <= 0) {
      AppLogger.log(
        '⚠️ Proxy: Suffix range requested but plaintext size unknown yet — using startPlain=0',
      );
      return 0;
    }

    final suffix = playerRange.suffixLength!;
    final start = plainTotal - suffix;
    return start < 0 ? 0 : start;
  }

  void _logMp4PlayabilityCheck(
    String tag,
    List<int> data, {
    required String? videoId,
    int streamOffset = 0,
  }) {
    if (data.isEmpty) return;

    final vid = videoId ?? 'unknown';

    if (streamOffset == 0 && data.length >= 8) {
      final boxType = String.fromCharCodes(data.sublist(4, 8));
      if (boxType == 'ftyp') {
        AppLogger.log(
          '✅ Proxy: PLAYABLE [$tag] video=$vid — ftyp box confirmed; '
          'player is receiving a valid MP4 header',
        );
        return;
      }
    }

    if (_indexOfAscii(data, 'moov') >= 0) {
      AppLogger.log(
        '✅ Proxy: PLAYABLE [$tag] video=$vid — moov atom present; '
        'player can read seek/metadata index',
      );
      return;
    }

    if (streamOffset == 0 && data.length >= 8) {
      final boxType = String.fromCharCodes(data.sublist(4, 8));
      AppLogger.log(
        '⚠️ Proxy: PLAYABLE-CHECK [$tag] video=$vid — '
        'first box "$boxType" (may be a mid-file range response)',
      );
    }
  }

  void _logStreamDeliveredToPlayer(
    String tag, {
    required String? videoId,
    required int decryptedBytes,
    bool cacheMarkedComplete = false,
    int? httpStatus,
  }) {
    final vid = videoId ?? 'unknown';
    final cacheNote = cacheMarkedComplete ? ', cache marked complete' : '';
    final statusNote = httpStatus != null ? ', http=$httpStatus' : '';
    AppLogger.log(
      '✅ Proxy: PLAYABLE [$tag] video=$vid — delivered '
      '$decryptedBytes decrypted bytes to player$cacheNote$statusNote',
    );
  }

  int _indexOfAscii(List<int> haystack, String needle) {
    if (needle.isEmpty || haystack.length < needle.length) return -1;
    final codes = needle.codeUnits;
    for (int i = 0; i <= haystack.length - codes.length; i++) {
      bool match = true;
      for (int j = 0; j < codes.length; j++) {
        if (haystack[i + j] != codes[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  /// Serve a pre-decrypted .dec file directly — 0ms decrypt, no Isolate needed.
  Future<void> _serveDecryptedFileDirectly(
    String url,
    File decFile,
    HttpRequest request, {
    String? fileKey,
    String? videoId,
  }) async {
    final response = request.response;
    try {
      final length = await decFile.length();

      // **DIAGNOSTIC: Validate decrypted cache file**
      await _logCacheFileValidation('serve-dec-direct', decFile, videoId: videoId);

      final String? rangeHeader =
          request.headers.value(HttpHeaders.rangeHeader);
      int startPlain = 0;
      int? endPlain;
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        startPlain = int.parse(parts[0]);
        if (parts.length > 1 && parts[1].isNotEmpty) {
          endPlain = int.parse(parts[1]);
        }
      }

      final int totalPlain = length;
      int endPlainValue = endPlain ?? (totalPlain > 0 ? totalPlain - 1 : 0);
      if (totalPlain > 0 && endPlainValue >= totalPlain) {
        endPlainValue = totalPlain - 1;
      }
      final int contentLength = endPlainValue - startPlain + 1;

      response.headers.add('Access-Control-Allow-Origin', '*');
      response.headers.add(HttpHeaders.contentTypeHeader, 'video/mp4');
      response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
      if (rangeHeader != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.add(HttpHeaders.contentRangeHeader,
            'bytes $startPlain-$endPlainValue/$totalPlain');
        response.headers.add(HttpHeaders.contentLengthHeader, contentLength);

        // **DIAGNOSTIC: Log E2EE dec-cache range response**
        _logResponseHeaders(
          'serve-dec-direct-range',
          statusCode: 206,
          videoId: videoId ?? 'unknown',
          contentLength: contentLength,
          contentRange: 'bytes $startPlain-$endPlainValue/$totalPlain',
          acceptRanges: 'bytes',
          contentType: 'video/mp4',
        );
      } else {
        response.statusCode = HttpStatus.ok;
        response.headers.add(HttpHeaders.contentLengthHeader, totalPlain);

        // **DIAGNOSTIC: Log E2EE dec-cache full response**
        _logResponseHeaders(
          'serve-dec-direct-full',
          statusCode: 200,
          videoId: videoId ?? 'unknown',
          contentLength: totalPlain,
          contentType: 'video/mp4',
        );
      }

      // Direct file read — no decryption, no Isolate, no CPU work.
      await response.addStream(decFile.openRead(startPlain, endPlainValue + 1));
      await response.close();

      _logStreamDeliveredToPlayer(
        'dec-cache-hit',
        videoId: videoId,
        decryptedBytes: contentLength,
        httpStatus: response.statusCode,
      );
    } catch (e, stack) {
      AppLogger.log('❌ Proxy: dec-cache serve failed for video=$videoId: $e\n$stack');
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveDecryptedStream(
      String url, File file, HttpRequest request, Uint8List symmetricKey,
      {bool forceRemote = false, String? videoId, String? fileKey}) async {
    AppLogger.log(
        '🔐 Proxy: ServeDecryptedStream started for ${file.path}. URL: $url, forceRemote: $forceRemote');
    final response = request.response;

    try {
      // ── FAST PATH: Check for pre-decrypted .dec file (0ms decrypt).
      if (fileKey != null && _cachePath != null && !forceRemote) {
        final decFile = File('$_cachePath/$fileKey.dec');
        final decComplete = File('$_cachePath/$fileKey.dec.complete');
        if (await decComplete.exists() && await decFile.exists()) {
          AppLogger.log('🔐 Proxy: Serving E2EE from DEC file (0ms decrypt): ${decFile.path}');
          return _serveDecryptedFileDirectly(url, decFile, request, fileKey: fileKey, videoId: videoId);
        }
      }

      if (await file.exists() && !forceRemote) {
        AppLogger.log('🔐 Proxy: Serving E2EE from cache file: ${file.path}');
        final length = await file.length();

        final String? rangeHeader =
            request.headers.value(HttpHeaders.rangeHeader);
        int startPlain = 0;
        int? endPlain;
        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          final parts = rangeHeader.substring(6).split('-');
          startPlain = int.parse(parts[0]);
          if (parts.length > 1 && parts[1].isNotEmpty) {
            endPlain = int.parse(parts[1]);
          }
        }

        // For range requests: use the stored/estimated plain length for Content-Range.
        // For full-file (no range) requests: use Int64.maxValue so the streaming
        // loop reads the ENTIRE encrypted file. This ensures bytesSent reflects the
        // true plaintext size (not capped by an estimation that may be too low),
        // and we then persist it for subsequent range requests.
        final bool isFullFileRequest = rangeHeader == null;
        final int totalPlainLength = fileKey != null
            ? _getE2eePlainLength(fileKey, encryptedHint: length)
            : _estimatePlainLengthFromEncrypted(length);

        int endPlainValue = endPlain ?? (totalPlainLength > 0 ? totalPlainLength - 1 : 0);
        if (totalPlainLength > 0 && endPlainValue >= totalPlainLength) {
          endPlainValue = totalPlainLength - 1;
        }
        // For full-file requests, use a sentinel so the loop never breaks early.
        final int contentLength = isFullFileRequest
            ? 0x7FFFFFFFFFFFFFFF
            : endPlainValue - startPlain + 1;

        response.headers.add('Access-Control-Allow-Origin', '*');
        response.headers.add(HttpHeaders.contentTypeHeader, 'video/mp4');
        if (rangeHeader != null) {
          response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
          response.statusCode = HttpStatus.partialContent;
          response.headers.add(HttpHeaders.contentRangeHeader,
              'bytes $startPlain-$endPlainValue/$totalPlainLength');
          response.headers.add(HttpHeaders.contentLengthHeader, endPlainValue - startPlain + 1);

          // **DIAGNOSTIC: Log E2EE cache-hit range response**
          _logResponseHeaders(
            'serve-dec-stream-range',
            statusCode: 206,
            videoId: videoId ?? 'unknown',
            contentLength: endPlainValue - startPlain + 1,
            contentRange: 'bytes $startPlain-$endPlainValue/$totalPlainLength',
            acceptRanges: 'bytes',
            contentType: 'video/mp4',
          );
        } else {
          response.statusCode = HttpStatus.ok;
          response.headers.add(HttpHeaders.transferEncodingHeader, 'chunked');

          // **DIAGNOSTIC: Log E2EE cache-hit full response**
          _logResponseHeaders(
            'serve-dec-stream-full',
            statusCode: 200,
            videoId: videoId ?? 'unknown',
            contentLength: totalPlainLength,
            transferEncoding: 'chunked',
            contentType: 'video/mp4',
          );
        }

        // ── Seek to the encrypted chunk that contains startPlain.
        final int chunkIndex = startPlain ~/ _e2eePlainChunkSize;
        final int offsetInPlainChunk = startPlain % _e2eePlainChunkSize;
        final int encFileOffset = chunkIndex * _e2eeEncChunkSize;

        // ── Stream-decrypt in 2 MiB encrypted-chunk increments.
        // Each chunk is decrypted in a background Isolate (CPU off main thread)
        // then forwarded immediately, keeping the proxy responsive to concurrent
        // range requests from ExoPlayer.
        int bytesSent = 0;
        int pendingSkip =
            offsetInPlainChunk; // bytes to discard from first chunk
        bool playabilityLogged = false;
        List<int> encAccum = [];

        await for (final diskBytes in file.openRead(encFileOffset)) {
          if (bytesSent >= contentLength) break;
          encAccum.addAll(diskBytes);

          // Decrypt whenever we have a full chunk boundary (or finish the stream).
          while (encAccum.length >= _e2eeEncChunkSize &&
              bytesSent < contentLength) {
            final encChunk =
                Uint8List.fromList(encAccum.sublist(0, _e2eeEncChunkSize));
            encAccum = encAccum.sublist(_e2eeEncChunkSize);

            final int skipNow = pendingSkip;
            final int wantNow = contentLength - bytesSent;
            final Uint8List plain = await Isolate.run(
              () => _decryptEncBytesFromOffset(
                  encChunk, symmetricKey, skipNow, wantNow),
            );
            pendingSkip = 0;

            if (plain.isNotEmpty) {
              if (!playabilityLogged) {
                _logMp4PlayabilityCheck('cache-hit', plain,
                    videoId: videoId, streamOffset: startPlain);
                playabilityLogged = true;
              }
              response.add(plain);
              bytesSent += plain.length;
            }
          }
        }

        // Flush any remaining partial last chunk.
        if (encAccum.isNotEmpty && bytesSent < contentLength) {
          final encChunk = Uint8List.fromList(encAccum);
          final int skipNow = pendingSkip;
          final int wantNow = contentLength - bytesSent;
          final Uint8List plain = await Isolate.run(
            () => _decryptEncBytesFromOffset(
                encChunk, symmetricKey, skipNow, wantNow),
          );
          if (plain.isNotEmpty) {
            if (!playabilityLogged) {
              _logMp4PlayabilityCheck('cache-hit', plain,
                  videoId: videoId, streamOffset: startPlain);
              playabilityLogged = true;
            }
            response.add(plain);
            bytesSent += plain.length;
          }
        }

        await response.close();

        // Persist the EXACT plaintext size from the full-file cache-hit response.
        // This ensures subsequent range requests (from ExoPlayer) use the correct
        // Content-Range total that matches the moov atom's file size. Without this,
        // _getE2eePlainLength falls back to _estimatePlainLengthFromEncrypted which
        // subtracts max PKCS7 padding, returning a value LESS than actual plaintext.
        // That causes Content-Range total mismatch → ExoPlayer rejects range responses.
        if (rangeHeader == null && fileKey != null && bytesSent > 0) {
          _recordE2eeExactPlainSize(fileKey, bytesSent);
        }

        _logStreamDeliveredToPlayer(
          'cache-hit',
          videoId: videoId,
          decryptedBytes: bytesSent,
          httpStatus: response.statusCode,
        );
        return; // ← normal cache-hit exit
      }
      // Cache miss or forceRemote — fall through to remote streaming below.
      AppLogger.log(
          '🔐 Proxy: E2EE cache file not found, fallback to remote streaming');
      final client = http.Client();
      final remoteRequest = http.Request('GET', Uri.parse(url));
      // Copy incoming headers (like Authorization) to the remote request, but exclude range headers for E2EE decryption
      request.headers.forEach((name, values) {
        if (name != 'host' &&
            name != 'content-length' &&
            name != 'range' &&
            name != 'if-range') {
          remoteRequest.headers[name] = values.join(', ');
        }
      });
      // Disable CDN compression for the same reason as the primary download path.
      remoteRequest.headers['accept-encoding'] = 'identity';
      AppLogger.log(
          '🔐 Proxy: Fallback E2EE sending remote request with headers: ${remoteRequest.headers}');
      final remoteResponse = await client.send(remoteRequest);
      AppLogger.log(
          '🔐 Proxy: Fallback E2EE remote status: ${remoteResponse.statusCode}, length: ${remoteResponse.contentLength}');

      if (remoteResponse.statusCode != 200) {
        AppLogger.log(
          '❌ Proxy: NOT PLAYABLE — race-guard remote rejected status '
          '${remoteResponse.statusCode} for video=$videoId',
        );
        response.statusCode = remoteResponse.statusCode;
        await response.close();
        client.close();
        return;
      }

      if (fileKey != null && remoteResponse.contentLength != null) {
        _recordE2eeEncryptedSize(fileKey, remoteResponse.contentLength!);
        final plainTotal = _getE2eePlainLength(fileKey);
        _applyE2eeFullFileHeaders(response, plainTotal);
        AppLogger.log(
          '🔐 Proxy: race-guard-remote Content-Length=$plainTotal '
          '(encrypted=${remoteResponse.contentLength})',
        );
      } else {
        response.headers.add('Access-Control-Allow-Origin', '*');
        response.headers.add(HttpHeaders.contentTypeHeader, 'video/mp4');
        response.statusCode = HttpStatus.ok;
      }

      final decryptor = ChunkDecryptor(symmetricKey);
      int totalWritten = 0;
      bool playabilityLogged = false;

      await for (final chunk in remoteResponse.stream) {
        final decryptedBytes = decryptor.processBytes(chunk);
        if (decryptedBytes.isNotEmpty) {
          if (!playabilityLogged) {
            _logMp4PlayabilityCheck(
              'race-guard-remote',
              decryptedBytes,
              videoId: videoId,
            );
            playabilityLogged = true;
          }
          response.add(decryptedBytes);
          totalWritten += decryptedBytes.length;
        }
      }

      final finalBytes = decryptor.finalizeStream();
      if (finalBytes.isNotEmpty) {
        if (!playabilityLogged) {
          _logMp4PlayabilityCheck(
            'race-guard-remote',
            finalBytes,
            videoId: videoId,
          );
          playabilityLogged = true;
        }
        response.add(finalBytes);
        totalWritten += finalBytes.length;
      }

      client.close();
      if (fileKey != null && totalWritten > 0) {
        _recordE2eeExactPlainSize(fileKey, totalWritten);
      }
      _logStreamDeliveredToPlayer(
        'race-guard-remote',
        videoId: videoId,
        decryptedBytes: totalWritten,
        httpStatus: remoteResponse.statusCode,
      );
      await response.close();
    } catch (e, stack) {
      AppLogger.log(
          '❌ Proxy: NOT PLAYABLE — decryption streaming failed for video=$videoId: $e\n$stack');

      // Only delete cache on ACTUAL corruption (wrong key, bad data).
      // Preserve cache on transient network errors so next play is instant.
      if (!_isTransientNetworkError(e)) {
        try {
          if (await file.exists()) {
            await file.delete();
            AppLogger.log(
                '🧹 Proxy: Deleted corrupt cache file ${file.path} after decryption failure');
          }
          final completeMarker = File('${file.path}.complete');
          if (await completeMarker.exists()) {
            await completeMarker.delete();
          }
        } catch (err) {
          AppLogger.log('⚠️ Proxy: Failed to delete corrupt cache file: $err');
        }
      } else {
        AppLogger.log(
            '🔄 Proxy: Preserving cache for video=$videoId — error is transient (network), not corruption');
      }
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _streamCacheAndDecrypt(
    String url,
    File cacheFile,
    HttpRequest request,
    Uint8List symmetricKey,
    String fileKey, {
    String? videoId,
  }) async {
    AppLogger.log(
        '🔐 Proxy: StreamCacheAndDecrypt started for $url (video=$videoId)');
    final client = http.Client();
    _activeProxyStreams[fileKey] = client;
    final response = request.response;
    IOSink? fileSink;

    try {
      final remoteRequest = http.Request('GET', Uri.parse(url));
      // Copy incoming headers (like Authorization) to the remote request, but exclude range headers for E2EE decryption
      request.headers.forEach((name, values) {
        if (name != 'host' &&
            name != 'content-length' &&
            name != 'range' &&
            name != 'if-range') {
          remoteRequest.headers[name] = values.join(', ');
        }
      });
      // Disable CDN compression so Content-Length matches actual encrypted byte count.
      // If the CDN gzip-compresses the binary, contentLength is the compressed size but
      // the stream body is the decompressed size → "Download truncated" → Source error.
      remoteRequest.headers['accept-encoding'] = 'identity';

      AppLogger.log(
          '🔐 Proxy: Sending remote E2EE request with headers: ${remoteRequest.headers}');
      final remoteResponse = await client.send(remoteRequest);
      AppLogger.log(
          '🔐 Proxy: Remote response received: status ${remoteResponse.statusCode}, length: ${remoteResponse.contentLength}');

      if (remoteResponse.statusCode != 200) {
        AppLogger.log(
          '❌ Proxy: NOT PLAYABLE — primary E2EE download rejected remote status '
          '${remoteResponse.statusCode} for video=$videoId',
        );
        response.statusCode = remoteResponse.statusCode;
        await response.close();
        return;
      }

      if (remoteResponse.contentLength != null) {
        _recordE2eeEncryptedSize(fileKey, remoteResponse.contentLength!);
        final plainTotal = _getE2eePlainLength(fileKey);
        _applyE2eeFullFileHeaders(response, plainTotal);
        AppLogger.log(
          '🔐 Proxy: primary-download Content-Length=$plainTotal '
          '(encrypted=${remoteResponse.contentLength}) for fileKey=$fileKey',
        );
      } else {
        response.headers.add('Access-Control-Allow-Origin', '*');
        response.headers.add(HttpHeaders.contentTypeHeader, 'video/mp4');
        response.statusCode = HttpStatus.ok;
      }

      int downloadedBytes = 0;
      int decryptedBytesCount = 0;
      final int? expectedLength = remoteResponse.contentLength;
      bool playabilityLogged = false;

      fileSink = cacheFile.openWrite();
      final decryptor = ChunkDecryptor(symmetricKey);

      int chunkCount = 0;
      await for (final chunk in remoteResponse.stream) {
        downloadedBytes += chunk.length;
        fileSink.add(chunk);

        final decryptedBytes = decryptor.processBytes(chunk);
        if (decryptedBytes.isNotEmpty) {
          if (!playabilityLogged) {
            _logMp4PlayabilityCheck(
              'primary-download',
              decryptedBytes,
              videoId: videoId,
            );
            playabilityLogged = true;
          }
          response.add(decryptedBytes);
          decryptedBytesCount += decryptedBytes.length;
        }
        chunkCount++;
        if (chunkCount % 100 == 0) {
          AppLogger.log(
              '🔐 Proxy: Downloaded $downloadedBytes bytes, decrypted and forwarded $decryptedBytesCount bytes...');
        }
      }

      AppLogger.log(
          '🔐 Proxy: E2EE download finished. Got $downloadedBytes bytes, expected: $expectedLength');

      // Detect truncation — do NOT mark truncated files as complete.
      // A truncated .chunk file would cause ExoPlayer to seek past the end of
      // decrypted data on next play (moov atom reports original plaintext size
      // but we only have partial encrypted data), resulting in Source error.
      final bool isTruncated =
          expectedLength != null && downloadedBytes != expectedLength;
      if (isTruncated) {
        AppLogger.log(
            '⚠️ Proxy: E2EE download truncated for video=$videoId: '
            'got $downloadedBytes bytes, expected $expectedLength — '
            'NOT marking complete (will retry on next play)');
      }

      final finalBytes = decryptor.finalizeStream();
      if (finalBytes.isNotEmpty) {
        if (!playabilityLogged) {
          _logMp4PlayabilityCheck(
            'primary-download',
            finalBytes,
            videoId: videoId,
          );
          playabilityLogged = true;
        }
        response.add(finalBytes);
        decryptedBytesCount += finalBytes.length;
      }

      await fileSink.close();
      fileSink = null;

      // Only create .complete marker if the download was NOT truncated.
      // Truncated files must be re-downloaded on next play to avoid
      // ExoPlayer seeking past the end of decrypted data.
      if (!isTruncated) {
        try {
          final completeMarker = File('${cacheFile.path}.complete');
          await completeMarker.create();
          // Persist videoId mapping for proactive background decrypt on restart
          if (videoId != null) _persistVideoIdMapping(fileKey, videoId);
          AppLogger.log('🔐 Proxy: Created .complete marker for $fileKey');
          
          // Trigger background decrypt immediately
          _backgroundDecryptToFile(fileKey, videoId: videoId);
        } catch (e) {
          AppLogger.log('⚠️ Proxy: Failed to create E2EE complete marker: $e');
        }

        _recordE2eeExactPlainSize(fileKey, decryptedBytesCount);
      } else {
        AppLogger.log(
            '⚠️ Proxy: Skipping _recordE2eeExactPlainSize for truncated download');
      }

      await response.close();
      _logStreamDeliveredToPlayer(
        'primary-download',
        videoId: videoId,
        decryptedBytes: decryptedBytesCount,
        cacheMarkedComplete: true,
        httpStatus: HttpStatus.ok,
      );
    } catch (e, stack) {
      AppLogger.log(
          '❌ Proxy: NOT PLAYABLE — stream & decrypt error for video=$videoId: $e\n$stack');
      try {
        await fileSink?.close();
      } catch (_) {}

      // Only delete cache on ACTUAL corruption (wrong key, bad data).
      // Preserve cache on transient network errors — partial .chunk is still valid
      // and can be served on-the-fly while the rest downloads in background.
      if (!_isTransientNetworkError(e)) {
        try {
          if (await cacheFile.exists()) await cacheFile.delete();
        } catch (_) {}
        try {
          final completeMarker = File('${cacheFile.path}.complete');
          if (await completeMarker.exists()) await completeMarker.delete();
        } catch (_) {}
        AppLogger.log(
            '🧹 Proxy: Deleted cache for video=$videoId — error is data corruption');
      } else {
        AppLogger.log(
            '🔄 Proxy: Preserving partial cache for video=$videoId — error is transient (network)');
      }
      try {
        response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    } finally {
      client.close();
      _activeProxyStreams.remove(fileKey);
    }
  }

  /// Chunk-aware remote range server for multi-IV E2EE uploads (2 MiB chunks).
  Future<void> _serveRemoteDecryptedRange(
    String url,
    HttpRequest request,
    Uint8List symmetricKey,
    int startPlain,
    int? endPlain, {
    String? videoId,
    String? fileKey,
  }) async {
    final response = request.response;
    final client = http.Client();
    bool playabilityLogged = false;

    try {
      final int? encTotal =
          fileKey != null ? _e2eeEncryptedLengths[fileKey] : null;
      int totalPlain = fileKey != null
          ? _getE2eePlainLength(fileKey, encryptedHint: encTotal)
          : 0;

      if (encTotal != null && totalPlain <= 0) {
        totalPlain = _estimatePlainLengthFromEncrypted(encTotal);
      }

      if (totalPlain > 0 && startPlain >= totalPlain) {
        AppLogger.log(
          '⚠️ Proxy: Rejecting out-of-bounds range start=$startPlain '
          '(totalPlain=$totalPlain) for video=$videoId',
        );
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers
            .add(HttpHeaders.contentRangeHeader, 'bytes */$totalPlain');
        await response.close();
        return;
      }

      final chunkIndex = startPlain ~/ _e2eePlainChunkSize;
      final offsetInPlainChunk = startPlain % _e2eePlainChunkSize;
      final encRangeStart = chunkIndex * _e2eeEncChunkSize;

      final remoteRequest = http.Request('GET', Uri.parse(url));
      request.headers.forEach((name, values) {
        if (name != 'host' &&
            name != 'content-length' &&
            name != 'range' &&
            name != 'if-range') {
          remoteRequest.headers[name] = values.join(', ');
        }
      });
      // Ensure CDN returns raw bytes without compression so byte-range math is exact.
      remoteRequest.headers['accept-encoding'] = 'identity';

      if (endPlain != null) {
        final endChunkIndex = endPlain ~/ _e2eePlainChunkSize;
        final endOffsetInChunk = endPlain % _e2eePlainChunkSize;
        var encRangeEnd =
            endChunkIndex * _e2eeEncChunkSize + 16 + endOffsetInChunk + 32;
        if (encTotal != null && encRangeEnd >= encTotal) {
          encRangeEnd = encTotal - 1;
        }
        remoteRequest.headers['range'] = 'bytes=$encRangeStart-$encRangeEnd';
      } else {
        remoteRequest.headers['range'] = 'bytes=$encRangeStart-';
      }

      AppLogger.log(
        '🔐 Proxy: Remote E2EE range request for video=$videoId: '
        '${remoteRequest.headers['range']} (plain start=$startPlain, '
        'chunk=$chunkIndex, offsetInChunk=$offsetInPlainChunk, totalPlain=$totalPlain)',
      );

      final remoteResponse = await client.send(remoteRequest);

      if (remoteResponse.statusCode != 200 &&
          remoteResponse.statusCode != 206) {
        AppLogger.log(
          '❌ Proxy: NOT PLAYABLE — E2EE range request failed with status '
          '${remoteResponse.statusCode} for video=$videoId',
        );
        response.statusCode = remoteResponse.statusCode;
        await response.close();
        return;
      }

      if (remoteResponse.contentLength != null) {
        AppLogger.log(
          '🔐 Proxy: E2EE range response status=${remoteResponse.statusCode}, '
          'encrypted chunk=${remoteResponse.contentLength} bytes',
        );
      }

      final remoteContentRange = remoteResponse.headers['content-range'];
      if (totalPlain <= 0 && remoteContentRange != null) {
        try {
          final totalStr = remoteContentRange.split('/').last;
          final totalEncrypted = int.parse(totalStr);
          if (fileKey != null) {
            _recordE2eeEncryptedSize(fileKey, totalEncrypted);
          }
          totalPlain = _estimatePlainLengthFromEncrypted(totalEncrypted);
        } catch (_) {}
      }

      int endPlainValue =
          endPlain ?? (totalPlain > 0 ? totalPlain - 1 : startPlain);
      if (totalPlain > 0 && endPlainValue >= totalPlain) {
        endPlainValue = totalPlain - 1;
      }
      final int bodyLength = (endPlainValue - startPlain + 1).clamp(0, 1 << 31);

      if (totalPlain > 0) {
        _applyE2eeRangeHeaders(
          response,
          startPlain: startPlain,
          endPlain: endPlainValue,
          totalPlain: totalPlain,
          bodyLength: bodyLength,
        );

        // **DIAGNOSTIC: Log E2EE remote-range response**
        _logResponseHeaders(
          'serve-remote-range',
          statusCode: 206,
          videoId: videoId ?? 'unknown',
          contentLength: bodyLength,
          contentRange: 'bytes $startPlain-$endPlainValue/$totalPlain',
          acceptRanges: 'bytes',
          contentType: 'video/mp4',
        );
      } else {
        response.headers.add('Access-Control-Allow-Origin', '*');
        response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
        response.headers.add(HttpHeaders.contentTypeHeader, 'video/mp4');
        response.statusCode = HttpStatus.partialContent;

        // **DIAGNOSTIC: Log E2EE remote-range response (no total)**
        _logResponseHeaders(
          'serve-remote-range-no-total',
          statusCode: 206,
          videoId: videoId ?? 'unknown',
          acceptRanges: 'bytes',
          contentType: 'video/mp4',
        );
      }

      final decryptor = ChunkDecryptor(symmetricKey);
      int plainBytesToSkip = offsetInPlainChunk;
      int bytesSent = 0;

      List<int> trimForRange(List<int> data) {
        var out = data;
        if (plainBytesToSkip > 0) {
          if (out.length <= plainBytesToSkip) {
            plainBytesToSkip -= out.length;
            return [];
          }
          out = out.sublist(plainBytesToSkip);
          plainBytesToSkip = 0;
        }
        final maxEmit = bodyLength - bytesSent;
        if (maxEmit <= 0) return [];
        if (out.length > maxEmit) {
          out = out.sublist(0, maxEmit);
        }
        return out;
      }

      await for (final chunk in remoteResponse.stream) {
        final decrypted = decryptor.processBytes(chunk);
        final bytesToForward = trimForRange(decrypted);
        if (bytesToForward.isNotEmpty) {
          if (!playabilityLogged) {
            _logMp4PlayabilityCheck(
              'remote-range',
              bytesToForward,
              videoId: videoId,
              streamOffset: startPlain,
            );
            playabilityLogged = true;
          }
          response.add(bytesToForward);
          bytesSent += bytesToForward.length;
        }
        if (bytesSent >= bodyLength) break;
      }

      final finalBytes = decryptor.finalizeStream();
      final tail = trimForRange(finalBytes);
      if (tail.isNotEmpty) {
        if (!playabilityLogged) {
          _logMp4PlayabilityCheck(
            'remote-range',
            tail,
            videoId: videoId,
            streamOffset: startPlain,
          );
          playabilityLogged = true;
        }
        response.add(tail);
        bytesSent += tail.length;
      }

      await response.close();
      _logStreamDeliveredToPlayer(
        'remote-range',
        videoId: videoId,
        decryptedBytes: bytesSent,
        httpStatus: response.statusCode,
      );
    } catch (e, stack) {
      AppLogger.log(
        '❌ Proxy: NOT PLAYABLE — remote decrypted range failed for video=$videoId: $e\n$stack',
      );
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    } finally {
      client.close();
    }
  }
}

final videoCacheProxy = VideoCacheProxyService();

/// Top-level function that runs inside an Isolate to decrypt a slice of
/// multi-chunk E2EE encrypted bytes without blocking the main event loop.
///
/// [encBytes]          — raw encrypted bytes starting at the chunk boundary
///                       (i.e. the first byte is the first byte of a chunk IV).
/// [symmetricKey]      — 32-byte AES-256 key.
/// [offsetInPlainChunk]— how many plaintext bytes to skip at the beginning
///                       (because the request may start mid-chunk).
/// [contentLength]     — exact number of plaintext bytes to return.
Uint8List _decryptEncBytesFromOffset(
  Uint8List encBytes,
  Uint8List symmetricKey,
  int offsetInPlainChunk,
  int contentLength,
) {
  final decryptor = ChunkDecryptor(symmetricKey);
  final List<int> decrypted = decryptor.processBytes(encBytes);
  decrypted.addAll(decryptor.finalizeStream());

  // Skip the intra-chunk offset.
  int start = offsetInPlainChunk;
  if (start >= decrypted.length) return Uint8List(0);

  // Cap to contentLength.
  int end = start + contentLength;
  if (end > decrypted.length) end = decrypted.length;

  return Uint8List.fromList(decrypted.sublist(start, end));
}

class _PlayerRange {
  final bool isPresent;
  final int startPlain;
  final int? endPlain;
  final bool isSuffixOnly;
  final int? suffixLength;

  const _PlayerRange({
    required this.isPresent,
    required this.startPlain,
    this.endPlain,
    this.isSuffixOnly = false,
    this.suffixLength,
  });
}

class ChunkDecryptor {
  final Uint8List symmetricKey;
  final int maxChunkSize = 2097184;

  int bytesReadInChunk = 0;
  Uint8List? iv;
  CBCBlockCipher? cipher;
  List<int> blockBuffer = [];
  Uint8List? lastDecryptedBlock;

  ChunkDecryptor(this.symmetricKey);

  List<int> processBytes(List<int> incomingBytes) {
    final List<int> output = [];
    int index = 0;

    while (index < incomingBytes.length) {
      if (bytesReadInChunk < 16) {
        // Accumulate IV
        iv ??= Uint8List(16);
        iv![bytesReadInChunk] = incomingBytes[index];
        bytesReadInChunk++;
        index++;

        if (bytesReadInChunk == 16) {
          // Initialize cipher
          cipher = CBCBlockCipher(AESEngine())
            ..init(
                false,
                ParametersWithIV<KeyParameter>(
                    KeyParameter(symmetricKey), iv!));
        }
      } else {
        // Accumulate ciphertext block (16 bytes)
        blockBuffer.add(incomingBytes[index]);
        bytesReadInChunk++;
        index++;

        if (blockBuffer.length == 16) {
          final ciphertextBlock = Uint8List.fromList(blockBuffer);
          blockBuffer.clear();

          final plaintextBlock = Uint8List(16);
          cipher!.processBlock(ciphertextBlock, 0, plaintextBlock, 0);

          if (lastDecryptedBlock != null) {
            output.addAll(lastDecryptedBlock!);
          }
          lastDecryptedBlock = plaintextBlock;
        }

        // Check if we reached chunk boundary
        if (bytesReadInChunk == maxChunkSize) {
          _finalizeChunk(output);
        }
      }
    }
    return output;
  }

  void _finalizeChunk(List<int> output) {
    if (lastDecryptedBlock != null) {
      // Strip PKCS7 padding
      final padLength = lastDecryptedBlock![15];
      if (padLength > 0 && padLength <= 16) {
        final strippedLength = 16 - padLength;
        output.addAll(lastDecryptedBlock!.sublist(0, strippedLength));
      } else {
        output.addAll(lastDecryptedBlock!);
      }
    }
    // Reset state for next chunk
    bytesReadInChunk = 0;
    iv = null;
    cipher = null;
    blockBuffer.clear();
    lastDecryptedBlock = null;
  }

  List<int> finalizeStream() {
    final List<int> output = [];
    _finalizeChunk(output);
    return output;
  }
}
