import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:vayug/shared/utils/banner_image_processor.dart';

/// **MediaUploaderWidget - Handles media file uploads for ads**
class MediaUploaderWidget extends ConsumerStatefulWidget {
  final String selectedAdType;
  final File? selectedImage;
  final File? selectedVideo;
  final List<File> selectedImages;
  final Function(File?) onImageSelected;
  final Function(File?) onVideoSelected;
  final Function(List<File>) onImagesSelected;
  final Function(String) onError;

  // **NEW: Validation states**
  final bool? isMediaValid;
  final String? mediaError;

  const MediaUploaderWidget({
    super.key,
    required this.selectedAdType,
    required this.selectedImage,
    required this.selectedVideo,
    required this.selectedImages,
    required this.onImageSelected,
    required this.onVideoSelected,
    required this.onImagesSelected,
    required this.onError,
    // **NEW: Optional validation parameters**
    this.isMediaValid,
    this.mediaError,
  });

  @override
  ConsumerState<MediaUploaderWidget> createState() =>
      _MediaUploaderWidgetState();
}

class _MediaUploaderWidgetState extends ConsumerState<MediaUploaderWidget> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Media Content',
              style: AppTypography.headlineSmall.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.white,
              ),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: (widget.isMediaValid == false)
                          ? AppColors.error
                          : AppColors.borderPrimary,
                      width: (widget.isMediaValid == false) ? 2.0 : 1.0,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _buildMediaPreview(),
                ),
                if (widget.isMediaValid == false && widget.mediaError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.mediaError!,
                      style:
                          const TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: _getImageButtonLabel(),
                    variant: AppButtonVariant.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    onPressed: _isVideoAllowed() ? _pickVideo : null,
                    icon: const Icon(Icons.video_library),
                    label: _getVideoButtonLabel(),
                    variant: AppButtonVariant.secondary,
                    isDisabled: !_isVideoAllowed(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _getMediaHelpText(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            // Add tips based on ad type
            if (widget.selectedAdType == 'video feed ad') _buildVideoTip(),
            if (widget.selectedAdType == 'carousel') _buildCarouselTip(),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (widget.selectedAdType == 'carousel' &&
        widget.selectedImages.isNotEmpty) {
      return ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.selectedImages.length,
        itemBuilder: (context, index) {
          return Container(
            width: 150,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderPrimary),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    widget.selectedImages[index],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _removeImageFromCarousel(index),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else if (widget.selectedImage != null) {
      // **NEW: Special preview for banner ads**
      if (widget.selectedAdType == 'banner') {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Preserve the 320x100 design ratio without exceeding narrow cards.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AspectRatio(
                  aspectRatio: 3.2,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Image.file(
                        widget.selectedImage!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'Banner Preview (320x100)',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        // Regular preview for other ad types
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            widget.selectedImage!,
            fit: BoxFit.cover,
            width: double.infinity,
          ),
        );
      }
    } else if (widget.selectedVideo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: AppColors.backgroundPrimary,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.video_file, size: 48, color: AppColors.white),
                Text(
                  'Video Selected',
                  style: TextStyle(color: AppColors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.selectedAdType == 'banner'
                ? Icons.image
                : Icons.add_photo_alternate,
            size: 48,
            color: AppColors.textTertiary,
          ),
          Text(
            _getPlaceholderText(),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getPlaceholderSubtext(),
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 12,
            ),
          ),
        ],
      );
    }
  }

  Widget _buildVideoTip() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.video_library, size: 16, color: AppColors.success),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '🎬 Video Tip: For best results, use MP4 videos with H.264 encoding. Keep file size under 100MB for faster uploads.',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselTip() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.view_carousel, size: 16, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '🎠 Carousel Tip: Choose either multiple images (up to 3) OR a single video for your carousel. This creates a cleaner, more focused ad experience.',
              style: TextStyle(
                color: AppColors.warning,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getImageButtonLabel() {
    switch (widget.selectedAdType) {
      case 'banner':
        return 'Select Image *';
      case 'carousel':
        return widget.selectedImages.isNotEmpty
            ? 'Add More Images (${widget.selectedImages.length}/3)'
            : 'Add Images (up to 3)';
      default:
        return 'Select Image';
    }
  }

  String _getVideoButtonLabel() {
    switch (widget.selectedAdType) {
      case 'banner':
        return 'Video Not Allowed';
      case 'carousel':
        return widget.selectedVideo != null ? 'Video Selected' : 'Add Video';
      default:
        return 'Select Video';
    }
  }

  String _getMediaHelpText() {
    switch (widget.selectedAdType) {
      case 'banner':
        return 'Banner ads only support images (will be cropped to 320x100 pixels)';
      case 'carousel':
        return 'Carousel ads: choose either up to 3 images OR 1 video (not both)';
      default:
        return 'Video feed ads support both images and videos';
    }
  }

  String _getPlaceholderText() {
    switch (widget.selectedAdType) {
      case 'banner':
        return 'Select Image *';
      case 'carousel':
        return 'Select Images OR Video *';
      default:
        return 'Select Image or Video *';
    }
  }

  String _getPlaceholderSubtext() {
    switch (widget.selectedAdType) {
      case 'banner':
        return 'Banner ads require an image';
      case 'carousel':
        return 'Carousel ads: either up to 3 images OR 1 video';
      default:
        return 'Video feed ads support both';
    }
  }

  bool _isVideoAllowed() {
    return widget.selectedAdType != 'banner';
  }

  Future<void> _pickImage() async {
    try {
      if (widget.selectedAdType == 'banner') {
        await _pickSingleImage();
      } else if (widget.selectedAdType == 'carousel') {
        await _handleCarouselImageSelection();
      } else {
        await _pickSingleImage();
      }
    } catch (e) {
      widget.onError('Error picking image: $e');
    }
  }

  Future<void> _pickSingleImage() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard before opening picker
    final ImagePicker picker = ImagePicker();
    // prevent autoplay on resume
    if (mounted) {
      ref.read(mainControllerProvider).setMediaPickerActive(true);
    }
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (mounted) {
      ref.read(mainControllerProvider).setMediaPickerActive(false);
    }

    if (image != null) {
      final file = File(image.path);
      if (await _validateImageFile(file)) {
        // **NEW: For banner ads, show cropping dialog**
        if (widget.selectedAdType == 'banner') {
          if (mounted) {
            final croppedFile = await BannerImageProcessor.showBannerCropDialog(
              context,
              file,
            );

            if (croppedFile != null) {
              widget.onImageSelected(croppedFile);
            }
          }
        } else {
          // For other ad types, use image directly
          widget.onImageSelected(file);
        }
      }
    }
  }

  Future<void> _handleCarouselImageSelection() async {
    String? choice;

    if (widget.selectedImages.isNotEmpty) {
      choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Switch to Video?',
            style: AppTypography.headlineSmall
                .copyWith(fontSize: 18, color: AppColors.white),
          ),
          content: const Text(
            'You currently have images selected. Would you like to switch to video? This will remove all selected images.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            AppButton(
              onPressed: () => Navigator.pop(context, 'switch_to_video'),
              label: 'Switch to Video',
              variant: AppButtonVariant.text,
            ),
            AppButton(
              onPressed: () => Navigator.pop(context, 'keep_images'),
              label: 'Keep Images',
              variant: AppButtonVariant.text,
            ),
            AppButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              label: 'Cancel',
              variant: AppButtonVariant.text,
            ),
          ],
        ),
      );

      if (choice == 'switch_to_video') {
        widget.onImagesSelected([]);
        await _pickVideo();
        return;
      } else if (choice == 'keep_images') {
        if (widget.selectedImages.length < 3) {
          await _pickMultipleImages();
        } else {
          widget.onError('Maximum 3 images already selected');
        }
        return;
      } else {
        return;
      }
    }

    if (widget.selectedVideo != null) {
      choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Switch to Images?',
            style: AppTypography.headlineSmall
                .copyWith(fontSize: 18, color: AppColors.white),
          ),
          content: const Text(
            'You currently have a video selected. Would you like to switch to images? This will remove the selected video.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            AppButton(
              onPressed: () => Navigator.pop(context, 'switch_to_images'),
              label: 'Switch to Images',
              variant: AppButtonVariant.text,
            ),
            AppButton(
              onPressed: () => Navigator.pop(context, 'keep_video'),
              label: 'Keep Video',
              variant: AppButtonVariant.text,
            ),
            AppButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              label: 'Cancel',
              variant: AppButtonVariant.text,
            ),
          ],
        ),
      );

      if (choice == 'switch_to_images') {
        widget.onVideoSelected(null);
        await _pickMultipleImages();
        return;
      } else {
        return;
      }
    }

    choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Media Type'),
        content: const Text(
            'Carousel ads support either multiple images (up to 3) OR a single video. Choose one:'),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context, 'multiple_images'),
            label: 'Add Images (up to 3)',
            variant: AppButtonVariant.text,
          ),
          AppButton(
            onPressed: () => Navigator.pop(context, 'video'),
            label: 'Add Video',
            variant: AppButtonVariant.text,
          ),
          AppButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            label: 'Cancel',
            variant: AppButtonVariant.text,
          ),
        ],
      ),
    );

    if (choice == 'multiple_images') {
      await _pickMultipleImages();
    } else if (choice == 'video') {
      await _pickVideo();
    }
  }

  Future<void> _pickMultipleImages() async {
    if (widget.selectedImages.length >= 3) {
      widget.onError('Maximum 3 images allowed for carousel ads');
      return;
    }

    final ImagePicker picker = ImagePicker();
    if (mounted) {
      ref.read(mainControllerProvider).setMediaPickerActive(true);
    }
    final List<XFile> images = await picker.pickMultiImage(
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (mounted) {
      ref.read(mainControllerProvider).setMediaPickerActive(false);
    }

    if (images.isNotEmpty) {
      final List<File> validImages = [];
      for (final image in images) {
        if (widget.selectedImages.length + validImages.length >= 3) break;

        final file = File(image.path);
        if (await _validateImageFile(file)) {
          validImages.add(file);
        }
      }

      if (validImages.isNotEmpty) {
        final List<File> newImages = List.from(widget.selectedImages)
          ..addAll(validImages);
        widget.onImagesSelected(newImages);
      } else {
        widget.onError(
            'No valid images selected. Please ensure files are valid image formats under 10MB.');
      }
    }
  }

  Future<void> _pickVideo() async {
    if (widget.selectedAdType == 'banner') {
      widget.onError(
          'Banner ads only support images. Please select an image instead.');
      return;
    }

    // Restrict to gallery videos only
    final ImagePicker picker = ImagePicker();
    if (mounted) {
      ref.read(mainControllerProvider).setMediaPickerActive(true);
    }
    final XFile? picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (mounted) {
      ref.read(mainControllerProvider).setMediaPickerActive(false);
    }

    if (picked != null) {
      final file = File(picked.path);
      if (await _validateVideoFile(file)) {
        widget.onVideoSelected(file);
      }
    }
  }

  void _removeImageFromCarousel(int index) {
    final List<File> newImages = List.from(widget.selectedImages)
      ..removeAt(index);
    widget.onImagesSelected(newImages);
  }

  Future<bool> _validateImageFile(File file) async {
    try {
      final fileName = p.basename(file.path).toLowerCase();
      final isSupported = fileName.endsWith('.jpg') ||
          fileName.endsWith('.jpeg') ||
          fileName.endsWith('.png') ||
          fileName.endsWith('.gif') ||
          fileName.endsWith('.webp') ||
          fileName.endsWith('.heic') ||
          fileName.endsWith('.heif') ||
          fileName.endsWith('.avif') ||
          fileName.endsWith('.bmp');

      if (!isSupported) {
        widget.onError(
            'Please select a valid image file (JPG, PNG, GIF, WebP, HEIC/HEIF, AVIF, or BMP)');
        return false;
      }

      final fileSize = await file.length();
      if (fileSize > 10 * 1024 * 1024) {
        widget.onError('Image file size must be less than 10MB');
        return false;
      }

      return true;
    } catch (e) {
      widget.onError('Error validating image file: $e');
      return false;
    }
  }

  Future<bool> _validateVideoFile(File file) async {
    try {
      final fileName = p.basename(file.path).toLowerCase();
      final supportedExtensions = ['.mp4', '.webm', '.avi', '.mov', '.mkv'];

      if (!supportedExtensions.any((ext) => fileName.endsWith(ext))) {
        widget.onError(
            'Unsupported video format. Please select MP4, WebM, AVI, MOV, or MKV');
        return false;
      }

      final fileSize = await file.length();
      if (fileSize > 100 * 1024 * 1024) {
        widget.onError('Video file size must be less than 100MB');
        return false;
      }

      return true;
    } catch (e) {
      widget.onError('Error validating video file: $e');
      return false;
    }
  }
}
