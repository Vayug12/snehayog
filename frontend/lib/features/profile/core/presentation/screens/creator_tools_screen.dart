import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class CreatorToolsScreen extends ConsumerStatefulWidget {
  const CreatorToolsScreen({super.key});

  @override
  ConsumerState<CreatorToolsScreen> createState() => _CreatorToolsScreenState();
}

class _CreatorToolsScreenState extends ConsumerState<CreatorToolsScreen> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  VideoModel? _selectedVideo;
  final Set<String> _selectedSubscriberIds = {};
  bool _selectAll = true;
  List<Subscriber> _subscribers = [];
  bool _isLoadingSubscribers = true;

  @override
  void initState() {
    super.initState();
    _loadSubscribers();
  }

  Future<void> _loadSubscribers() async {
    try {
      final subs = await UserService().getSubscribers();
      setState(() {
        _subscribers = subs;
        _isLoadingSubscribers = false;
        if (_selectAll) {
          _selectedSubscriberIds.addAll(subs.map((s) => s.id));
        }
      });
    } catch (e) {
      setState(() => _isLoadingSubscribers = false);
    }
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedSubscriberIds.addAll(_subscribers.map((s) => s.id));
      } else {
        _selectedSubscriberIds.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(profileStateManagerProvider);

    if (!manager.isSignedIn) {
      return _buildAuthRequiredPlaceholder();
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Creator Tools', style: TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: true,
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.primary),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSectionHeader('BROADCAST DETAILS'),
                
                _buildSettingRow(
                  icon: Icons.edit_note_rounded,
                  title: 'Compose Message',
                  subtitle: _messageController.text.isEmpty 
                      ? 'Set title & broadcast message' 
                      : _messageController.text,
                  trailing: _messageController.text.isNotEmpty 
                      ? const Icon(Icons.check_circle, color: AppColors.success, size: 18)
                      : const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                  onTap: () => _showBroadcastDetailsEditor(),
                ),


                _buildVideoPickerRow(manager),


                _buildSettingRow(
                  icon: Icons.people_rounded,
                  title: 'Select Subscribers',
                  subtitle: _selectAll 
                      ? 'All Subscribers selected' 
                      : '${_selectedSubscriberIds.length} subscribers selected',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Select All', style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _selectAll,
                          onChanged: _toggleSelectAll,
                          activeColor: AppColors.primary,
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _showSubscriberSelectionSheet(),
                ),

                const SizedBox(height: 32),
                
                // Info Box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                  ),
                  child: const Row(
                    children: [
                       Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
                       SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your broadcast will be sent as a direct notification to the selected subscribers.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: AppButton(
                onPressed: manager.isAlertSending ? null : _handleSend,
                label: manager.isAlertSending ? 'Sending...' : 'Broadcast to Subscribers',
                variant: AppButtonVariant.primary,
                isLoading: manager.isAlertSending,
                isFullWidth: true,
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthRequiredPlaceholder() {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_person_rounded, color: AppColors.primary, size: 64),
              ),
              const SizedBox(height: 32),
              const Text(
                'Creator Access Required',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Sign in to your account to send broadcast alerts and updates to your subscribers.',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              AppButton(
                onPressed: () => ref.read(googleSignInProvider).signIn(),
                label: 'Sign In with Google',
                variant: AppButtonVariant.primary,
                isFullWidth: true,
                icon: const Icon(Icons.login_rounded, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textTertiary.withValues(alpha: 0.7),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.textPrimary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing,
              const SizedBox(width: 8),
            ],
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  void _showBroadcastDetailsEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24, right: 24, top: 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter the content for your subscriber alert.', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _titleController,
                label: 'Notification Title',
                hint: 'e.g., New Video Out Now!',
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _messageController,
                label: 'Message Body',
                hint: 'Tell your subscribers what\'s happening...',
                maxLines: 4,
              ),
              const SizedBox(height: 24),
              AppButton(
                onPressed: () {
                  setState(() {});
                  Navigator.pop(context);
                },
                label: 'Save Changes',
                variant: AppButtonVariant.primary,
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPickerRow(ProfileStateManager manager) {
    return _buildSettingRow(
      icon: Icons.video_collection_outlined,
      title: 'Attach Video',
      subtitle: _selectedVideo == null ? 'Optional attachment' : _selectedVideo!.videoName,
      trailing: _selectedVideo != null 
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.error),
              onPressed: () => setState(() => _selectedVideo = null),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          : null,
      onTap: () => _showVideoSelectionDialog(manager),
    );
  }

  void _showSubscriberSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Target Subscribers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _selectAll,
                onChanged: (val) {
                  _toggleSelectAll(val);
                  setModalState(() {});
                },
                title: const Text('Select All Subscribers', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: _isLoadingSubscribers 
                  ? const Center(child: CircularProgressIndicator())
                  : _subscribers.isEmpty
                    ? const Center(child: Text('No subscribers found', style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        itemCount: _subscribers.length,
                        itemBuilder: (context, index) {
                          final sub = _subscribers[index];
                          final isSelected = _selectedSubscriberIds.contains(sub.id);
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedSubscriberIds.add(sub.id);
                                } else {
                                  _selectedSubscriberIds.remove(sub.id);
                                  _selectAll = false;
                                }
                              });
                              setModalState(() {});
                            },
                            title: Text(sub.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: Text(sub.email, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                            secondary: CircleAvatar(
                              radius: 14,
                              backgroundImage: sub.profilePic != null ? NetworkImage(sub.profilePic!) : null,
                              child: sub.profilePic == null ? const Icon(Icons.person, size: 14) : null,
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              AppButton(
                onPressed: () => Navigator.pop(context),
                label: 'Confirm Selection',
                variant: AppButtonVariant.primary,
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    ).then((_) => setState(() {}));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }


  void _showVideoSelectionDialog(ProfileStateManager manager) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Select Video', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: manager.userVideos.length,
                itemBuilder: (context, index) {
                  final video = manager.userVideos[index];
                  return ListTile(
                    leading: Image.network(video.thumbnailUrl, width: 50, fit: BoxFit.cover),
                    title: Text(video.videoName, style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      setState(() => _selectedVideo = video);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }


  Future<void> _handleSend() async {
    if (_messageController.text.trim().isEmpty) {
      VayuSnackBar.showError(context, 'Please enter a message');
      return;
    }

    if (_selectedSubscriberIds.isEmpty) {
      VayuSnackBar.showError(context, 'Please select at least one subscriber');
      return;
    }

    try {
      final manager = ref.read(profileStateManagerProvider);
      // Logic for deep link or navigation target
      String? targetUrl;
      if (_selectedVideo != null) {
        // Assuming video player deep link format
        targetUrl = 'vayug://video/${_selectedVideo!.id}';
      }

      await manager.sendCreatorAlert(
        title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
        message: _messageController.text.trim(),
        targetUrl: targetUrl,
        recipientIds: _selectedSubscriberIds.toList(),
      );

      if (mounted) {
        VayuSnackBar.showSuccess(context, 'Broadcast sent successfully!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        VayuSnackBar.showError(context, 'Error: $e');
      }
    }
  }
}
