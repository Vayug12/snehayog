import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:vayug/core/interfaces/i_dubbing_service.dart';
import 'package:vayug/features/video/dubbing/data/models/dubbing_models.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/config/app_config.dart';

/// Orchestrates the dubbing process via Backend AI.
class OnDeviceDubbingServiceImpl implements IDubbingService {
  final Map<String, bool> _cancellationTokens = {};

  @override
  void cancelDubbing(String videoId, String videoUrl) {
    AppLogger.log('🛑 DubbingService: Cancelling dubbing for $videoUrl');
    _cancellationTokens[videoUrl] = true;
    FFmpegKit.cancel();
  }

  @override
  Stream<DubbingResult> dubVideo(
    String videoId,
    String videoUrl, {
    String targetLang = 'hindi',
  }) {
    return dubLocalVideo(videoUrl, targetLang: targetLang);
  }

  /// Starts the dubbing for a video file (local or remote).
  Stream<DubbingResult> dubLocalVideo(String videoPath, {String targetLang = 'hindi'}) async* {
    _cancellationTokens[videoPath] = false;
    String effectivePath = videoPath;
    bool isRemote = videoPath.startsWith('http');
    
    if (isRemote) {
      if (!videoPath.contains('.m3u8')) {
        yield const DubbingResult(status: DubbingStatus.checking, progress: 5);
        try {
          final tempDir = await getTemporaryDirectory();
          effectivePath = p.join(tempDir.path, 'temp_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
          AppLogger.log('🌐 DubbingService: Downloading remote video');
          
          final dio = Dio();
          await dio.download(videoPath, effectivePath);
          AppLogger.log('✅ DubbingService: Download complete');
        } catch (e) {
          yield DubbingResult(status: DubbingStatus.failed, error: 'Download failed: $e');
          return;
        }
      }
    }

    final tempBaseDir = await getTemporaryDirectory();
    final dubbingTaskId = 'dub_${DateTime.now().microsecondsSinceEpoch}';
    final isolationDir = Directory(p.join(tempBaseDir.path, dubbingTaskId));
    if (!isolationDir.existsSync()) await isolationDir.create(recursive: true);
    
    final audioPath = p.join(isolationDir.path, 'extracted_audio.wav');
    final finalVideoPath = p.join(tempBaseDir.path, 'final_dubbed_${DateTime.now().millisecondsSinceEpoch}.mp4');

    try {
      // 1. Extract Audio
      yield const DubbingResult(status: DubbingStatus.extractingAudio, progress: 10);
      AppLogger.log('🎬 DubbingService: Extracting audio');
      
      const filterChain = 'highpass=f=80,lowpass=f=10000,afftdn=nf=-25,loudnorm';
      final extractSession = await FFmpegKit.execute(
        '-y -i "$effectivePath" -af "$filterChain" -ac 1 -ar 16000 "$audioPath"'
      );
      
      if (!ReturnCode.isSuccess(await extractSession.getReturnCode())) {
        throw Exception('Audio extraction failed');
      }

      // 2. Transcribe via Backend (Whisper)
      if (_cancellationTokens[videoPath] == true) throw Exception('Cancelled');
      yield const DubbingResult(status: DubbingStatus.checkingContent, progress: 25);
      
      AppLogger.log('🎙️ DubbingService: Transcribing via Backend');
      final String fullTranscript = await _transcribeViaBackend(audioPath);
      
      if (fullTranscript.trim().isEmpty) {
        yield const DubbingResult(status: DubbingStatus.notSuitable, reason: 'No vocal detected');
        return;
      }

      // 3. Translate via Backend
      if (_cancellationTokens[videoPath] == true) throw Exception('Cancelled');
      
      final hasDevanagari = RegExp(r'[\u0900-\u097F]').hasMatch(fullTranscript);
      final String detectedSourceLang = hasDevanagari ? 'hindi' : 'english';
      String effectiveTargetLang = targetLang;
      if (detectedSourceLang == targetLang) {
        effectiveTargetLang = (targetLang == 'hindi') ? 'english' : 'hindi';
      }

      yield DubbingResult(status: DubbingStatus.synthesizing, progress: 50, language: effectiveTargetLang);

      AppLogger.log('🔄 DubbingService: Translating via Backend to $effectiveTargetLang');
      final String translatedText = await _translateViaBackend(fullTranscript, effectiveTargetLang);

      // 4. Synthesize via Backend (High Quality AI4Bharat Voice)
      AppLogger.log('🔊 DubbingService: Synthesizing via Backend for $effectiveTargetLang');
      final String synthesizedAudioPath = p.join(isolationDir.path, 'synthesized_voice.wav');
      await _synthesizeViaBackend(translatedText, effectiveTargetLang, synthesizedAudioPath);

      // 5. Mux Video + New Audio
      if (_cancellationTokens[videoPath] == true) throw Exception('Cancelled');
      yield const DubbingResult(status: DubbingStatus.muxing, progress: 90);
      
      AppLogger.log('🎬 DubbingService: Muxing final video');
      final muxSession = await FFmpegKit.execute(
        '-y -i "$effectivePath" -i "$synthesizedAudioPath" -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest "$finalVideoPath"'
      );
      
      if (ReturnCode.isSuccess(await muxSession.getReturnCode())) {
        yield DubbingResult(
          status: DubbingStatus.completed,
          progress: 100,
          dubbedUrl: finalVideoPath,
          language: effectiveTargetLang,
        );
      } else {
        throw Exception('Muxing failed');
      }

    } catch (e) {
      AppLogger.log('❌ DubbingService Error: $e');
      yield DubbingResult(status: DubbingStatus.failed, error: e.toString());
    } finally {
      if (isolationDir.existsSync()) isolationDir.deleteSync(recursive: true);
      if (isRemote && !videoPath.contains('.m3u8') && File(effectivePath).existsSync()) {
        File(effectivePath).deleteSync();
      }
    }
  }

  Future<String> _transcribeViaBackend(String audioPath) async {
    final dio = Dio();
    final formData = FormData.fromMap({
      'audio': await MultipartFile.fromFile(audioPath, filename: 'audio.wav'),
    });
    final response = await dio.post('${NetworkHelper.apiBaseUrl}/dubbing/transcribe', data: formData);
    if (response.statusCode == 200) return response.data['transcript'];
    throw Exception('Transcription failed');
  }

  Future<String> _translateViaBackend(String text, String targetLang) async {
    final dio = Dio();
    try {
      final response = await dio.post(
        '${NetworkHelper.apiBaseUrl}/dubbing/translate',
        data: {
          'text': text,
          'targetLang': targetLang,
        },
      );
      final translatedText = response.data is Map<String, dynamic>
          ? response.data['translatedText']
          : null;

      if (response.statusCode != 200 ||
          translatedText is! String ||
          translatedText.trim().isEmpty) {
        throw Exception('Translation service returned an invalid response');
      }

      return translatedText;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      throw Exception(
        statusCode == 503
            ? 'Translation service is warming up. Please try again shortly.'
            : 'Translation service is unavailable. Please try again.',
      );
    }
  }

  Future<void> _synthesizeViaBackend(String text, String language, String outputPath) async {
    final dio = Dio();
    final response = await dio.post(
      '${NetworkHelper.apiBaseUrl}/dubbing/synthesize', 
      data: {'text': text, 'language': language},
      options: Options(responseType: ResponseType.bytes)
    );
    if (response.statusCode == 200) {
      await File(outputPath).writeAsBytes(response.data);
    } else {
      throw Exception('Synthesis failed');
    }
  }
}
