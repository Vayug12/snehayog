import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/features/ads/presentation/widgets/create_ad/ad_type_selector_widget.dart';
import 'package:vayug/features/ads/presentation/widgets/create_ad/media_uploader_widget.dart';
import 'package:vayug/features/ads/presentation/widgets/create_ad/ad_details_form_widget.dart';
import 'package:vayug/features/ads/presentation/widgets/create_ad/targeting_section_widget.dart';
import 'package:vayug/features/ads/presentation/widgets/create_ad/campaign_preview_widget.dart';
import 'package:vayug/features/ads/presentation/widgets/create_ad/payment_handler_widget.dart';
import 'package:vayug/features/ads/data/services/ad_service.dart';
import 'package:vayug/features/auth/data/services/logout_service.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_static_views.dart';
import 'package:vayug/shared/services/cloudflare_r2_service.dart';
import 'package:vayug/features/ads/data/services/ad_refresh_notifier.dart';
import 'package:vayug/features/ads/data/ad_model.dart';
import 'dart:io';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/shared/managers/activity_recovery_manager.dart';
import 'package:vayug/shared/models/app_activity.dart';

class CreateAdScreenRefactored extends ConsumerStatefulWidget {
  const CreateAdScreenRefactored({super.key});

  @override
  ConsumerState<CreateAdScreenRefactored> createState() =>
      _CreateAdScreenRefactoredState();
}

class _CreateAdScreenRefactoredState extends ConsumerState<CreateAdScreenRefactored>
    with WidgetsBindingObserver {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _linkController = TextEditingController();
  final _budgetController = TextEditingController();
  final _targetAudienceController = TextEditingController();
  final _keywordsController = TextEditingController();
  bool _agreeToTerms = false;

  // Ad type and media
  String _selectedAdType = 'banner';
  File? _selectedImage;
  File? _selectedVideo;
  final List<File> _selectedImages = [];

  // Campaign settings
  DateTime? _startDate;
  DateTime? _endDate;

  // Advanced targeting
  int? _minAge;
  int? _maxAge;
  String _selectedGender = 'all';
  final List<String> _selectedLocations = [];
  final List<String> _selectedInterests = [];
  final List<String> _selectedPlatforms = [];

  // **NEW: Additional targeting fields**
  String _deviceType = 'all';
  String? _optimizationGoal = 'impressions';
  int? _frequencyCap = 3;
  String? _timeZone = 'Asia/Kolkata';
  final Map<String, bool> _dayParting = {};
  // **NEW: Advanced KPI fields**
  String? _bidType = 'CPM';
  double? _bidAmount;
  String? _pacing = 'smooth';
  double? _targetCPA;
  double? _targetROAS;
  int? _attributionWindow;

  // State management
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // **NEW: Simple mode for beginners**
  bool _showAdvancedSettings = false;

  // **NEW: Field-specific validation states**
  bool _isTitleValid = true;
  bool _isDescriptionValid = true;
  bool _isLinkValid = true;
  bool _isMediaValid = true;
  String? _titleError;
  String? _descriptionError;
  String? _linkError;
  String? _mediaError;

  // Services retrieved via ref.read(adServiceProvider) in methods
  final CloudflareR2Service _cloudflareService = CloudflareR2Service();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // **NEW: Smart defaults for beginners**
    _budgetController.text = '300.00'; // Recommended ₹300/day
    _targetAudienceController.text = 'smart'; // Smart targeting
    _keywordsController.text = 'general'; // Default keywords

    // **NEW: Auto-set dates (14 days from now)**
    final now = DateTime.now();
    _startDate = now;
    _endDate = now.add(const Duration(days: 14));

    // **NEW: Smart targeting defaults**
    _selectedGender = 'all';
    _deviceType = 'all';
    _optimizationGoal = 'impressions';
    _frequencyCap = 3;
    _timeZone = 'Asia/Kolkata';
    // **NEW: Advanced KPI defaults**
    _bidType = 'CPM';
    _pacing = 'smooth';

    // **FIX: Pause videos when entering create ad screen**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pauseBackgroundVideos();
    });

    // **NEW: Restore form state if user had previously minimized the app**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreFormState();
    });

    try {
      PaymentHandlerWidget.initialize();
    } catch (e) {
      // Continue without payment handler - user can still create ads
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    _budgetController.dispose();
    _targetAudienceController.dispose();
    _keywordsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Reset UI to a fresh state after successful ad creation
  void _showFreshAdScreen() {
    // Clear all form fields and saved state
    _clearForm();
    // Clear global activity
    ActivityRecoveryManager().clearActivity();
    // Scroll to top for a clean start
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    // Inform user
    if (mounted) {
      VayuSnackBar.showSuccess(context, AppText.get('ad_created_success'),
          duration: const Duration(seconds: 2));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    AppLogger.log('🔍 CreateAdScreen: App lifecycle changed to $state');

    // **FIX: Handle app lifecycle properly to maintain state**
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      AppLogger.log(
        '🛑 CreateAdScreen: App backgrounded - pausing videos and saving state',
      );
      _pauseBackgroundVideos();
      _saveFormState();
    } else if (state == AppLifecycleState.resumed) {
      AppLogger.log('▶️ CreateAdScreen: App resumed - restoring state');
      _restoreFormState();
      // Don't resume videos automatically - let user navigate back to video feed
    }
  }

  /// **FIX: Pause videos in background when minimizing from create ad screen**
  void _pauseBackgroundVideos() {
    try {
      // Use providers for services
      final mainController = ref.read(mainControllerProvider);
      mainController.forcePauseVideos();
      AppLogger.log('✅ CreateAdScreen: Background videos paused successfully');
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error pausing background videos: $e');
    }
  }

  /// **NEW: Save form state when app is minimized**
  void _saveFormState() {
    try {
      AppLogger.log('💾 CreateAdScreen: Saving form state...');

      // Save form data to SharedPreferences (Legacy)
      _saveFormData();

      // Save to ActivityRecoveryManager (New Global System)
      _saveToActivityManager();

      AppLogger.log('✅ CreateAdScreen: Form state saved successfully');
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error saving form state: $e');
    }
  }

  Future<void> _saveToActivityManager() async {
    final data = {
      'title': _titleController.text,
      'description': _descriptionController.text,
      'link': _linkController.text,
      'budget': _budgetController.text,
      'adType': _selectedAdType,
      // We can add more fields if needed, but these are the main ones
    };
    await ActivityRecoveryManager().saveActivity(ActivityType.adCreation, data);
  }

  /// **NEW: Restore form state when app is resumed**
  void _restoreFormState() {
    try {
      AppLogger.log('🔄 CreateAdScreen: Restoring form state...');

      // Restore form data from SharedPreferences
      _restoreFormData();

      AppLogger.log('✅ CreateAdScreen: Form state restored successfully');
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error restoring form state: $e');
    }
  }

  /// **NEW: Save form data to SharedPreferences**
  void _saveFormData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save all form fields
      await prefs.setString('create_ad_title', _titleController.text);
      await prefs.setString(
        'create_ad_description',
        _descriptionController.text,
      );
      await prefs.setString('create_ad_link', _linkController.text);
      await prefs.setString('create_ad_budget', _budgetController.text);
      await prefs.setString(
        'create_ad_target_audience',
        _targetAudienceController.text,
      );
      await prefs.setString('create_ad_keywords', _keywordsController.text);
      await prefs.setString('create_ad_type', _selectedAdType);

      // Save dates
      if (_startDate != null) {
        await prefs.setString(
          'create_ad_start_date',
          _startDate!.millisecondsSinceEpoch.toString(),
        );
      }
      if (_endDate != null) {
        await prefs.setString(
          'create_ad_end_date',
          _endDate!.millisecondsSinceEpoch.toString(),
        );
      }

      // Save targeting data
      await prefs.setString('create_ad_min_age', _minAge?.toString() ?? '');
      await prefs.setString('create_ad_max_age', _maxAge?.toString() ?? '');
      await prefs.setString('create_ad_gender', _selectedGender);
      await prefs.setStringList('create_ad_locations', _selectedLocations);
      await prefs.setStringList('create_ad_interests', _selectedInterests);
      await prefs.setStringList('create_ad_platforms', _selectedPlatforms);

      // Save additional targeting
      await prefs.setString('create_ad_device_type', _deviceType);
      await prefs.setString(
        'create_ad_optimization_goal',
        _optimizationGoal ?? '',
      );
      await prefs.setString(
        'create_ad_frequency_cap',
        _frequencyCap?.toString() ?? '',
      );
      await prefs.setString('create_ad_timezone', _timeZone ?? '');

      // Save day parting
      final dayPartingKeys = _dayParting.keys.toList();
      final dayPartingValues =
          _dayParting.values.map((v) => v.toString()).toList();
      await prefs.setStringList('create_ad_day_parting_keys', dayPartingKeys);
      await prefs.setStringList(
        'create_ad_day_parting_values',
        dayPartingValues,
      );

      AppLogger.log('✅ CreateAdScreen: Form data saved to SharedPreferences');
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error saving form data: $e');
    }
  }

  /// **NEW: Restore form data from SharedPreferences**
  void _restoreFormData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Restore all form fields
      _titleController.text = prefs.getString('create_ad_title') ?? '';
      _descriptionController.text =
          prefs.getString('create_ad_description') ?? '';
      _linkController.text = prefs.getString('create_ad_link') ?? '';
      _budgetController.text = prefs.getString('create_ad_budget') ?? '100.00';
      _targetAudienceController.text =
          prefs.getString('create_ad_target_audience') ?? 'all';
      _keywordsController.text = prefs.getString('create_ad_keywords') ?? '';
      _selectedAdType = prefs.getString('create_ad_type') ?? 'banner';

      // Restore dates
      final startDateStr = prefs.getString('create_ad_start_date');
      if (startDateStr != null && startDateStr.isNotEmpty) {
        _startDate = DateTime.fromMillisecondsSinceEpoch(
          int.parse(startDateStr),
        );
      }
      final endDateStr = prefs.getString('create_ad_end_date');
      if (endDateStr != null && endDateStr.isNotEmpty) {
        _endDate = DateTime.fromMillisecondsSinceEpoch(int.parse(endDateStr));
      }

      // Restore targeting data
      final minAgeStr = prefs.getString('create_ad_min_age');
      _minAge = minAgeStr != null && minAgeStr.isNotEmpty
          ? int.parse(minAgeStr)
          : null;
      final maxAgeStr = prefs.getString('create_ad_max_age');
      _maxAge = maxAgeStr != null && maxAgeStr.isNotEmpty
          ? int.parse(maxAgeStr)
          : null;
      _selectedGender = prefs.getString('create_ad_gender') ?? 'all';
      _selectedLocations.clear();
      _selectedLocations.addAll(
        prefs.getStringList('create_ad_locations') ?? [],
      );
      _selectedInterests.clear();
      _selectedInterests.addAll(
        prefs.getStringList('create_ad_interests') ?? [],
      );
      _selectedPlatforms.clear();
      _selectedPlatforms.addAll(
        prefs.getStringList('create_ad_platforms') ?? [],
      );

      // Restore additional targeting
      _deviceType = prefs.getString('create_ad_device_type') ?? 'all';
      _optimizationGoal = prefs.getString('create_ad_optimization_goal');
      final frequencyCapStr = prefs.getString('create_ad_frequency_cap');
      _frequencyCap = frequencyCapStr != null && frequencyCapStr.isNotEmpty
          ? int.parse(frequencyCapStr)
          : 3;
      _timeZone = prefs.getString('create_ad_timezone') ?? 'Asia/Kolkata';

      // Restore day parting
      _dayParting.clear();
      final dayPartingKeys =
          prefs.getStringList('create_ad_day_parting_keys') ?? [];
      final dayPartingValues =
          prefs.getStringList('create_ad_day_parting_values') ?? [];
      for (int i = 0;
          i < dayPartingKeys.length && i < dayPartingValues.length;
          i++) {
        _dayParting[dayPartingKeys[i]] = dayPartingValues[i] == 'true';
      }

      // Trigger UI update
      if (mounted) {
        setState(() {});
      }

      AppLogger.log(
        '✅ CreateAdScreen: Form data restored from SharedPreferences',
      );
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error restoring form data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authController = ref.watch(googleSignInProvider);
    final isSignedIn = authController.isSignedIn;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: !isSignedIn
          ? CustomScrollView(
              slivers: [
                _buildSliverAppBar(),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ProfileSignInView(
                    onGoogleSignIn: () async {
                      final user = await authController.signIn();
                      if (user != null) {
                        await LogoutService.refreshAllState(ref);
                      }
                    },
                  ),
                ),
              ],
            )
          : _buildCreateAdForm(),
      // Pinned so the primary action is visible without scrolling
      bottomNavigationBar: isSignedIn ? _buildSubmitBar() : null,
    );
  }

  Widget _buildSubmitBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary,
        border: Border(
          top: BorderSide(color: AppColors.borderPrimary.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: AppButton(
            onPressed: _isLoading ? null : _submitAd,
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
            label: _isLoading
                ? AppText.get('btn_creating_ad')
                : AppText.get('btn_create_ad'),
            variant: AppButtonVariant.primary,
            isLoading: _isLoading,
            isFullWidth: true,
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      title: Text(
        AppText.get('ad_create_title'),
        style: AppTypography.headlineSmall.copyWith(
          fontWeight: AppTypography.weightBold,
          color: AppColors.textPrimary,
        ),
      ),
      backgroundColor: AppColors.backgroundPrimary,
      centerTitle: true,
      elevation: 0,
      floating: true,
      snap: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.primary),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildCreateAdForm() {
    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        _buildSliverAppBar(),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Success/Error Messages
              if (_successMessage != null) _buildSuccessMessage(),
              if (_errorMessage != null) _buildErrorMessage(),

              // 1. Ad Type Selection
              _buildSettingRow(
                icon: Icons.ads_click_rounded,
                title: 'Ad Format',
                subtitle: _selectedAdType.toUpperCase(),
                trailing: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textTertiary),
                onTap: () => _showAdTypeSelector(),
              ),

              // 2. Media Upload
              _buildSettingRow(
                icon: Icons.perm_media_rounded,
                title: 'Campaign Media',
                trailing: _buildMediaStatus(),
                onTap: () => _showMediaUploader(),
              ),

              // 3. Ad Content (Title, Description, Link)
              _buildSettingRow(
                icon: Icons.edit_note_rounded,
                title: 'Ad Details',
                subtitle: _titleController.text.isEmpty ? 'Set title & link' : _titleController.text,
                trailing: _isTitleValid && _isLinkValid 
                    ? const Icon(Icons.check_circle, color: AppColors.success, size: 18)
                    : const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                onTap: () => _showAdDetailsEditor(),
              ),

              // 4. Budget & Duration
              _buildSettingRow(
                icon: Icons.payments_rounded,
                title: 'Budget & Duration',
                subtitle: '₹${_budgetController.text}/day for ${_endDate?.difference(_startDate ?? DateTime.now()).inDays ?? 0} days',
                onTap: () => _showBudgetDurationEditor(),
              ),

              // 5. Targeting (Advanced)
              _buildSettingRow(
                icon: Icons.ads_click_rounded,
                title: 'Targeting & Optimization',
                subtitle: _selectedLocations.isEmpty ? 'Smart Targeting' : '${_selectedLocations.length} locations',
                onTap: () => setState(() => _showAdvancedSettings = !_showAdvancedSettings),
              ),

              if (_showAdvancedSettings)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
                  ),
                  child: TargetingSectionWidget(
                    minAge: _minAge,
                    maxAge: _maxAge,
                    selectedGender: _selectedGender,
                    selectedLocations: _selectedLocations,
                    selectedInterests: _selectedInterests,
                    selectedPlatforms: _selectedPlatforms,
                    deviceType: _deviceType,
                    optimizationGoal: _optimizationGoal,
                    frequencyCap: _frequencyCap,
                    timeZone: _timeZone,
                    dayParting: _dayParting,
                    bidType: _bidType,
                    bidAmount: _bidAmount,
                    pacing: _pacing,
                    targetCPA: _targetCPA,
                    targetROAS: _targetROAS,
                    attributionWindow: _attributionWindow,
                    onMinAgeChanged: (age) => setState(() => _minAge = age),
                    onMaxAgeChanged: (age) => setState(() => _maxAge = age),
                    onGenderChanged: (gender) => setState(() => _selectedGender = gender),
                    onLocationsChanged: (locs) => setState(() { _selectedLocations.clear(); _selectedLocations.addAll(locs); }),
                    onInterestsChanged: (ints) => setState(() { _selectedInterests.clear(); _selectedInterests.addAll(ints); }),
                    onPlatformsChanged: (plats) => setState(() { _selectedPlatforms.clear(); _selectedPlatforms.addAll(plats); }),
                    onDeviceTypeChanged: (dt) => setState(() => _deviceType = dt),
                    onOptimizationGoalChanged: (goal) => setState(() => _optimizationGoal = goal),
                    onFrequencyCapChanged: (cap) => setState(() => _frequencyCap = cap),
                    onTimeZoneChanged: (tz) => setState(() => _timeZone = tz),
                    onDayPartingChanged: (dp) => setState(() { _dayParting.clear(); _dayParting.addAll(dp); }),
                    onBidTypeChanged: (bt) => setState(() => _bidType = bt),
                    onBidAmountChanged: (ba) => setState(() => _bidAmount = ba),
                    onPacingChanged: (p) => setState(() => _pacing = p),
                    onTargetCPAChanged: (cpa) => setState(() => _targetCPA = cpa),
                    onTargetROASChanged: (roas) => setState(() => _targetROAS = roas),
                    onAttributionWindowChanged: (aw) => setState(() => _attributionWindow = aw),
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // Preview & Legal
              CampaignPreviewWidget(
                startDate: _startDate,
                endDate: _endDate,
                budgetText: _budgetController.text,
                selectedAdType: _selectedAdType,
              ),
              _buildLegalAgreement(),
              _buildValidationSummary(),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ],
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
                    Text(subtitle, style: const TextStyle(color: AppColors.textTertiary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing,
            ] else 
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaStatus() {
    bool hasMedia = _selectedImage != null || _selectedVideo != null || _selectedImages.isNotEmpty;
    return Text(
      hasMedia ? 'Selected' : 'None',
      style: TextStyle(
        color: hasMedia ? AppColors.success : AppColors.textTertiary,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    );
  }

  void _showAdTypeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: AdTypeSelectorWidget(
          selectedAdType: _selectedAdType,
          onAdTypeChanged: (type) {
            Navigator.pop(context);
            _handleAdTypeChanged(type);
          },
          onShowBenefits: () => PaymentHandlerWidget.showAdvertisingBenefits(context),
        ),
      ),
    );
  }

  void _showMediaUploader() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaUploaderWidget(
                selectedAdType: _selectedAdType,
                selectedImage: _selectedImage,
                selectedVideo: _selectedVideo,
                selectedImages: _selectedImages,
                onImageSelected: (image) { setState(() => _selectedImage = image); setModalState((){}); _validateField('media'); },
                onVideoSelected: (video) { setState(() => _selectedVideo = video); setModalState((){}); _validateField('media'); },
                onImagesSelected: (images) { setState(() { _selectedImages.clear(); _selectedImages.addAll(images); }); setModalState((){}); _validateField('media'); },
                onError: (error) => setState(() => _errorMessage = error),
                isMediaValid: _isMediaValid,
                mediaError: _mediaError,
              ),
              const SizedBox(height: 24),
              AppButton(onPressed: () => Navigator.pop(context), label: 'Done', variant: AppButtonVariant.primary, isFullWidth: true),
            ],
          ),
        ),
      ),
    );
  }

  void _showAdDetailsEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 24, right: 24, top: 24),
        child: Form( // Local form for details
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ad Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 16),
              AdDetailsFormWidget(
                titleController: _titleController,
                descriptionController: _descriptionController,
                linkController: _linkController,
                adType: _selectedAdType,
                onClearErrors: _clearErrorMessages,
                onFieldChanged: (f) { _validateField(f); setState((){}); },
                isTitleValid: _isTitleValid,
                isDescriptionValid: _isDescriptionValid,
                isLinkValid: _isLinkValid,
                titleError: _titleError,
                descriptionError: _descriptionError,
                linkError: _linkError,
              ),
              const SizedBox(height: 24),
              AppButton(onPressed: () => Navigator.pop(context), label: 'Confirm Details', variant: AppButtonVariant.primary, isFullWidth: true),
            ],
          ),
        ),
      ),
    );
  }

  void _showBudgetDurationEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Budget & Duration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _budgetController,
                decoration: InputDecoration(labelText: 'Daily Budget', prefixText: '₹', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                keyboardType: TextInputType.number,
                onChanged: (v) { _validateField('budget'); setState((){}); setModalState((){}); },
              ),
              const SizedBox(height: 20),
              const Text('Quick Duration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final days in [7, 14, 30])
                    ChoiceChip(
                      label: Text('$days days'),
                      selected: _endDate?.difference(_startDate ?? DateTime.now()).inDays == days,
                      onSelected: (_) => setModalState(() { _startDate = DateTime.now(); _endDate = _startDate!.add(Duration(days: days)); setState((){}); }),
                    ),
                  ChoiceChip(label: const Text('Custom'), selected: false, onSelected: (_) async { await _selectDateRange(); setModalState((){}); }),
                ],
              ),
              const SizedBox(height: 24),
              AppButton(onPressed: () => Navigator.pop(context), label: 'Save Budget', variant: AppButtonVariant.primary, isFullWidth: true),
            ],
          ),
        ),
      ),
    );
  }

  /// **NEW: Build Legal Agreement Checkbox**
  Widget _buildLegalAgreement() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: _agreeToTerms,
            onChanged: (value) {
              setState(() {
                _agreeToTerms = value ?? false;
                if (_agreeToTerms) _errorMessage = null;
              });
            },
            title: Wrap(
              children: [
                const Text(
                  'I agree to the ',
                  style: TextStyle(fontSize: 13),
                ),
                GestureDetector(
                  onTap: () => _launchURL('https://snehayog.site/terms.html'),
                  child: const Text(
                    'Terms & Conditions',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: AppTypography.weightBold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const Text(
                  ' and ',
                  style: TextStyle(fontSize: 13),
                ),
                GestureDetector(
                  onTap: () => _launchURL('https://snehayog.site/privacy.html'),
                  child: const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: AppTypography.weightBold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  /// Helper to launch URLs
  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        AppLogger.log('❌ Could not launch $url');
        if (mounted) {
          VayuSnackBar.showError(context, 'Could not open link');
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error launching URL: $e');
    }
  }

  Widget _buildSuccessMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.success.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.success,
            size: 24,
          ),
          AppSpacing.hSpace12,
          Expanded(
            child: Text(
              _successMessage!,
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 14,
                fontWeight: AppTypography.weightMedium,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _successMessage = null),
            icon: const Icon(Icons.close, color: AppColors.success, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.error.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 24),
              AppSpacing.hSpace8,
              const Expanded(
                child: Text(
                  'Error',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 16,
                    fontWeight: AppTypography.weightBold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _errorMessage = null),
                icon: const Icon(Icons.close, color: AppColors.error, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          AppSpacing.vSpace8,
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          if (_errorMessage!.contains('upload') ||
              _errorMessage!.contains('media') ||
              _errorMessage!.contains('network'))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  AppButton(
                    onPressed: () {
                      setState(() => _errorMessage = null);
                      _clearMediaSelection();
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: 'Try Again',
                    variant: AppButtonVariant.primary,
                  ),
                  AppSpacing.hSpace12,
                  AppButton(
                    onPressed: () => setState(() => _errorMessage = null),
                    label: 'Dismiss',
                    variant: AppButtonVariant.outline,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _handleAdTypeChanged(String newAdType) {
    // **FIXED: Use addPostFrameCallback to maintain scroll position**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _selectedAdType = newAdType;

        // Clear inappropriate media when ad type changes
        if (newAdType == 'banner') {
          if (_selectedVideo != null) {
            _selectedVideo = null;
            _errorMessage = AppText.get('ad_banner_only_images');
          }
          if (_selectedImages.isNotEmpty) {
            _selectedImages.clear();
            _errorMessage = AppText.get('ad_banner_single_image');
          }
        } else if (newAdType == 'carousel') {
          if (_selectedImage != null ||
              _selectedVideo != null ||
              _selectedImages.isNotEmpty) {
            _selectedImage = null;
            _selectedVideo = null;
            _selectedImages.clear();
            _errorMessage = AppText.get('ad_carousel_exclusive');
          }
        }

        _clearErrorMessages();
      });
    });
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _clearErrorMessages();
      });
    }
  }

  void _clearErrorMessages() {
    if (_errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _errorMessage = null);
      });
    }
  }

  void _clearFieldErrors() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isTitleValid = true;
        _isDescriptionValid = true;
        _isLinkValid = true;
        _isMediaValid = true;
        _titleError = null;
        _descriptionError = null;
        _linkError = null;
        _mediaError = null;
      });
    });
  }

  // **NEW: Real-time field validation**
  void _validateField(String fieldName) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (fieldName) {
        case 'title':
          // Title is required for all ad types including banner
          if (_titleController.text.trim().isEmpty) {
            setState(() {
              _isTitleValid = false;
              _titleError = AppText.get('ad_title_required');
            });
          } else {
            // Check word count for banner ads (max 30 words)
            if (_selectedAdType == 'banner') {
              final wordCount =
                  _titleController.text.trim().split(RegExp(r'\s+')).length;
              if (wordCount > 30) {
                setState(() {
                  _isTitleValid = false;
                  _titleError = AppText.get('ad_title_too_long');
                });
              } else {
                setState(() {
                  _isTitleValid = true;
                  _titleError = null;
                });
              }
            } else {
              setState(() {
                _isTitleValid = true;
                _titleError = null;
              });
            }
          }
          break;
        case 'description':
          // Skip description validation for banner ads
          if (_selectedAdType == 'banner') {
            setState(() {
              _isDescriptionValid = true;
              _descriptionError = null;
            });
          } else if (_descriptionController.text.trim().isEmpty) {
            setState(() {
              _isDescriptionValid = false;
              _descriptionError = AppText.get('ad_description_required');
            });
          } else {
            setState(() {
              _isDescriptionValid = true;
              _descriptionError = null;
            });
          }
          break;
        case 'link':
          if (_linkController.text.trim().isEmpty) {
            setState(() {
              _isLinkValid = false;
              _linkError = AppText.get('ad_link_required');
            });
          } else {
            setState(() {
              _isLinkValid = true;
              _linkError = null;
            });
          }
          break;
        case 'budget':
          if (_budgetController.text.trim().isEmpty) {
            // No action needed for local state
          } else {
            try {
              // budget validation logic (can be added back if local state is needed)
            } catch (e) {
              // budget error logic
            }
          }
          break;
        case 'media':
          if (_selectedAdType == 'banner' && _selectedImage == null) {
            setState(() {
              _isMediaValid = false;
              _mediaError = AppText.get('ad_banner_image_required');
            });
          } else if (_selectedAdType == 'carousel' &&
              _selectedImages.isEmpty &&
              _selectedVideo == null) {
            setState(() {
              _isMediaValid = false;
              _mediaError = AppText.get('ad_carousel_media_required');
            });
          } else {
            setState(() {
              _isMediaValid = true;
              _mediaError = null;
            });
          }
          break;
      }
    });
  }

  Widget _buildValidationSummary() {
    final List<Map<String, dynamic>> validationItems = [];

    // Show title for all ad types (including banner)
    validationItems.add({
      'label': _selectedAdType == 'banner'
          ? AppText.get('ad_banner_title_max')
          : AppText.get('ad_title'),
      'isValid': _titleController.text.trim().isNotEmpty &&
          (_selectedAdType != 'banner' ||
              _titleController.text.trim().split(RegExp(r'\s+')).length <= 30),
      'icon': Icons.title,
    });

    // Only show description for non-banner ads
    if (_selectedAdType != 'banner') {
      validationItems.add({
        'label': AppText.get('ad_description'),
        'isValid': _descriptionController.text.trim().isNotEmpty,
        'icon': Icons.description,
      });
    }

    // Link URL is required for all ad types
    validationItems.add({
      'label': _selectedAdType == 'banner'
          ? AppText.get('ad_destination_url')
          : AppText.get('ad_link_url'),
      'isValid': _linkController.text.trim().isNotEmpty,
      'icon': Icons.link,
    });

    // Budget, dates, and media are required for all ad types
    validationItems.addAll([
      {
        'label': AppText.get('ad_budget_min'),
        'isValid': _budgetController.text.trim().isNotEmpty &&
            (double.tryParse(_budgetController.text.trim()) ?? 0) >= 100,
        'icon': Icons.attach_money,
      },
      {
        'label': AppText.get('ad_campaign_dates'),
        'isValid': _startDate != null && _endDate != null,
        'icon': Icons.calendar_today,
      },
      {
        'label': AppText.get('ad_media_file'),
        'isValid': _isMediaValid,
        'icon': _selectedAdType == 'banner' ? Icons.image : Icons.video_library,
      },
      {
        'label': 'Agree to Terms & Privacy Policy',
        'isValid': _agreeToTerms,
        'icon': Icons.gavel,
      },
    ]);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppText.get('ad_required_fields'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: AppTypography.weightBold),
            ),
            AppSpacing.vSpace12,
            ...validationItems.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      item['isValid']
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: item['isValid']
                          ? AppColors.success
                          : AppColors.textSecondary,
                      size: 20,
                    ),
                    AppSpacing.hSpace8,
                    Icon(
                      item['icon'] as IconData,
                      color: item['isValid']
                          ? AppColors.success
                          : AppColors.textSecondary,
                      size: 16,
                    ),
                    AppSpacing.hSpace8,
                    Expanded(
                      child: Text(
                        item['label'] as String,
                        style: TextStyle(
                          color: item['isValid']
                              ? AppColors.success
                              : AppColors.textSecondary,
                          fontWeight: item['isValid']
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearMediaSelection() {
    setState(() {
      _selectedImage = null;
      _selectedVideo = null;
      _selectedImages.clear();
    });
  }

  /// **NEW: Notify video feed to refresh ads**
  void _notifyVideoFeedRefresh() {
    try {
      AppLogger.log('🔄 CreateAdScreen: Notifying video feed to refresh ads');
      AdRefreshNotifier().notifyRefresh();
      AppLogger.log('✅ CreateAdScreen: Video feed notification sent');
    } catch (e) {
      AppLogger.log('❌ Error notifying video feed refresh: $e');
    }
  }

  Future<void> _submitAd() async {
    if (!_validateForm()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Step 1: Upload media files
      setState(() {
        _errorMessage = AppText.get('ad_error_uploading_media');
      });

      final mediaUrls = await _uploadMediaFiles();
      if (mediaUrls.isEmpty) {
        throw Exception(
          AppText.get('ad_error_media_failed'),
        );
      }

      // Step 2: Create ad with payment
      setState(() {
        _errorMessage = AppText.get('ad_error_creating');
      });

      final result = await ref.read(adServiceProvider).createAdWithPayment(
        // For banner ads, title and description are optional (use defaults)
        title: _selectedAdType == 'banner'
            ? (_titleController.text.trim().isEmpty
                ? 'Banner Ad'
                : _titleController.text.trim())
            : _titleController.text.trim(),
        description: _selectedAdType == 'banner'
            ? (_descriptionController.text.trim().isEmpty
                ? 'Click to learn more'
                : _descriptionController.text.trim())
            : _descriptionController.text.trim(),
        imageUrl: _getImageUrl(mediaUrls),
        videoUrl: _selectedVideo != null ? mediaUrls.first : null,
        link: _linkController.text.trim(),
        adType: _selectedAdType,
        budget: double.parse(_budgetController.text.trim()),
        targetAudience: _targetAudienceController.text.trim(),
        targetKeywords: _keywordsController.text
            .trim()
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        startDate: _startDate,
        endDate: _endDate,
        minAge: _minAge,
        maxAge: _maxAge,
        gender: _selectedGender != 'all' ? _selectedGender : null,
        locations: _selectedLocations.isNotEmpty ? _selectedLocations : null,
        interests: _selectedInterests.isNotEmpty ? _selectedInterests : null,
        platforms: _selectedPlatforms.isNotEmpty ? _selectedPlatforms : null,
        deviceType: _deviceType,
        optimizationGoal: _optimizationGoal,
        frequencyCap: _frequencyCap,
        timeZone: _timeZone,
        dayParting: _dayParting.isNotEmpty ? _dayParting : null,
        // **NEW: Advanced KPI parameters**
        bidType: _bidType,
        bidAmount: _bidAmount,
        pacing: _pacing,
        targetCPA: _targetCPA,
        targetROAS: _targetROAS,
        attributionWindow: _attributionWindow,
        // **NEW: Pass all carousel image URLs**
        imageUrls: _selectedAdType == 'carousel' && _selectedImages.isNotEmpty
            ? mediaUrls
            : null,
      );

      if (result['success']) {
        setState(() {
          _successMessage = AppText.get('success_ad_created_full');
          _errorMessage = null;
        });

        // Immediately reset the form for a fresh experience
        _showFreshAdScreen();
        _notifyVideoFeedRefresh();

        // Then show payment options (doesn't depend on current form fields)
        if (mounted) {
          PaymentHandlerWidget.showPaymentOptions(
            context,
            AdModel.fromJson(result['ad']),
            result['invoice'],
            () {
              // Payment completed – nothing extra to reset here
            },
          );
        }
      } else {
        throw Exception(
          AppText.get('ad_error_failed',
                  fallback: '❌ Failed to create ad: {message}')
              .replaceAll(
                  '{message}',
                  result['message'] ??
                      'Unknown error occurred. Please try again.'),
        );
      }
    } catch (e) {
      String errorMessage = e.toString().replaceAll('Exception: ', '');

      // Provide more specific error messages based on common issues
      if (errorMessage.contains('network') ||
          errorMessage.contains('connection')) {
        errorMessage = AppText.get('ad_error_network');
      } else if (errorMessage.contains('upload') ||
          errorMessage.contains('media')) {
        errorMessage = "${AppText.get('ad_error_media_upload')}: $errorMessage";
      } else if (errorMessage.contains('payment') ||
          errorMessage.contains('billing')) {
        errorMessage = AppText.get('ad_error_payment');
      } else if (errorMessage.contains('validation') ||
          errorMessage.contains('required')) {
        errorMessage = AppText.get('ad_error_validation');
      } else if (errorMessage.contains('server') ||
          errorMessage.contains('500')) {
        errorMessage = AppText.get('ad_error_server');
      } else if (errorMessage.contains('unauthorized') ||
          errorMessage.contains('401')) {
        errorMessage = AppText.get('ad_error_auth');
      } else if (errorMessage.contains('forbidden') ||
          errorMessage.contains('403')) {
        errorMessage = AppText.get('ad_error_forbidden');
      } else if (errorMessage.contains('Invalid Token')) {
        errorMessage = "🔐 Authentication Error: Your session token is invalid for the ad server. Please try logging out and logging back in. If the issue persists, your backend JWT_SECRET may be mismatched with the Cloudflare Worker secret.";
      }

      setState(() {
        _errorMessage = errorMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _validateForm() {
    // Clear previous errors
    _clearErrorMessages();
    _clearFieldErrors();

    bool isValid = true;

    // Check title (required for all ad types including banner)
    if (_titleController.text.trim().isEmpty) {
      setState(() {
        _isTitleValid = false;
        _titleError = AppText.get('ad_title_required');
        isValid = false;
      });
    } else {
      // Check word count for banner ads (max 30 words)
      if (_selectedAdType == 'banner') {
        final wordCount =
            _titleController.text.trim().split(RegExp(r'\s+')).length;
        if (wordCount > 30) {
          setState(() {
            _isTitleValid = false;
            _titleError = AppText.get('ad_title_too_long');
            isValid = false;
          });
        } else {
          setState(() {
            _isTitleValid = true;
            _titleError = null;
          });
        }
      } else {
        setState(() {
          _isTitleValid = true;
          _titleError = null;
        });
      }
    }

    // Check description (skip for banner ads)
    if (_selectedAdType != 'banner') {
      if (_descriptionController.text.trim().isEmpty) {
        setState(() {
          _isDescriptionValid = false;
          _descriptionError = AppText.get('ad_description_required');
          isValid = false;
        });
      } else {
        setState(() {
          _isDescriptionValid = true;
          _descriptionError = null;
        });
      }
    } else {
      setState(() {
        _isDescriptionValid = true;
        _descriptionError = null;
      });
    }

    // Check link
    if (_linkController.text.trim().isEmpty) {
      setState(() {
        _isLinkValid = false;
        _linkError = AppText.get('ad_link_required');
        isValid = false;
      });
    } else {
      setState(() {
        _isLinkValid = true;
        _linkError = null;
      });
    }

    // Check budget
    if (_budgetController.text.trim().isEmpty) {
      isValid = false;
    } else {
      // Validate budget format
      try {
        final budget = double.parse(_budgetController.text.trim());
        if (budget < 100) {
          isValid = false;
        }
      } catch (e) {
        isValid = false;
      }
    }

    // Check date range
    if (_startDate == null || _endDate == null) {
      isValid = false;
    } else {
      // Check if end date is after start date
      if (_endDate!.isBefore(_startDate!) || 
          _startDate!.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        isValid = false;
      }
    }

    // Check media requirements based on ad type
    if (_selectedAdType == 'banner' && _selectedImage == null) {
      setState(() {
        _isMediaValid = false;
        _mediaError = AppText.get('ad_banner_image_required');
        isValid = false;
      });
    } else if (_selectedAdType == 'carousel' &&
        _selectedImages.isEmpty &&
        _selectedVideo == null) {
      setState(() {
        _isMediaValid = false;
        _mediaError = AppText.get('ad_carousel_media_required');
        isValid = false;
      });
    } else {
      setState(() {
        _isMediaValid = true;
        _mediaError = null;
      });
    }

    // Check agreement to terms
    if (!_agreeToTerms) {
      setState(() {
        _errorMessage =
            'Please agree to the Terms & Conditions and Privacy Policy';
        isValid = false;
      });
    }

    // Check age range if specified
    if (_minAge != null && _maxAge != null && _minAge! > _maxAge!) {
      isValid = false;
    }

    return isValid;
  }

  Future<List<String>> _uploadMediaFiles() async {
    final List<String> mediaUrls = [];

    try {
      if (_selectedAdType == 'banner' && _selectedImage != null) {
        AppLogger.log('🔄 CreateAdScreen: Uploading banner image...');
        final imageUrl = await _cloudflareService.uploadImage(_selectedImage!);
        mediaUrls.add(imageUrl);
        AppLogger.log('✅ CreateAdScreen: Banner image uploaded: $imageUrl');
      } else if (_selectedAdType == 'carousel') {
        if (_selectedImages.isNotEmpty) {
          AppLogger.log(
            '🔄 CreateAdScreen: Uploading ${_selectedImages.length} carousel images...',
          );
          for (int i = 0; i < _selectedImages.length; i++) {
            final image = _selectedImages[i];
            AppLogger.log(
              '🔄 CreateAdScreen: Uploading carousel image ${i + 1}/${_selectedImages.length}...',
            );
            final imageUrl = await _cloudflareService.uploadImage(image);
            mediaUrls.add(imageUrl);
            AppLogger.log(
              '✅ CreateAdScreen: Carousel image ${i + 1} uploaded: $imageUrl',
            );
          }
        }
        if (_selectedVideo != null) {
          AppLogger.log('🔄 CreateAdScreen: Uploading carousel video...');
          AppLogger.log(
            '🔄 CreateAdScreen: Video file path: ${_selectedVideo!.path}',
          );
          AppLogger.log(
            '🔄 CreateAdScreen: Video file size: ${await _selectedVideo!.length()} bytes',
          );

          final result = await _cloudflareService.uploadVideoForAd(
            _selectedVideo!,
          );
          AppLogger.log('🔄 CreateAdScreen: Video upload result: $result');

          final videoUrl =
              result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
          if (videoUrl.isEmpty) {
            throw Exception(
              'Video upload succeeded but no URL returned. Result: $result',
            );
          }
          mediaUrls.add(videoUrl);
          AppLogger.log('✅ CreateAdScreen: Carousel video uploaded: $videoUrl');
        }
      }

      AppLogger.log(
        '✅ CreateAdScreen: All media files uploaded successfully. Total URLs: ${mediaUrls.length}',
      );
      return mediaUrls;
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error uploading media files: $e');
      rethrow;
    }
  }

  String? _getImageUrl(List<String> mediaUrls) {
    if (_selectedAdType == 'banner' && _selectedImage != null) {
      return mediaUrls.first;
    } else if (_selectedAdType == 'carousel' && _selectedImages.isNotEmpty) {
      return mediaUrls.first;
    }
    return null;
  }

  void _clearForm() {
    _titleController.clear();
    _descriptionController.clear();
    _linkController.clear();
    _budgetController.text = '100.00';
    _targetAudienceController.text = 'all';
    _keywordsController.clear();
    _selectedAdType = 'banner';
    _startDate = null;
    _endDate = null;
    _selectedImage = null;
    _selectedVideo = null;
    _selectedImages.clear();
    _minAge = null;
    _maxAge = null;
    _selectedGender = 'all';
    _selectedLocations.clear();
    _selectedInterests.clear();
    _selectedPlatforms.clear();

    // **NEW: Clear additional targeting fields**
    _deviceType = 'all';
    _optimizationGoal = 'impressions';
    _frequencyCap = 3;
    _timeZone = 'Asia/Kolkata';
    _dayParting.clear();
    // **NEW: Clear advanced KPI fields**
    _bidType = 'CPM';
    _bidAmount = null;
    _pacing = 'smooth';
    _targetCPA = null;
    _targetROAS = null;
    _attributionWindow = null;

    setState(() {
      _errorMessage = null;
      _successMessage = null;
      // **NEW: Clear validation states**
      _isTitleValid = true;
      _isDescriptionValid = true;
      _isLinkValid = true;
      _isMediaValid = true;
      _titleError = null;
      _descriptionError = null;
      _linkError = null;
      _mediaError = null;
    });

    // **NEW: Clear saved form state**
    _clearSavedFormState();
  }

  /// **NEW: Clear saved form state from SharedPreferences**
  void _clearSavedFormState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clear all saved form data
      await prefs.remove('create_ad_title');
      await prefs.remove('create_ad_description');
      await prefs.remove('create_ad_link');
      await prefs.remove('create_ad_budget');
      await prefs.remove('create_ad_target_audience');
      await prefs.remove('create_ad_keywords');
      await prefs.remove('create_ad_type');
      await prefs.remove('create_ad_start_date');
      await prefs.remove('create_ad_end_date');
      await prefs.remove('create_ad_min_age');
      await prefs.remove('create_ad_max_age');
      await prefs.remove('create_ad_gender');
      await prefs.remove('create_ad_locations');
      await prefs.remove('create_ad_interests');
      await prefs.remove('create_ad_platforms');
      await prefs.remove('create_ad_device_type');
      await prefs.remove('create_ad_optimization_goal');
      await prefs.remove('create_ad_frequency_cap');
      await prefs.remove('create_ad_timezone');
      await prefs.remove('create_ad_day_parting_keys');
      await prefs.remove('create_ad_day_parting_values');

      AppLogger.log('✅ CreateAdScreen: Saved form state cleared');
    } catch (e) {
      AppLogger.log('❌ CreateAdScreen: Error clearing saved form state: $e');
    }
  }
}
