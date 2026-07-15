import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vayug/core/interfaces/i_video_service.dart';
import 'package:vayug/core/interfaces/i_video_upload_service.dart';
import 'package:vayug/features/video/upload/presentation/managers/upload_state_manager.dart';

class _MockVideoService extends Mock implements IVideoService {}

class _ControlledUploadService implements IVideoUploadService {
  final StreamController<double> _progress = StreamController<double>.broadcast();
  final Completer<String?> uploadCompleter = Completer<String?>();
  bool wasCancelled = false;

  @override
  Stream<double> get uploadProgress => _progress.stream;

  @override
  Future<bool> validateVideo(File videoFile) async => true;

  @override
  Future<File?> generateThumbnail(File videoFile) async => null;

  @override
  Future<String?> uploadVideo({
    required File videoFile,
    File? thumbnailFile,
    required String title,
    required String description,
    Map<String, dynamic>? metadata,
  }) => uploadCompleter.future;

  @override
  void cancelUpload() => wasCancelled = true;
}

void main() {
  test('cancelled upload cannot set an error after a new video is selected', () async {
    final uploadService = _ControlledUploadService();
    final manager = UploadStateManager(
      uploadService: uploadService,
      videoService: _MockVideoService(),
    );
    final firstVideo = File('first.mp4');
    final secondVideo = File('second.mp4');

    manager.setVideo(firstVideo);
    final firstUpload = manager.startUpload(title: 'First', description: '');
    await Future<void>.delayed(Duration.zero);

    manager.cancelUpload();
    manager.setVideo(secondVideo);
    uploadService.uploadCompleter.complete(null);
    await firstUpload;

    expect(uploadService.wasCancelled, isTrue);
    expect(manager.selectedVideo, secondVideo);
    expect(manager.status, UploadStatus.idle);
    expect(manager.errorMessage, isNull);
  });

  test('reset clears the upload metadata', () {
    final manager = UploadStateManager(
      uploadService: _ControlledUploadService(),
      videoService: _MockVideoService(),
    );

    manager.setVideo(File('video.mp4'));
    manager.setThumbnail(File('thumbnail.jpg'));
    manager.setCategory('Fitness');
    manager.setTags(['morning', 'yoga']);
    manager.reset();

    expect(manager.selectedVideo, isNull);
    expect(manager.selectedThumbnail, isNull);
    expect(manager.category, isNull);
    expect(manager.tags, isEmpty);
    expect(manager.errorMessage, isNull);
  });
}
