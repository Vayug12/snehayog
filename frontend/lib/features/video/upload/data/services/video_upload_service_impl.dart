import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:vayug/core/interfaces/i_video_service.dart';
import 'package:vayug/core/interfaces/i_video_upload_service.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class VideoUploadService implements IVideoUploadService {
  final IVideoService _videoService;
  final StreamController<double> _progressController = StreamController<double>.broadcast();
  CancelToken? _cancelToken;

  VideoUploadService({required IVideoService videoService}) : _videoService = videoService;

  @override
  Stream<double> get uploadProgress => _progressController.stream;

  @override
  Future<bool> validateVideo(File videoFile) async {
    try {
      if (!await videoFile.exists()) return false;
      
      final fileSize = await videoFile.length();
      if (fileSize > 700 * 1024 * 1024) return false; // 700MB limit

      final fileName = videoFile.path.split('/').last.toLowerCase();
      final allowedExtensions = ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'];
      final fileExtension = fileName.split('.').last;
      
      if (!allowedExtensions.contains(fileExtension)) return false;

      // Check for duplicates using hash
      final hash = await _calculateFileHash(videoFile);
      final isDuplicate = await _checkForDuplicate(hash);
      
      return !isDuplicate;
    } catch (e) {
      AppLogger.log('❌ VideoUploadService: Validation error: $e');
      return false;
    }
  }

  Future<String> _calculateFileHash(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<bool> _checkForDuplicate(String hash) async {
    try {
      // Using a generic Dio/Http call here or delegating to a specialized service
      // For this example, we assume success if we can't reach the server to avoid blocking
      return false; 
    } catch (e) {
      return false;
    }
  }

  @override
  Future<File?> generateThumbnail(File videoFile) async {
    return null;
  }

  @override
  Future<String?> uploadVideo({
    required File videoFile,
    File? thumbnailFile,
    required String title,
    required String description,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _cancelToken = CancelToken();
      _progressController.add(0.0);

      final response = await _videoService.uploadVideo(
        videoFile: videoFile,
        title: title,
        description: description,
        thumbnailFile: thumbnailFile,
        category: metadata?['category'],
        tags: List<String>.from(metadata?['tags'] ?? []),
        videoType: metadata?['videoType'] ?? 'yog',
        crossPostPlatforms: List<String>.from(metadata?['crossPostPlatforms'] ?? []),
        link: metadata?['link'],
        allowedSubscribers: metadata?['allowedSubscribers'] != null
            ? List<String>.from(metadata?['allowedSubscribers'])
            : null,
        targetProfessionIds:
            List<String>.from(metadata?['targetProfessionIds'] ?? const []),
        // Series placement and quizzes travel through metadata so the upload
        // contract stays a single generic map instead of growing a parameter
        // per feature.
        seriesId: metadata?['seriesId'] as String?,
        episodeNumber: metadata?['episodeNumber'] as int?,
        quizzes: (metadata?['quizzes'] as List?)?.cast<QuizModel>(),
        onProgress: (progress) {
          _progressController.add(progress);
        },
        cancelToken: _cancelToken,
      );

      final videoData = response['video'] ?? response;
      return videoData['id']?.toString() ?? videoData['_id']?.toString();
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        AppLogger.log('🚫 VideoUploadService: Upload cancelled');
      } else {
        AppLogger.log('❌ VideoUploadService: Upload failed: $e');
      }
      return null;
    }
  }

  @override
  void cancelUpload() {
    _cancelToken?.cancel('User cancelled upload');
    _cancelToken = null;
  }
  
  void dispose() {
    _progressController.close();
  }
}
