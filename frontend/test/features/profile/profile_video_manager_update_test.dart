import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vayug/features/profile/core/presentation/managers/sub_managers/profile_video_manager.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/core/interfaces/i_video_service.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:vayug/shared/managers/smart_cache_manager.dart';

class MockVideoService extends Mock implements IVideoService {}
class MockAuthService extends Mock implements IAuthService {}
class MockSmartCacheManager extends Mock implements SmartCacheManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProfileVideoManager videoManager;
  late MockVideoService mockVideoService;
  late MockAuthService mockAuthService;
  late MockSmartCacheManager mockCacheManager;

  final testVideo = VideoModel(
    id: 'video_1',
    videoName: 'Test Video',
    videoUrl: 'https://example.com/video.mp4',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    likes: 10,
    views: 100,
    shares: 5,
    uploadedAt: DateTime.now(),
    uploader: Uploader(id: 'user_1', name: 'Test User', profilePic: ''),
    likedBy: [],
    videoType: 'yog',
    aspectRatio: 9 / 16,
    duration: const Duration(minutes: 1),
    seriesId: null,
    episodes: null,
  );

  setUp(() {
    mockVideoService = MockVideoService();
    mockAuthService = MockAuthService();
    mockCacheManager = MockSmartCacheManager();

    when(() => mockAuthService.getUserData()).thenAnswer((_) async => {
      'id': 'user_1',
      'googleId': 'user_1',
    });

    videoManager = ProfileVideoManager(
      videoService: mockVideoService,
      authService: mockAuthService,
      smartCacheManager: mockCacheManager,
    );
  });

  group('updateVideoInList', () {
    test('should update video seriesId when result comes from EditVideoDetails',
        () async {
      // ARRANGE: Load a video without series data
      when(() => mockVideoService.getUserVideos(
            any(),
            forceRefresh: any(named: 'forceRefresh'),
            page: any(named: 'page'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [testVideo]);

      await videoManager.loadUserVideos('user_1');

      expect(videoManager.userVideos, hasLength(1));
      expect(videoManager.userVideos.first.seriesId, isNull);

      // ACT: Simulate what happens when EditVideoDetails pops with result
      // This is the method that SHOULD exist after the fix
      final updatedData = {
        'videoName': 'Test Video',
        'link': '',
        'tags': <String>[],
        'quizzes': <dynamic>[],
        'episodes': [
          {'id': 'video_1', 'videoName': 'Test Video'},
          {'id': 'video_2', 'videoName': 'Episode 2'},
        ],
        'seriesId': 'series_abc',
      };

      // BUG: This method doesn't exist yet - test will FAIL
      videoManager.updateVideoInList('video_1', updatedData);

      // ASSERT: Video should now have series data
      final updatedVideo = videoManager.userVideos.first;
      expect(updatedVideo.seriesId, equals('series_abc'));
      expect(updatedVideo.episodes, isNotNull);
      expect(updatedVideo.episodes, hasLength(2));
    });

    test('should not affect other videos in the list', () async {
      final otherVideo = VideoModel(
        id: 'video_2',
        videoName: 'Other Video',
        videoUrl: 'https://example.com/other.mp4',
        thumbnailUrl: 'https://example.com/other.jpg',
        likes: 5,
        views: 50,
        shares: 2,
        uploadedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        uploader: Uploader(id: 'user_1', name: 'Test User', profilePic: ''),
        likedBy: [],
        videoType: 'yog',
        aspectRatio: 9 / 16,
        duration: const Duration(minutes: 1),
      );

      when(() => mockVideoService.getUserVideos(
            any(),
            forceRefresh: any(named: 'forceRefresh'),
            page: any(named: 'page'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [testVideo, otherVideo]);

      await videoManager.loadUserVideos('user_1');
      expect(videoManager.userVideos, hasLength(2));

      // ACT: Update only video_1
      final updatedData = {
        'videoName': 'Updated Video',
        'seriesId': 'series_xyz',
        'episodes': [
          {'id': 'video_1', 'videoName': 'Updated Video'},
        ],
      };

      videoManager.updateVideoInList('video_1', updatedData);

      // ASSERT: Find by ID (sort may reorder)
      final updated = videoManager.userVideos.firstWhere((v) => v.id == 'video_1');
      final untouched = videoManager.userVideos.firstWhere((v) => v.id == 'video_2');
      expect(updated.seriesId, equals('series_xyz'));
      expect(untouched.seriesId, isNull);
    });

    test('should handle video not found in list gracefully', () {
      // ACT: Try to update a video that doesn't exist
      // Should not throw
      expect(
        () => videoManager.updateVideoInList('nonexistent_video', {
          'videoName': 'Ghost',
          'seriesId': 'series_999',
        }),
        returnsNormally,
      );
    });
  });
}
