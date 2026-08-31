import 'dart:io';
import 'package:dio/dio.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';

abstract class IVideoService {
  Future<List<VideoModel>> getUserVideos(String userId,
      {bool forceRefresh = false,
      int page = 1,
      int limit = 9,
      String? videoType,
      String? mediaType});

  Future<int> deleteVideos(List<String> videoIds);

  Future<bool> deleteVideo(String videoId);

  Future<Map<String, dynamic>?> getVideoProcessingStatus(String videoId);

  Future<Map<String, dynamic>> uploadVideo({
    required File videoFile,
    required String title,
    String? description,
    String? link,
    String? category,
    List<String>? tags,
    String? videoType,
    Function(double)? onProgress,
    CancelToken? cancelToken,
    List<String>? crossPostPlatforms,
    String? seriesId,
    int? episodeNumber,
    List<QuizModel>? quizzes,
    List<String>? allowedSubscribers,
    List<String>? targetProfessionIds,
    File? thumbnailFile,
  });

  Future<VideoModel> toggleLike(String videoId);
  
  Future<bool> toggleSave(String videoId);

  // Add more as needed by the app
}
