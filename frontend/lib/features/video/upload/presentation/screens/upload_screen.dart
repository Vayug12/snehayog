import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vayug/shared/services/file_picker_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/video_upload_providers.dart';
import 'package:vayug/features/video/upload/presentation/managers/upload_state_manager.dart';
import 'package:vayug/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'dart:io';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:vayug/features/auth/data/services/logout_service.dart';
import 'package:vayug/features/ads/presentation/screens/create_ad_screen_refactored.dart';
import 'package:vayug/features/ads/presentation/screens/ad_management_screen.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/features/video/upload/presentation/screens/upload_advanced_settings_screen.dart';
// AI Video generation is not completed yet — screen hidden from UI.
// import 'package:vayug/features/video/upload/presentation/screens/ai_video_generate_screen.dart';
import 'package:vayug/shared/constants/interests.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:video_player/video_player.dart';

class UploadScreen extends ConsumerStatefulWidget {
  final VoidCallback? onVideoUploaded;

  const UploadScreen({super.key, this.onVideoUploaded});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _tagInputController = TextEditingController();

  final ValueNotifier<bool> _showUploadForm = ValueNotifier<bool>(false);
  final ValueNotifier<double> _videoAspectRatio = ValueNotifier<double>(9 / 16);
  final ValueNotifier<double> _videoDuration = ValueNotifier<double>(0.0);
  final ValueNotifier<List<String>> _selectedSubscribers = ValueNotifier<List<String>>([]);
  final ValueNotifier<List<QuizModel>> _quizzes = ValueNotifier<List<QuizModel>>([]);
  final ValueNotifier<File?> _selectedThumbnail = ValueNotifier<File?>(null);
  final ValueNotifier<List<String>> _selectedPlatforms = ValueNotifier<List<String>>([]);

  late final IAuthService _authService;
  late final FilePickerService _filePickerService;

  @override
  void initState() {
    super.initState();
    _authService = ref.read(authServiceProvider);
    _filePickerService = ref.read(filePickerServiceProvider);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _linkController.dispose();
    _tagInputController.dispose();
    _showUploadForm.dispose();
    _videoAspectRatio.dispose();
    _videoDuration.dispose();
    _selectedSubscribers.dispose();
    _quizzes.dispose();
    _selectedThumbnail.dispose();
    _selectedPlatforms.dispose();
    super.dispose();
  }

  void _resetScreenState({bool resetManager = true}) {
    if (resetManager) {
      ref.read(uploadStateManagerProvider).reset();
    }
    _showUploadForm.value = false;
    _titleController.clear();
    _linkController.clear();
    _tagInputController.clear();
    _selectedThumbnail.value = null;
    _selectedSubscribers.value = [];
    _quizzes.value = [];
    _selectedPlatforms.value = [];
    _videoAspectRatio.value = 9 / 16;
    _videoDuration.value = 0.0;
  }

  void _deselectVideo() {
    _resetScreenState();
  }

  void _cancelUpload() {
    ref.read(uploadStateManagerProvider).cancelUpload();
    _resetScreenState(resetManager: false);
  }

  Future<void> _pickVideo() async {
    final userData = await _authService.getUserData();
    if (userData == null) {
      _showLoginPrompt();
      return;
    }

    try {
      final result = await _filePickerService.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'],
      );

      if (result != null) {
        final pickedFile = File(result.files.single.path!);
        ref.read(uploadStateManagerProvider).setVideo(pickedFile);
        _titleController.text = _deriveTitleFromFile(pickedFile);
        _showUploadForm.value = true;
        _probeVideoMetadata(pickedFile);
      }
    } catch (e) {
      AppLogger.log('Error picking video: $e');
    }
  }

  /// Reads duration and aspect ratio from the picked file. The quiz editor
  /// derives its per-video quiz limit from this duration, so without it the
  /// limit is computed from 0s and blocks quiz creation.
  Future<void> _probeVideoMetadata(File file) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      final value = controller.value;
      _videoDuration.value = value.duration.inMilliseconds / 1000.0;
      if (value.size.width > 0 && value.size.height > 0) {
        _videoAspectRatio.value = value.size.width / value.size.height;
      }
      AppLogger.log(
          'UploadScreen: Video metadata — ${_videoDuration.value.toStringAsFixed(1)}s, AR ${_videoAspectRatio.value.toStringAsFixed(2)}');
    } catch (e) {
      AppLogger.log('UploadScreen: Could not read video metadata: $e');
    } finally {
      await controller?.dispose();
    }
  }

  String _deriveTitleFromFile(File file) {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    return baseName.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  }

  Future<void> _uploadVideo() async {
    final manager = ref.read(uploadStateManagerProvider);
    await manager.startUpload(
      title: _titleController.text,
      description: '',
      link: _linkController.text,
      thumbnailFile: _selectedThumbnail.value,
      tags: manager.tags,
      platforms: _selectedPlatforms.value,
      allowedSubscribers: _selectedSubscribers.value,
    );

    if (manager.status == UploadStatus.success) {
      if (mounted) {
        VayuSnackBar.showSuccess(context, AppText.get('upload_success_message'));
      }
      if (widget.onVideoUploaded != null) {
        widget.onVideoUploaded!();
      }
      _resetScreenState();
    }
  }

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppText.get('upload_login_required')),
        content: Text(AppText.get('upload_please_sign_in_upload')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppText.get('btn_cancel')),
          ),
          AppButton(
            onPressed: () async {
              final authController = ref.read(googleSignInProvider);
              Navigator.pop(context);
              await authController.signIn();
              if (mounted) {
                await LogoutService.refreshAllState(ref);
              }
            },
            label: AppText.get('btn_sign_in'),
            variant: AppButtonVariant.primary,
          ),
        ],
      ),
    );
  }

  void _showWhatToUploadDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
        padding: AppSpacing.edgeInsetsAll24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppText.get('upload_terms_title'), style: AppTypography.headlineSmall),
              AppSpacing.vSpace16,
              _buildNoticePoint(
                title: AppText.get('upload_terms_copyright'),
                body: AppText.get('upload_terms_copyright_desc'),
              ),
              _buildNoticePoint(
                title: AppText.get('upload_terms_reporting'),
                body: AppText.get('upload_terms_reporting_desc'),
              ),
              AppSpacing.vSpace24,
              AppButton(
                onPressed: () => Navigator.pop(context),
                label: AppText.get('btn_i_understand'),
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoticePoint({required String title, required String body}) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold)),
          AppSpacing.vSpace4,
          Text(body, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(uploadStateManagerProvider);
    final authController = ref.watch(googleSignInProvider);
    final isSignedIn = authController.isSignedIn;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(AppText.get('upload_title')),
        centerTitle: true,
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        leading: state.selectedVideo != null
            ? IconButton(icon: const Icon(Icons.close), onPressed: _deselectVideo)
            : null,
        actions: [
          if (isSignedIn)
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdManagementScreen()),
                );
              },
              icon: const Icon(Icons.campaign),
            ),
        ],
      ),
      body: _buildBody(context, state, isSignedIn, authController),
    );
  }

  Widget _buildBody(BuildContext context, UploadStateManager state, bool isSignedIn, GoogleSignInController authController) {
    if (!isSignedIn) return _buildLoginView(authController);

    if (state.status == UploadStatus.idle && state.selectedVideo == null) {
      return _buildInitialChoiceView(context);
    }

    return SingleChildScrollView(
      padding: AppSpacing.edgeInsetsAll24,
      child: Column(
        children: [
          _buildUploadProgressDashboard(context, state),
          AppSpacing.vSpace32,
          _buildActionButtons(state),
        ],
      ),
    );
  }

  Widget _buildLoginView(GoogleSignInController authController) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: AppColors.textTertiary),
            AppSpacing.vSpace24,
            Text(AppText.get('upload_login_required'), style: AppTypography.headlineSmall),
            AppSpacing.vSpace32,
            AppButton(
              onPressed: () => authController.signIn(),
              label: AppText.get('btn_sign_in_google'),
              isFullWidth: true,
              isLoading: authController.isLoading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialChoiceView(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.space24, vertical: AppSpacing.spacing10),
      child: Column(
        children: [
          Text(AppText.get('upload_choose_what_create'),
              style: AppTypography.headlineLarge.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          AppSpacing.vSpace48,
          _buildChoiceCard(
            icon: Icons.video_library,
            title: AppText.get('upload_video'),
            color: AppColors.primary,
            onTap: _pickVideo,
          ),
          AppSpacing.vSpace24,
          _buildChoiceCard(
            icon: Icons.campaign,
            title: AppText.get('upload_create_ad'),
            color: AppColors.success,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateAdScreenRefactored()));
            },
          ),
          // AI Video generation is not completed yet — hidden from UI.
          // _buildChoiceCard(
          //   icon: Icons.auto_awesome,
          //   title: 'AI Video',
          //   color: AppColors.primary,
          //   onTap: () {
          //     Navigator.push(context, MaterialPageRoute(builder: (context) => const AiVideoGenerateScreen()));
          //   },
          // ),
          SizedBox(height: AppSpacing.spacing10),
          TextButton.icon(
            onPressed: _showWhatToUploadDialog,
            icon: const Icon(Icons.help_outline, size: 16),
            label: Text(AppText.get('upload_what_to_upload')),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceCard({required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(AppSpacing.spacing5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: color),
            AppSpacing.hSpace16,
            Expanded(child: Text(title, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold))),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadProgressDashboard(BuildContext context, UploadStateManager state) {
    final status = state.status;
    final progress = state.progress;

    return Column(
      children: [
        if (state.errorMessage != null) _buildErrorBanner(state.errorMessage!),
        AppSpacing.vSpace16,
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 8,
                  backgroundColor: AppColors.backgroundSecondary,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${(progress * 100).toInt()}%',
                      style: AppTypography.headlineMedium.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                  Text(_getStatusText(status), style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
        ),
        AppSpacing.vSpace32,
        if (status == UploadStatus.idle || status == UploadStatus.error)
          _buildUploadForm(state)
        else
          _buildProcessingDetails(state),
      ],
    );
  }

  Widget _buildUploadForm(UploadStateManager state) {
    return Column(
      children: [
        _buildCategorySelector(state),
        SizedBox(height: AppSpacing.spacing5),
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        SizedBox(height: AppSpacing.spacing5),
        _buildAdvancedSettingsNavigation(),
      ],
    );
  }

  Widget _buildCategorySelector(UploadStateManager state) {
    final options = kInterestOptions.where((c) => c != 'Custom Interest').toList();
    return DropdownButtonFormField<String>(
      initialValue: state.category ?? 'Others',
      items: options.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: (val) => state.setCategory(val ?? 'Others'),
      decoration: InputDecoration(
        labelText: 'Category',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildProcessingDetails(UploadStateManager state) {
    return Column(
      children: [
        Text('Phase: ${state.currentPhase.toUpperCase()}', style: AppTypography.titleSmall),
        AppSpacing.vSpace16,
        if (state.crossPostStatus.isNotEmpty)
          ...state.crossPostStatus.entries.map((e) => ListTile(
                leading: _getPlatformIcon(e.key, AppColors.primary),
                title: Text(e.key.toUpperCase()),
                trailing: Text(e.value),
              )),
      ],
    );
  }

  Widget _buildActionButtons(UploadStateManager state) {
    final isUploading = state.status != UploadStatus.idle && state.status != UploadStatus.error && state.status != UploadStatus.success;

    if (state.status == UploadStatus.success) {
      return AppButton(onPressed: _resetScreenState, label: 'Upload Another', isFullWidth: true);
    }

    if (isUploading) {
      return AppButton(
        onPressed: _cancelUpload,
        label: 'Cancel Upload',
        variant: AppButtonVariant.outline,
        isFullWidth: true,
      );
    }

    return AppButton(onPressed: _uploadVideo, label: 'Start Upload', isFullWidth: true);
  }

  Widget _getPlatformIcon(String platform, Color color) {
    switch (platform) {
      case 'youtube':
        return HugeIcon(icon: HugeIcons.strokeRoundedYoutube, color: color, size: 18);
      default:
        return Icon(Icons.public, color: color, size: 18);
    }
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: EdgeInsets.only(bottom: AppSpacing.space24),
      padding: AppSpacing.edgeInsetsAll12,
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          AppSpacing.hSpace12,
          Expanded(child: Text(message, style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
  }

  Widget _buildAdvancedSettingsNavigation() {
    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UploadAdvancedSettingsScreen(
              linkController: _linkController,
              tagInputController: _tagInputController,
              tags: ValueNotifier(ref.read(uploadStateManagerProvider).tags),
              onAddTag: (tag) {
                final manager = ref.read(uploadStateManagerProvider);
                manager.setTags([...manager.tags, tag]);
              },
              onRemoveTag: (tag) {
                final manager = ref.read(uploadStateManagerProvider);
                manager.setTags(manager.tags.where((t) => t != tag).toList());
              },
              onMakeEpisode: () {},
              quizzes: _quizzes,
              selectedPlatforms: _selectedPlatforms,
              selectedSubscribers: _selectedSubscribers,
              selectedThumbnail: _selectedThumbnail,
              videoDuration: _videoDuration.value,
              videoAspectRatio: _videoAspectRatio.value,
            ),
          ),
        );
      },
      leading: const Icon(Icons.settings, color: AppColors.primary),
      title: const Text('Advanced Settings'),
      subtitle: const Text('Tags, Links, and more'),
      trailing: const Icon(Icons.chevron_right),
    );
  }

  String _getStatusText(UploadStatus status) {
    switch (status) {
      case UploadStatus.idle: return 'Idle';
      case UploadStatus.preparing: return 'Preparing';
      case UploadStatus.validation: return 'Validating';
      case UploadStatus.uploading: return 'Uploading';
      case UploadStatus.processing: return 'Processing';
      case UploadStatus.finalizing: return 'Finalizing';
      case UploadStatus.success: return 'Success';
      case UploadStatus.error: return 'Error';
    }
  }
}
