import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/features/ads/presentation/widgets/create_ad/media_uploader_widget.dart';

void main() {
  const targetWidths = [320.0, 360.0, 375.0, 392.0, 411.0];

  for (final width in targetWidths) {
    testWidgets('banner preview stays within a ${width.toInt()}dp viewport',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (context, child) => MaterialApp(
              home: Scaffold(
                body: MediaUploaderWidget(
                  selectedAdType: 'banner',
                  selectedImage: File('assets/icons/app_icon.png'),
                  selectedVideo: null,
                  selectedImages: const [],
                  onImageSelected: (_) {},
                  onVideoSelected: (_) {},
                  onImagesSelected: (_) {},
                  onError: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final preview = find.byType(AspectRatio);
      final previewSize = tester.getSize(preview);

      expect(previewSize.width, lessThanOrEqualTo(320));
      expect(previewSize.height, closeTo(previewSize.width / 3.2, 0.1));
      expect(tester.takeException(), isNull);
    });
  }
}
