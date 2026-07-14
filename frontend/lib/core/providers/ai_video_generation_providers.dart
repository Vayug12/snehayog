import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/features/video/upload/presentation/managers/ai_video_generation_manager.dart';

final aiVideoGenerationManagerProvider =
    ChangeNotifierProvider<AiVideoGenerationManager>((ref) {
  return AiVideoGenerationManager();
});
