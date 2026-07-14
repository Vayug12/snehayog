import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/widgets/app_button.dart';

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
  final _formKey = GlobalKey<FormState>();
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
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      try {
        // Update the state manager's controllers before saving
        widget.stateManager.nameController.text = _nameController.text.trim();
        widget.stateManager.websiteController.text = _websiteController.text.trim();
        
        await widget.stateManager.saveProfile();
        
        if (mounted) {
          // Navigate back to ProfileScreen
          Navigator.pop(context);
          
          // Show success message on the Profile screen
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
              padding: EdgeInsets.all(AppSpacing.spacing4),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Photo Section
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: AppColors.backgroundSecondary,
                                backgroundImage: profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
                                child: profilePic.isEmpty
                                    ? const HugeIcon(icon: HugeIcons.strokeRoundedUser, size: 40, color: AppColors.textTertiary)
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
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const HugeIcon(icon: HugeIcons.strokeRoundedCamera01, size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
                    const SizedBox(height: 32),
                    _buildSectionTitle(AppText.get('edit_profile_name_label', fallback: 'Display Name')),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration('Enter your name'),
                      validator: (value) => value == null || value.isEmpty ? 'Please enter your name' : null,
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle(AppText.get('edit_profile_website_label', fallback: 'Website Link')),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _websiteController,
                      keyboardType: TextInputType.url,
                      decoration: _inputDecoration('e.g. snehayog.site').copyWith(
                        prefixIcon: const Icon(Icons.link, size: 20, color: AppColors.textTertiary),
                      ),
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          if (!value.contains('.')) return 'Please enter a valid URL';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 40),
                    AppButton(
                      onPressed: _isSaving ? null : _handleSave,
                      label: _isSaving ? 'Saving...' : 'Save Changes',
                      variant: AppButtonVariant.primary,
                      isLoading: _isSaving,
                      isFullWidth: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTypography.labelMedium.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.backgroundSecondary.withValues(alpha: 0.3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
