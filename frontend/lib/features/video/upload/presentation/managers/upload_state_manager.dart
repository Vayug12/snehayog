import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vayug/core/interfaces/i_video_upload_service.dart';
import 'package:vayug/core/interfaces/i_video_service.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/upload/domain/models/episode_draft.dart';
import 'package:vayug/shared/services/notification_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

enum UploadStatus { idle, preparing, uploading, validation, processing, finalizing, success, error }

/// Everything one upload needs, captured once at submit time.
///
/// Held for the lifetime of the upload so a series retry can resume with the
/// exact same metadata instead of asking the UI to hand it over again.
class _UploadRequest {
  final String title;
  final String description;
  final String? link;
  final File? thumbnail;
  final List<String> tags;
  final List<String>? platforms;
  final List<String>? allowedSubscribers;
  final List<QuizModel>? quizzes;

  const _UploadRequest({
    required this.title,
    required this.description,
    this.link,
    this.thumbnail,
    this.tags = const [],
    this.platforms,
    this.allowedSubscribers,
    this.quizzes,
  });
}

/// Turns a progress stream into a time-remaining estimate.
///
/// Rate is measured over a trailing window rather than since the start, so a
/// slow handshake or a stalled chunk does not poison the estimate for the rest
/// of the upload. When the window has not seen enough real movement it returns
/// null — an honest "no estimate yet" beats a number that jumps around.
class _EtaEstimator {
  static const Duration _window = Duration(seconds: 20);
  static const Duration _minSpan = Duration(seconds: 3);
  static const Duration _maxEstimate = Duration(hours: 2);

  final List<(DateTime, double)> _samples = [];

  void reset() => _samples.clear();

  void add(double progress) {
    final now = DateTime.now();
    _samples.add((now, progress));
    while (_samples.length > 2 && now.difference(_samples.first.$1) > _window) {
      _samples.removeAt(0);
    }
  }

  Duration? estimate(double progress) {
    if (_samples.length < 2 || progress <= 0 || progress >= 1) return null;

    final first = _samples.first;
    final last = _samples.last;
    final spanMs = last.$1.difference(first.$1).inMilliseconds;
    final gained = last.$2 - first.$2;
    if (spanMs < _minSpan.inMilliseconds || gained <= 0) return null;

    final remainingMs = (1.0 - progress) * spanMs / gained;
    if (!remainingMs.isFinite || remainingMs <= 0) return null;

    return Duration(
      milliseconds:
          remainingMs.clamp(1000, _maxEstimate.inMilliseconds.toDouble()).round(),
    );
  }
}

/// One episode as it will actually be sent.
class _EpisodeUpload {
  final File file;
  final String title;
  final File? thumbnail;
  final List<QuizModel>? quizzes;

  const _EpisodeUpload({
    required this.file,
    required this.title,
    this.thumbnail,
    this.quizzes,
  });
}

class UploadStateManager extends ChangeNotifier {
  final IVideoUploadService _uploadService;
  final IVideoService _videoService; // For status polling

  UploadStateManager({
    required IVideoUploadService uploadService,
    required IVideoService videoService,
  }) : _uploadService = uploadService, _videoService = videoService;

  static const Set<UploadStatus> _inFlightStatuses = {
    UploadStatus.preparing,
    UploadStatus.validation,
    UploadStatus.uploading,
    UploadStatus.processing,
    UploadStatus.finalizing,
  };

  // --- Core State ---
  File? _selectedVideo;
  File? get selectedVideo => _selectedVideo;

  File? _selectedThumbnail;
  File? get selectedThumbnail => _selectedThumbnail;

  UploadStatus _status = UploadStatus.idle;
  UploadStatus get status => _status;

  double _progress = 0.0;
  double get progress => _progress;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _currentPhase = 'preparation';
  String get currentPhase => _currentPhase;

  // --- Metadata State ---
  String? _selectedCategory;
  String? get selectedCategory => _selectedCategory;
  String? get category => _selectedCategory;

  List<String> _tags = [];
  List<String> get tags => _tags;

  Map<String, String> _crossPostStatus = {};
  Map<String, String> get crossPostStatus => _crossPostStatus;

  // --- Series State ---
  // Episodes 2..N only. Episode 1 is always [_selectedVideo], which keeps a
  // single source of truth for the primary file no matter what the series
  // editor does.
  List<EpisodeDraft> _extraEpisodes = const [];
  List<EpisodeDraft> get extraEpisodes => _extraEpisodes;

  bool get isSeries => _extraEpisodes.isNotEmpty;
  int get totalEpisodes => _extraEpisodes.length + 1;

  String? _activeSeriesId;

  int _episodesUploaded = 0;
  int get episodesUploaded => _episodesUploaded;

  /// Ids of everything already accepted by the server, kept across a retry so
  /// the processing watch covers the whole series and not just the resumed tail.
  final List<String> _uploadedVideoIds = [];

  int _episodesReady = 0;

  /// How many episodes the server has finished encoding.
  int get episodesReady => _episodesReady;

  /// 1-based number of the episode currently being sent.
  int get currentEpisodeNumber => (_episodesUploaded + 1).clamp(1, totalEpisodes);

  final _EtaEstimator _eta = _EtaEstimator();

  /// Best guess at the time left, or null while the rate is too noisy to say
  /// anything honest. Callers must render nothing rather than a fake number.
  Duration? get estimatedTimeRemaining =>
      isUploadInFlight ? _eta.estimate(_progress) : null;

  /// A series that died part-way can be resumed instead of restarted, so the
  /// episodes already on the server are never orphaned or duplicated.
  bool get canRetrySeries =>
      isSeries &&
      _status == UploadStatus.error &&
      _episodesUploaded > 0 &&
      _episodesUploaded < totalEpisodes &&
      _lastRequest != null;

  _UploadRequest? _lastRequest;

  // --- Background State ---
  bool _isBackgrounded = false;

  /// True once the user has chosen to stop watching this upload. The work keeps
  /// running; only the UI's relationship to it changes.
  bool get isBackgrounded => _isBackgrounded;

  bool get isUploadInFlight => _inFlightStatuses.contains(_status);

  /// A backgrounded upload that has since finished — the UI owes the user a
  /// result banner even though they walked away.
  bool get hasUnseenResult =>
      _isBackgrounded &&
      (_status == UploadStatus.success || _status == UploadStatus.error);

  // Every upload gets its own id.  Cancelling (or replacing) an upload
  // invalidates that id so a late result from the old HTTP request cannot
  // overwrite the state for the next video.
  int _uploadOperationId = 0;

  bool _isCurrentOperation(int operationId) =>
      operationId == _uploadOperationId;

  // --- Setters ---
  void setVideo(File video) {
    _invalidateActiveUpload();
    _clearState();
    _selectedVideo = video;
    notifyListeners();
  }

  void setThumbnail(File? thumbnail) {
    _selectedThumbnail = thumbnail;
    notifyListeners();
  }

  void setCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setTags(List<String> tags) {
    _tags = tags;
    notifyListeners();
  }

  /// Turns the current draft into a series (or back into a single video when
  /// [episodes] is empty). Ignored mid-upload — the episode list is baked into
  /// the request the moment it starts.
  void setExtraEpisodes(List<EpisodeDraft> episodes) {
    if (isUploadInFlight) return;
    _extraEpisodes = List.unmodifiable(episodes);
    _activeSeriesId = null;
    _episodesUploaded = 0;
    notifyListeners();
  }

  // --- Actions ---

  Future<void> startUpload({
    required String title,
    required String description,
    String? link,
    File? thumbnailFile,
    List<String>? tags,
    List<String>? platforms,
    List<String>? allowedSubscribers,
    List<QuizModel>? quizzes,
  }) async {
    if (_selectedVideo == null) {
      _setError('Please select a video first');
      return;
    }
    // Guards against a double tap queuing the same video twice.
    if (isUploadInFlight) return;

    final request = _UploadRequest(
      title: title,
      description: description,
      link: link,
      thumbnail: thumbnailFile ?? _selectedThumbnail,
      tags: tags ?? _tags,
      platforms: platforms,
      allowedSubscribers: allowedSubscribers,
      quizzes: quizzes,
    );
    _lastRequest = request;
    _activeSeriesId = null;
    _episodesUploaded = 0;
    _episodesReady = 0;
    _uploadedVideoIds.clear();
    _eta.reset();

    final operationId = ++_uploadOperationId;

    if (isSeries) {
      await _runSeriesUpload(operationId, request);
    } else {
      await _runSingleUpload(operationId, request);
    }
  }

  /// Resumes a series at the first episode that did not make it, reusing the
  /// original series id so the retried episodes join the same series.
  Future<void> retryFailedEpisodes() async {
    if (!canRetrySeries) return;
    // Ids from the first attempt are kept so the processing watch still covers
    // the whole series, but the rate history is stale — drop it.
    _eta.reset();
    final operationId = ++_uploadOperationId;
    await _runSeriesUpload(operationId, _lastRequest!, startIndex: _episodesUploaded);
  }

  /// Detaches the UI from an in-flight upload without touching the upload.
  void runInBackground() {
    if (!isUploadInFlight) return;
    _isBackgrounded = true;
    notifyListeners();
  }

  void bringToForeground() {
    if (!_isBackgrounded) return;
    _isBackgrounded = false;
    notifyListeners();
  }

  // --- Single video ---

  Future<void> _runSingleUpload(int operationId, _UploadRequest request) async {
    final videoFile = _selectedVideo!;

    _status = UploadStatus.preparing;
    _currentPhase = 'preparation';
    _errorMessage = null;
    _setProgress(0.0);
    notifyListeners();

    // 1. Validate
    final isValid = await _uploadService.validateVideo(videoFile);
    if (!_isCurrentOperation(operationId)) return;
    if (!isValid) {
      _setError('Invalid video file or size too large (Max 700MB)');
      return;
    }

    // 2. Setup Progress Listener
    final progressSubscription = _uploadService.uploadProgress.listen((p) {
      if (_isCurrentOperation(operationId) &&
          _status == UploadStatus.uploading) {
        _setProgress(0.1 + (p * 0.4)); // Upload is 10% to 50% of total
        notifyListeners();
      }
    });

    try {
      // 3. Upload
      _status = UploadStatus.uploading;
      _currentPhase = 'upload';
      notifyListeners();

      final videoId = await _uploadService.uploadVideo(
        videoFile: videoFile,
        thumbnailFile: request.thumbnail,
        title: request.title,
        description: request.description,
        metadata: _metadataFor(request, quizzes: request.quizzes),
      );

      if (!_isCurrentOperation(operationId)) return;

      if (videoId != null) {
        // 4. Wait for Processing
        _uploadedVideoIds.add(videoId);
        final isProcessed = await _awaitProcessing(operationId);
        if (!_isCurrentOperation(operationId)) return;
        if (isProcessed) {
          _markCompleted();
        } else {
          _setError('Video processing failed or timed out.');
        }
      } else {
        _setError('Upload failed. Please try again.');
      }
    } catch (e) {
      if (_isCurrentOperation(operationId)) {
        _setError('An unexpected error occurred: $e');
      }
    } finally {
      await progressSubscription.cancel();
      if (_isCurrentOperation(operationId)) notifyListeners();
    }
  }

  // --- Series ---

  /// Uploads every episode under one series id, in list order, then watches the
  /// whole series through server-side processing.
  ///
  /// Episodes are encoded in parallel by the backend, so processing is watched
  /// once for all of them rather than serially per episode — five sequential
  /// 15-minute waits would be unusable.
  Future<void> _runSeriesUpload(
    int operationId,
    _UploadRequest request, {
    int startIndex = 0,
  }) async {
    final episodes = _composeEpisodes(request);

    _status = UploadStatus.preparing;
    _currentPhase = 'preparation';
    _errorMessage = null;
    _episodesUploaded = startIndex;
    _setProgress(_uploadShare(startIndex, episodes.length));
    notifyListeners();

    // Validate the whole series up front. Discovering episode 4 is oversized
    // only after three uploads have landed is exactly the partial-failure mess
    // this flow is meant to prevent.
    _status = UploadStatus.validation;
    notifyListeners();
    for (var i = startIndex; i < episodes.length; i++) {
      final isValid = await _uploadService.validateVideo(episodes[i].file);
      if (!_isCurrentOperation(operationId)) return;
      if (!isValid) {
        _setError(
            'Episode ${i + 1} ("${episodes[i].title}") is not a supported video or is over 700MB. Remove or replace it and try again.');
        return;
      }
    }

    final seriesId = _activeSeriesId ??= _generateSeriesId();
    AppLogger.log('UploadStateManager: series $seriesId, ${episodes.length} episodes, resuming at $startIndex');

    final progressSubscription = _uploadService.uploadProgress.listen((p) {
      if (!_isCurrentOperation(operationId) ||
          _status != UploadStatus.uploading) {
        return;
      }
      final withinEpisode = p.clamp(0.0, 1.0);
      _setProgress(
          _uploadShare(_episodesUploaded + withinEpisode, episodes.length));
      notifyListeners();
    });

    try {
      _status = UploadStatus.uploading;
      _currentPhase = 'upload';
      notifyListeners();

      for (var i = startIndex; i < episodes.length; i++) {
        if (!_isCurrentOperation(operationId)) return;
        final episode = episodes[i];

        final videoId = await _uploadService.uploadVideo(
          videoFile: episode.file,
          thumbnailFile: episode.thumbnail,
          title: episode.title,
          description: request.description,
          metadata: _metadataFor(
            request,
            quizzes: episode.quizzes,
            seriesId: seriesId,
            episodeNumber: i + 1,
          ),
        );

        if (!_isCurrentOperation(operationId)) return;

        if (videoId == null) {
          _setError(
              'Episode ${i + 1} failed to upload. $i of ${episodes.length} episodes are safe — retry to resume from episode ${i + 1}.');
          return;
        }

        _uploadedVideoIds.add(videoId);
        _episodesUploaded = i + 1;
        _setProgress(_uploadShare(_episodesUploaded, episodes.length));
        notifyListeners();
      }

      final isProcessed = await _awaitProcessing(operationId);
      if (!_isCurrentOperation(operationId)) return;
      if (isProcessed) {
        _markCompleted();
      } else {
        final stuck = episodes.length - _episodesReady;
        _setError(
            '$stuck of ${episodes.length} episodes could not be processed. They stay in your profile and will retry on our side.');
      }
    } catch (e) {
      if (_isCurrentOperation(operationId)) {
        _setError('Series upload failed at episode ${_episodesUploaded + 1}: $e');
      }
    } finally {
      await progressSubscription.cancel();
    }
  }

  /// Episode 1 is the main-flow video and carries the shared assets (custom
  /// cover, quizzes); the extras carry their own titles only.
  List<_EpisodeUpload> _composeEpisodes(_UploadRequest request) {
    return <_EpisodeUpload>[
      _EpisodeUpload(
        file: _selectedVideo!,
        title: request.title,
        thumbnail: request.thumbnail,
        quizzes: request.quizzes,
      ),
      ..._extraEpisodes.map(
        (draft) => _EpisodeUpload(file: draft.file, title: draft.title),
      ),
    ];
  }

  Map<String, dynamic> _metadataFor(
    _UploadRequest request, {
    List<QuizModel>? quizzes,
    String? seriesId,
    int? episodeNumber,
  }) {
    return {
      'link': request.link,
      'tags': request.tags,
      'crossPostPlatforms': request.platforms,
      'category': _selectedCategory,
      'allowedSubscribers': request.allowedSubscribers,
      'quizzes': quizzes,
      'seriesId': seriesId,
      'episodeNumber': episodeNumber,
    };
  }

  String _generateSeriesId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';

  /// Watches every uploaded video through server-side encoding, driving the
  /// 50–100% half of [progress].
  ///
  /// Handles one video or twenty the same way: FCM resolves an episode the
  /// instant the backend finishes it, and the poll is the fallback for pushes
  /// that never arrive. Each tick queries only the episodes still pending, in
  /// one parallel batch, so a five-episode series costs one round of requests
  /// per tick rather than five sequential waits.
  Future<bool> _awaitProcessing(int operationId) async {
    final videoIds = List<String>.from(_uploadedVideoIds);
    if (videoIds.isEmpty) return false;

    const maxAttempts = 180; // 15 minutes at 5s per attempt.
    const tick = Duration(seconds: 5);

    final pending = <String>{...videoIds};
    final failed = <String>{};
    // videoId -> 0..1 completion of that single video's encode.
    final perVideo = <String, double>{for (final id in videoIds) id: 0.0};

    _status = UploadStatus.processing;
    _currentPhase = 'processing';
    _setProgress(_processingShare(perVideo, videoIds.length));
    notifyListeners();

    StreamSubscription<RemoteMessage>? sub;
    try {
      sub = NotificationService.onMessageStream.listen((message) {
        if (!_isCurrentOperation(operationId)) return;
        final data = message.data;
        if (data['type'] != 'video_processed') return;

        final id = data['videoId']?.toString();
        if (id == null || !pending.contains(id)) return;

        final status = data['status']?.toString();
        AppLogger.log('📱 FCM: video $id processing status: $status');
        if (status == 'completed') {
          pending.remove(id);
          perVideo[id] = 1.0;
        } else if (status == 'failed') {
          pending.remove(id);
          failed.add(id);
          perVideo[id] = 1.0;
        } else {
          return;
        }
        _publishProcessingProgress(perVideo, videoIds.length);
      });
    } catch (e) {
      AppLogger.log('⚠️ Failed to initialize FCM stream listener: $e');
    }

    try {
      for (var attempt = 0; attempt < maxAttempts && pending.isNotEmpty; attempt++) {
        if (!_isCurrentOperation(operationId)) return false;

        final batch = pending.toList();
        final results = await Future.wait(
          batch.map((id) async {
            try {
              return MapEntry(id, await _videoService.getVideoProcessingStatus(id));
            } catch (_) {
              return MapEntry(id, null); // A single bad poll is not fatal.
            }
          }),
        );
        if (!_isCurrentOperation(operationId)) return false;

        for (final entry in results) {
          final video = entry.value?['video'] as Map<String, dynamic>?;
          final status = video?['processingStatus']?.toString().toLowerCase();
          final percent = (video?['processingProgress'] as num?)?.toDouble();

          if (status == 'completed' || status == 'ready') {
            pending.remove(entry.key);
            perVideo[entry.key] = 1.0;
          } else if (status == 'failed') {
            pending.remove(entry.key);
            failed.add(entry.key);
            perVideo[entry.key] = 1.0;
          } else if (percent != null && percent > 0) {
            perVideo[entry.key] = (percent / 100).clamp(0.0, 0.99);
          } else {
            // No server-side number: creep forward so the bar never looks
            // frozen, but never backwards and never all the way to done.
            final creep = (attempt / maxAttempts) * 0.8;
            perVideo[entry.key] = max(perVideo[entry.key] ?? 0.0, creep);
          }
        }

        _publishProcessingProgress(perVideo, videoIds.length);
        if (pending.isEmpty) break;
        await Future.delayed(tick);
      }
    } finally {
      await sub?.cancel();
    }

    return pending.isEmpty && failed.isEmpty;
  }

  void _publishProcessingProgress(Map<String, double> perVideo, int total) {
    _episodesReady = perVideo.values.where((v) => v >= 1.0).length;
    _setProgress(_processingShare(perVideo, total));
    notifyListeners();
  }

  /// Uploading owns the first half of the bar, processing the second.
  double _uploadShare(num episodesDone, int total) =>
      total == 0 ? 0.0 : (episodesDone / total) * 0.5;

  double _processingShare(Map<String, double> perVideo, int total) {
    if (total == 0) return 0.5;
    final done = perVideo.values.fold<double>(0, (sum, v) => sum + v);
    return 0.5 + (done / total) * 0.5;
  }

  void _setProgress(double value) {
    _progress = value.clamp(0.0, 1.0);
    _eta.add(_progress);
  }

  void _markCompleted() {
    _status = UploadStatus.success;
    _currentPhase = 'completed';
    _setProgress(1.0);
  }

  void cancelUpload() {
    _invalidateActiveUpload();
    _clearState();
    notifyListeners();
  }

  void _invalidateActiveUpload() {
    _uploadOperationId++;
    _uploadService.cancelUpload();
  }

  void _clearState() {
    _selectedVideo = null;
    _selectedThumbnail = null;
    _selectedCategory = null;
    _tags = [];
    _status = UploadStatus.idle;
    _currentPhase = 'preparation';
    _progress = 0.0;
    _errorMessage = null;
    _crossPostStatus = {};
    _extraEpisodes = const [];
    _activeSeriesId = null;
    _episodesUploaded = 0;
    _episodesReady = 0;
    _uploadedVideoIds.clear();
    _lastRequest = null;
    _isBackgrounded = false;
    _eta.reset();
  }

  void _setError(String message) {
    _status = UploadStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  void reset() {
    _invalidateActiveUpload();
    _clearState();
    notifyListeners();
  }
}
