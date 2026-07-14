import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/core/providers/ai_video_generation_providers.dart';
import 'package:vayug/features/video/upload/presentation/managers/ai_video_generation_manager.dart';
import 'package:vayug/shared/constants/interests.dart';

class AiVideoGenerateScreen extends ConsumerStatefulWidget {
  const AiVideoGenerateScreen({super.key});

  @override
  ConsumerState<AiVideoGenerateScreen> createState() => _AiVideoGenerateScreenState();
}

class _AiVideoGenerateScreenState extends ConsumerState<AiVideoGenerateScreen> {
  final TextEditingController _promptController = TextEditingController();
  String? _selectedCategory;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generateVideo() async {
    // **GUARD: Only one video can generate at a time**
    final manager = ref.read(aiVideoGenerationManagerProvider);
    if (manager.isRunning) {
      VayuSnackBar.showInfo(
        context,
        '1 video is already generating. Please wait for it to finish.',
      );
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.length < 5) {
      VayuSnackBar.showError(context, 'Prompt must be at least 5 characters');
      return;
    }
    ref.read(aiVideoGenerationManagerProvider.notifier).generateVideo(prompt, _selectedCategory);
  }

  void _runInBackground() {
    ref.read(aiVideoGenerationManagerProvider.notifier).background();
    Navigator.of(context).pop();
    VayuSnackBar.showInfo(context, 'Video generating in background. Check the banner for progress.');
  }

  void _reset() {
    ref.read(aiVideoGenerationManagerProvider.notifier).cancel();
    _promptController.clear();
    _selectedCategory = null;
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(aiVideoGenerationManagerProvider);

    // If generation is done and was in background, just pop
    if (manager.status == AiVideoGenStatus.done && manager.isInBackground) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          manager.markDoneSeen();
          Navigator.of(context).pop();
          VayuSnackBar.showSuccess(context, 'Video saved to gallery!');
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('AI Video Generator'),
        centerTitle: true,
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        leading: manager.isRunning && !manager.isInBackground
            ? IconButton(icon: const Icon(Icons.close), onPressed: _reset)
            : null,
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.edgeInsetsAll24,
        child: _buildBody(manager),
      ),
    );
  }

  Widget _buildBody(AiVideoGenerationManager manager) {
    switch (manager.status) {
      case AiVideoGenStatus.idle:
        return _buildPromptForm();
      case AiVideoGenStatus.error:
        return _buildErrorView(manager);
      case AiVideoGenStatus.done:
        return _buildDoneView();
      default:
        return _buildProgressView(manager);
    }
  }

  Widget _buildPromptForm() {
    final options = kInterestOptions.where((c) => c != 'Custom Interest').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What do you want to create?',
          style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.bold),
        ),
        AppSpacing.vSpace8,
        Text(
          'Describe the video you want AI to generate. Be specific for better results.',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        AppSpacing.vSpace24,
        TextField(
          controller: _promptController,
          maxLines: 4,
          minLines: 3,
          maxLength: 1000,
          decoration: InputDecoration(
            hintText: 'e.g. A 60-second motivational video about discipline and consistency...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            alignLabelWithHint: true,
          ),
        ),
        AppSpacing.vSpace16,
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          items: options.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (val) => setState(() => _selectedCategory = val),
          decoration: InputDecoration(
            labelText: 'Category (optional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        AppSpacing.vSpace32,
        AppButton(
          onPressed: _generateVideo,
          label: 'Generate Video',
          isFullWidth: true,
        ),
      ],
    );
  }

  Widget _buildProgressView(AiVideoGenerationManager manager) {
    final statusText = manager.status == AiVideoGenStatus.submitting
        ? 'Starting...'
        : manager.status == AiVideoGenStatus.generating
            ? 'AI is creating your video...'
            : 'Saving to gallery...';
    final percent = (manager.progress * 100).toInt();

    return Column(
      children: [
        AppSpacing.vSpace24,
        // **Clear "one at a time" banner so the creator always knows a job is live**
        _buildInProgressBanner(),
        AppSpacing.vSpace32,
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: CircularProgressIndicator(
                  value: manager.progress,
                  strokeWidth: 8,
                  backgroundColor: AppColors.backgroundSecondary,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              Text(
                '$percent%',
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        AppSpacing.vSpace32,
        Text(statusText, style: AppTypography.titleMedium, textAlign: TextAlign.center),
        AppSpacing.vSpace16,
        // **Explicit linear progress bar (matches the notification the user sees)**
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: manager.progress,
            minHeight: 8,
            backgroundColor: AppColors.backgroundSecondary,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        AppSpacing.vSpace16,
        Text(
          manager.isInBackground
              ? 'Running in the background. We\'ll notify you when it\'s ready.'
              : 'This may take a few minutes. You can run it in the background and keep using the app.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        AppSpacing.vSpace32,
        if (manager.status == AiVideoGenStatus.generating &&
            !manager.isInBackground) ...[
          AppButton(
            onPressed: _runInBackground,
            label: 'Run in Background',
            isFullWidth: true,
          ),
          AppSpacing.vSpace12,
          AppButton(
            onPressed: _reset,
            label: 'Cancel',
            variant: AppButtonVariant.outline,
            isFullWidth: true,
          ),
        ] else if (manager.isInBackground) ...[
          // Already backgrounded — let the user leave or stop the job.
          AppButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Keep Using App',
            isFullWidth: true,
          ),
          AppSpacing.vSpace12,
          AppButton(
            onPressed: _reset,
            label: 'Cancel Generation',
            variant: AppButtonVariant.outline,
            isFullWidth: true,
          ),
        ],
      ],
    );
  }

  /// Prominent banner communicating that exactly one video is generating.
  Widget _buildInProgressBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: AppColors.primary, size: 22),
          AppSpacing.hSpace12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1 video is generating',
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                AppSpacing.vSpace4,
                Text(
                  'You can only create one video at a time.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(AiVideoGenerationManager manager) {
    return Column(
      children: [
        AppSpacing.vSpace48,
        const Icon(Icons.error_outline, size: 64, color: AppColors.error),
        AppSpacing.vSpace16,
        Text('Generation Failed', style: AppTypography.headlineSmall),
        AppSpacing.vSpace8,
        Text(
          manager.errorMessage ?? 'Unknown error',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        AppSpacing.vSpace32,
        AppButton(
          onPressed: _reset,
          label: 'Try Again',
          isFullWidth: true,
        ),
      ],
    );
  }

  Widget _buildDoneView() {
    return Column(
      children: [
        AppSpacing.vSpace48,
        const Icon(Icons.check_circle, size: 64, color: AppColors.success),
        AppSpacing.vSpace16,
        Text('Video Saved!', style: AppTypography.headlineSmall),
        AppSpacing.vSpace8,
        Text(
          'Your AI-generated video has been saved to your gallery.',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        AppSpacing.vSpace32,
        AppButton(
          onPressed: _reset,
          label: 'Generate Another',
          isFullWidth: true,
        ),
      ],
    );
  }
}
