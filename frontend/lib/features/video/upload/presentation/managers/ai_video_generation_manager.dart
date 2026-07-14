import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/services/notification_service.dart';

enum AiVideoGenStatus { idle, submitting, generating, downloading, done, error }

class AiVideoGenerationManager extends ChangeNotifier {
  AiVideoGenStatus _status = AiVideoGenStatus.idle;
  String? _jobId;
  String? _errorMessage;
  String? _videoUrl;
  double _progress = 0.0;
  bool _isInBackground = false;

  Timer? _pollTimer;
  StreamSubscription<List<int>>? _sseSub;
  CancelToken? _sseCancel;
  bool _terminalReached = false;
  int _lastNotifiedPercent = -1;

  AiVideoGenStatus get status => _status;
  String? get jobId => _jobId;
  String? get errorMessage => _errorMessage;
  String? get videoUrl => _videoUrl;
  double get progress => _progress;
  bool get isInBackground => _isInBackground;
  bool get isRunning =>
      _status == AiVideoGenStatus.submitting ||
      _status == AiVideoGenStatus.generating ||
      _status == AiVideoGenStatus.downloading;

  void _update({
    AiVideoGenStatus? status,
    String? jobId,
    String? errorMessage,
    String? videoUrl,
    double? progress,
    bool? isInBackground,
    bool? terminalReached,
  }) {
    _status = status ?? _status;
    _jobId = jobId ?? _jobId;
    _errorMessage = errorMessage;
    _videoUrl = videoUrl ?? _videoUrl;
    _progress = progress ?? _progress;
    _isInBackground = isInBackground ?? _isInBackground;
    _terminalReached = terminalReached ?? _terminalReached;
    notifyListeners();
    if (_isInBackground) _syncBackgroundNotification();
  }

  /// Mirrors the current generation state into a system notification so the
  /// creator can watch progress from the notification shade after tapping
  /// "Run in Background".
  void _syncBackgroundNotification() {
    final ns = NotificationService();
    switch (_status) {
      case AiVideoGenStatus.done:
        _lastNotifiedPercent = -1;
        ns.showAiVideoComplete();
        break;
      case AiVideoGenStatus.error:
        _lastNotifiedPercent = -1;
        ns.showAiVideoFailed(_errorMessage ?? 'Video generation failed');
        break;
      case AiVideoGenStatus.idle:
        _lastNotifiedPercent = -1;
        ns.cancelAiVideoNotification();
        break;
      default:
        final pct = (_progress * 100).round();
        // Throttle: only push when the whole-percent value changes.
        if (pct == _lastNotifiedPercent) return;
        _lastNotifiedPercent = pct;
        final statusText = _status == AiVideoGenStatus.downloading
            ? 'Saving to gallery'
            : _status == AiVideoGenStatus.submitting
                ? 'Starting'
                : 'AI is creating your video';
        ns.showAiVideoProgress(progressPercent: pct, statusText: statusText);
    }
  }

  Future<void> generateVideo(String prompt, String? category) async {
    if (prompt.length < 5) return;

    _update(
      status: AiVideoGenStatus.submitting,
      errorMessage: null,
      videoUrl: null,
      progress: 0.0,
      terminalReached: false,
    );

    final targetUrl = '${AppConfig.baseUrl}/api/video-gen/generate';
    AppLogger.log('🚀 [AiVideoGenerate] Starting generation request to $targetUrl');

    try {
      final dio = Dio();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      AppLogger.log('🔑 JWT token present: ${token != null}');

      final data = {
        'prompt': prompt,
        if (category != null) 'category': category,
      };
      AppLogger.log('📦 Post body: $data');

      final response = await dio.post(
        targetUrl,
        data: data,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      AppLogger.log('📥 Response status code: ${response.statusCode}');
      AppLogger.log('📥 Response data: ${response.data}');

      if (response.statusCode == 202 && response.data['jobId'] != null) {
        _jobId = response.data['jobId'];
        _terminalReached = false;
        AppLogger.log('✅ Job initiated. Job ID: $_jobId');
        _update(
          status: AiVideoGenStatus.generating,
          progress: 0.1,
        );
        _startStatusStream();
      } else {
        AppLogger.warning('⚠️ Unexpected success response format or status code');
        _setError('Failed to start video generation');
      }
    } on DioException catch (e) {
      AppLogger.error(
        '❌ DioException during video generation: ${e.message}\n'
        'Status code: ${e.response?.statusCode}\n'
        'Response: ${e.response?.data}',
        e,
        e.stackTrace,
      );
      final msg = e.response?.data?['error'] ?? 'Failed to connect to server';
      _setError(msg.toString());
    } catch (e, stack) {
      AppLogger.error('❌ Unexpected error during video generation: $e', e, stack);
      _setError('Unexpected error: $e');
    }
  }

  Future<void> _startStatusStream() async {
    if (_jobId == null) return;
    final targetUrl = '${AppConfig.baseUrl}/api/video-gen/stream/$_jobId';
    AppLogger.log('📡 Opening SSE status stream for Job ID: $_jobId');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      _sseCancel = CancelToken();

      final response = await Dio().get<ResponseBody>(
        targetUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Accept': 'text/event-stream',
          },
        ),
        cancelToken: _sseCancel,
      );

      var buffer = '';
      _sseSub = response.data!.stream.listen(
        (chunk) {
          buffer += utf8.decode(chunk, allowMalformed: true);
          int idx;
          while ((idx = buffer.indexOf('\n\n')) != -1) {
            final rawEvent = buffer.substring(0, idx);
            buffer = buffer.substring(idx + 2);
            _handleSseEvent(rawEvent);
          }
        },
        onError: (e) {
          AppLogger.warning('⚠️ SSE error, falling back to polling: $e');
          _fallbackToPolling();
        },
        onDone: () {
          if (!_terminalReached) {
            AppLogger.log('ℹ️ SSE closed before completion — falling back to polling');
            _fallbackToPolling();
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      AppLogger.warning('⚠️ Failed to open SSE, falling back to polling: $e');
      _fallbackToPolling();
    }
  }

  void _handleSseEvent(String rawEvent) {
    final dataStr = rawEvent
        .split('\n')
        .where((l) => l.startsWith('data:'))
        .map((l) => l.substring(5).trim())
        .join('\n');
    if (dataStr.isEmpty) return;
    try {
      final data = jsonDecode(dataStr) as Map<String, dynamic>;
      _handleStatusData(data);
    } catch (e) {
      AppLogger.warning('⚠️ Failed to parse SSE event: $e');
    }
  }

  void _closeSse() {
    _sseSub?.cancel();
    _sseSub = null;
    try {
      _sseCancel?.cancel();
    } catch (_) {}
    _sseCancel = null;
  }

  void _fallbackToPolling() {
    _closeSse();
    if (_terminalReached) return;
    if (_pollTimer?.isActive ?? false) return;
    _startPolling();
  }

  void _startPolling() {
    AppLogger.log('🔄 Starting polling timer (every 5 seconds) for Job ID: $_jobId');
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollStatus());
  }

  Future<void> _pollStatus() async {
    if (_jobId == null) {
      AppLogger.warning('⚠️ Poll status called, but _jobId is null!');
      return;
    }

    final targetUrl = '${AppConfig.baseUrl}/api/video-gen/status/$_jobId';
    AppLogger.debug('🔍 Polling Job ID status: $_jobId (URL: $targetUrl)');

    try {
      final dio = Dio();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      final response = await dio.get(
        targetUrl,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );

      AppLogger.debug('📥 Poll response status: ${response.statusCode}');
      AppLogger.debug('📥 Poll response data: ${response.data}');

      if (response.statusCode == 200) {
        _handleStatusData(response.data as Map<String, dynamic>);
      } else {
        AppLogger.warning('⚠️ Poll returned non-200 status code: ${response.statusCode}');
      }
    } catch (e, stack) {
      AppLogger.warning('⚠️ Poll error: $e\nStacktrace:\n$stack');
    }
  }

  void _handleStatusData(Map<String, dynamic> data) {
    if (_terminalReached) return;
    final status = data['status']?.toString();

    if (status == 'completed') {
      _terminalReached = true;
      _pollTimer?.cancel();
      _closeSse();
      final streamUrl = data['videoUrl']?.toString();
      final downloadUrl = data['downloadUrl']?.toString();
      final url = (downloadUrl != null && downloadUrl.isNotEmpty)
          ? downloadUrl
          : streamUrl;
      AppLogger.log('✅ Job completed! Download URL: $url (stream: $streamUrl)');
      if (url != null && url.isNotEmpty) {
        _update(
          status: AiVideoGenStatus.downloading,
          videoUrl: url,
          progress: 0.7,
        );
        _downloadToGallery(url);
      } else {
        AppLogger.error('❌ Status is completed but no video/download URL was returned.');
        _setError('Video generated but URL not found');
      }
    } else if (status == 'failed') {
      _terminalReached = true;
      _pollTimer?.cancel();
      _closeSse();
      final errorText = data['error']?.toString() ?? 'Video generation failed';
      AppLogger.error('❌ Job failed on backend. Error: $errorText');
      _setError(errorText);
    } else {
      _update(progress: (_progress + 0.02).clamp(0.1, 0.6));
    }
  }

  Future<void> _downloadToGallery(String url) async {
    AppLogger.log('📥 Starting video download from URL: $url');
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/ai_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      AppLogger.log('📂 Downloading to temporary local path: $filePath');

      final dio = Dio();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _update(progress: 0.7 + ((received / total) * 0.25));
          }
        },
      );

      AppLogger.log('💾 Saving downloaded file to device gallery using Gal');
      await Gal.putVideo(filePath);
      AppLogger.log('🎉 Video successfully saved to gallery!');

      await _notifyDownloaded();

      _update(
        status: AiVideoGenStatus.done,
        progress: 1.0,
      );
    } catch (e, stack) {
      AppLogger.error('❌ Failed to download/save video: $e', e, stack);
      _setError('Failed to save video to gallery: $e');
    }
  }

  Future<void> _notifyDownloaded() async {
    if (_jobId == null) return;
    try {
      final dio = Dio();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      await dio.post(
        '${AppConfig.baseUrl}/api/video-gen/downloaded/$_jobId',
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
      AppLogger.log('🧹 Backend notified to clean up download copy for job $_jobId');
    } catch (e) {
      AppLogger.warning('⚠️ Failed to notify backend of download completion: $e');
    }
  }

  void _setError(String message) {
    _pollTimer?.cancel();
    _closeSse();
    _update(
      status: AiVideoGenStatus.error,
      errorMessage: message,
    );
  }

  void cancel() {
    _pollTimer?.cancel();
    _closeSse();
    _terminalReached = false;
    _lastNotifiedPercent = -1;
    NotificationService().cancelAiVideoNotification();
    _update(
      status: AiVideoGenStatus.idle,
      jobId: null,
      progress: 0.0,
      errorMessage: null,
      videoUrl: null,
    );
  }

  void background() {
    _isInBackground = true;
    notifyListeners();
    // Immediately surface a progress notification so the creator sees status
    // the moment they leave the screen.
    _syncBackgroundNotification();
  }

  void dismissBackground() {
    _isInBackground = false;
    notifyListeners();
  }

  void markDoneSeen() {
    _isInBackground = false;
    _update(status: AiVideoGenStatus.idle, jobId: null, progress: 0.0);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _closeSse();
    super.dispose();
  }
}
