import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class StoryShareService {
  StoryShareService._();

  static const MethodChannel _directShareChannel =
      MethodChannel('vayug/direct_share');

  /// Captures any RepaintBoundary widget tagged with [boundaryKey] as an HD PNG file.
  static Future<File?> captureCardToPng(GlobalKey boundaryKey) async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        AppLogger.log('StoryShareService: RenderRepaintBoundary not found for key');
        return null;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/vayu_creator_story_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes, flush: true);
      return file;
    } catch (e) {
      AppLogger.log('StoryShareService: Error capturing story card: $e');
      return null;
    }
  }

  /// 1-Tap Share directly to WhatsApp with pre-attached image.
  static Future<void> shareToWhatsAppStatus({
    required File? imageFile,
    required String message,
  }) async {
    if (Platform.isAndroid && imageFile != null) {
      try {
        final bool? success = await _directShareChannel.invokeMethod<bool>(
          'shareToWhatsApp',
          {
            'filePath': imageFile.path,
            'text': message,
          },
        );
        if (success == true) return;
      } catch (e) {
        AppLogger.log(
            'StoryShareService: Direct WhatsApp native share failed: $e, falling back to SharePlus');
      }
    }

    // Fallback to system share
    await SharePlus.instance.share(
      ShareParams(
        files: imageFile != null ? [XFile(imageFile.path)] : null,
        text: message,
        subject: 'Vayug – Monetize from Day 1',
      ),
    );
  }

  /// 1-Tap Share directly to Instagram Story canvas with image.
  static Future<void> shareToInstagramStory({
    required File? imageFile,
    required String message,
    required String playStoreUrl,
  }) async {
    if (Platform.isAndroid && imageFile != null) {
      try {
        final bool? success = await _directShareChannel.invokeMethod<bool>(
          'shareToInstagramStory',
          {
            'filePath': imageFile.path,
            'contentUrl': playStoreUrl,
          },
        );
        if (success == true) return;
      } catch (e) {
        AppLogger.log(
            'StoryShareService: Direct Instagram Story native share failed: $e, falling back to SharePlus');
      }
    }

    // Fallback to system share
    await SharePlus.instance.share(
      ShareParams(
        files: imageFile != null ? [XFile(imageFile.path)] : null,
        text: message,
        subject: 'Vayug – Monetize from Day 1',
      ),
    );
  }

  /// Native System Share Sheet.
  static Future<void> shareGeneral({
    required File? imageFile,
    required String message,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: imageFile != null ? [XFile(imageFile.path)] : null,
        text: message,
        subject: 'Vayug – Monetize from Day 1',
      ),
    );
  }
}
