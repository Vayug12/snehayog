import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/features/video/edit/presentation/screens/edit_video_details.dart';

import 'package:image_picker/image_picker.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final ProfileStateManager stateManager;

  const EditProfileScreen({
    super.key,
    required this.stateManager,
  });

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _websiteController;
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSaving = false;
  bool _isPhotoLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.stateManager.userData?['name'] ?? '');
    _websiteController = TextEditingController(text: widget.stateManager.userData?['websiteUrl'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _handlePhotoChange() async {
    try {
      final XFile? image = await showModalBottomSheet<XFile?>(
        context: context,
        backgroundColor: AppColors.backgroundSecondary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const HugeIcon(icon: HugeIcons.strokeRoundedCamera01),
                  title: Text(AppText.get('profile_take_photo', fallback: 'Take a Photo')),
                  onTap: () async {
                    final XFile? photo = await _imagePicker.pickImage(source: ImageSource.camera);
                    Navigator.pop(context, photo);
                  },
                ),
                ListTile(
                  leading: const HugeIcon(icon: HugeIcons.strokeRoundedImage02),
                  title: Text(AppText.get('profile_choose_gallery', fallback: 'Choose from Gallery')),
                  onTap: () async {
                    final XFile? photo = await _imagePicker.pickImage(source: ImageSource.gallery);
                    Navigator.pop(context, photo);
                  },
                ),
              ],
            ),
          );
        },
      );

      if (image != null && mounted) {
        setState(() => _isPhotoLoading = true);
        VayuSnackBar.showInfo(context, AppText.get('profile_photo_uploading', fallback: 'Uploading photo...'), duration: const Duration(seconds: 1));

        await widget.stateManager.updateProfilePhoto(image.path);

        if (mounted) {
          setState(() => _isPhotoLoading = false);
          VayuSnackBar.showSuccess(context, AppText.get('profile_photo_updated', fallback: 'Profile photo updated!'));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPhotoLoading = false);
        VayuSnackBar.showError(context, 'Failed to update photo: $e');
      }
    }
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      VayuSnackBar.showError(context, 'Please enter your name');
      return;
    }

    setState(() => _isSaving = true);
    try {
      widget.stateManager.nameController.text = name;
      widget.stateManager.websiteController.text = _websiteController.text.trim();

      await widget.stateManager.saveProfile();

      if (mounted) {
        Navigator.pop(context);
        VayuSnackBar.showSuccess(
          context,
          AppText.get('profile_updated_success', fallback: 'Profile updated successfully'),
        );
      }
    } catch (e) {
      if (mounted) {
        VayuSnackBar.showError(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userData = widget.stateManager.userData;
    final profilePic = userData?['profilePic'] ?? '';

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            leading: IconButton(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              AppText.get('edit_profile_title', fallback: 'Edit Profile'),
              style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
            actions: [
              if (_isSaving || _isPhotoLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else
                TextButton(
                  onPressed: _handleSave,
                  child: Text(
                    AppText.get('btn_save', fallback: 'Save'),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                children: [
                  AppSpacing.vSpace12,
                  // Profile Photo — identity anchor, stays visible on the hub
                  Center(
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: AppColors.backgroundSecondary,
                              backgroundImage: profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
                              child: profilePic.isEmpty
                                  ? const HugeIcon(icon: HugeIcons.strokeRoundedUser, size: 36, color: AppColors.textTertiary)
                                  : null,
                            ),
                            if (_isPhotoLoading)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(child: CircularProgressIndicator()),
                                ),
                              ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _isPhotoLoading ? null : _handlePhotoChange,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const HugeIcon(icon: HugeIcons.strokeRoundedCamera01, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        AppSpacing.vSpace8,
                        TextButton(
                          onPressed: _isPhotoLoading ? null : _handlePhotoChange,
                          child: Text(
                            AppText.get('profile_change_photo', fallback: 'Change Photo'),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  AppSpacing.vSpace16,

                  // Hub: tap into a spoke to edit each field
                  _buildSettingRow(
                    icon: Icons.badge_outlined,
                    title: 'Display Name',
                    subtitle: _nameController.text.isNotEmpty ? _nameController.text : 'Add your name',
                    onTap: _showNameEditor,
                  ),

                  AppSpacing.vSpace8,

                  _buildSettingRow(
                    icon: Icons.link_rounded,
                    title: 'Website Link',
                    subtitle: _websiteController.text.isNotEmpty ? _websiteController.text : 'Add a link',
                    onTap: _showWebsiteEditor,
                  ),

                  AppSpacing.vSpace8,

                  _buildSettingRow(
                    icon: Icons.videocam_outlined,
                    title: 'Manage Video',
                    subtitle: '${widget.stateManager.userVideos.length} videos',
                    onTap: _showVideoPicker,
                  ),

                  AppSpacing.vSpace16,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 22),
      ),
      title: Text(
        title,
        style: AppTypography.titleMedium.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppTypography.bodySmall.copyWith(
          height: 1.4,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: AppColors.textTertiary,
      ),
      onTap: onTap,
    );
  }

  void _showNameEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: AppColors.backgroundPrimary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Display Name',
                style: AppTypography.headlineMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              AppSpacing.vSpace16,
              _buildTextField(
                controller: _nameController,
                hintText: 'Enter your name',
                onChanged: (_) => setModalState(() {}),
              ),
              AppSpacing.vSpace16,
              AppButton(
                onPressed: () {
                  setState(() {});
                  Navigator.pop(context);
                },
                label: 'Done',
                variant: AppButtonVariant.primary,
                isFullWidth: true,
                size: AppButtonSize.large,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWebsiteEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: AppColors.backgroundPrimary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Website Link',
                style: AppTypography.headlineMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              AppSpacing.vSpace16,
              _buildTextField(
                controller: _websiteController,
                hintText: 'e.g. snehayog.site',
                keyboardType: TextInputType.url,
                onChanged: (_) => setModalState(() {}),
              ),
              AppSpacing.vSpace16,
              AppButton(
                onPressed: () {
                  setState(() {});
                  Navigator.pop(context);
                },
                label: 'Done',
                variant: AppButtonVariant.primary,
                isFullWidth: true,
                size: AppButtonSize.large,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVideoPicker() {
    final videos = widget.stateManager.userVideos;
    if (videos.isEmpty) {
      VayuSnackBar.showInfo(context, 'No videos to manage');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: AppColors.backgroundPrimary,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select a Video',
                    style: AppTypography.headlineMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: videos.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                itemBuilder: (context, index) {
                  final video = videos[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: Container(
                      width: 60,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.backgroundSecondary,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: video.thumbnailUrl.isNotEmpty
                            ? Image.network(video.thumbnailUrl, fit: BoxFit.cover)
                            : const Icon(Icons.videocam_rounded, color: AppColors.textTertiary),
                      ),
                    ),
                    title: Text(
                      video.videoName,
                      style: AppTypography.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      video.videoType.toUpperCase(),
                      style: AppTypography.labelSmall,
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary),
                    onTap: () async {
                      Navigator.pop(context);
                      final result = await Navigator.push<Map<String, dynamic>>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditVideoDetails(video: video),
                        ),
                      );
                      if (result != null && mounted) {
                        widget.stateManager.updateVideoInList(video.id, result);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int? maxLines = 1,
    TextInputType? keyboardType,
    Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: AppTypography.fontSizeBase,
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.4)),
        filled: true,
        fillColor: AppColors.backgroundSecondary.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
