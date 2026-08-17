import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/shared/services/app_remote_config_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/app_button.dart';

/// Forced Update Widget
///
/// This widget handles forced and soft app updates:
/// - Blocks app usage if version < minimum (forced update)
/// - Shows banner if version < latest (soft update)
/// - Provides update button that opens Play Store/App Store
class ForcedUpdateWidget extends StatefulWidget {
  final Widget child;
  final bool showSoftUpdateBanner;

  const ForcedUpdateWidget({
    super.key,
    required this.child,
    this.showSoftUpdateBanner = true,
  });

  @override
  State<ForcedUpdateWidget> createState() => _ForcedUpdateWidgetState();
}

class _ForcedUpdateWidgetState extends State<ForcedUpdateWidget>
    with WidgetsBindingObserver {
  VersionCheckResult? _versionCheck;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkVersion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkVersion();
    }
  }

  Future<void> _checkVersion() async {
    try {
      setState(() => _isChecking = true);

      final result = await AppRemoteConfigService.instance
          .checkAppVersion(refresh: true);

      if (mounted) {
        setState(() {
          _versionCheck = result;
          _isChecking = false;
        });
      }
    } catch (e) {
      AppLogger.log('❌ ForcedUpdateWidget: Error checking version: $e');
      if (mounted) {
        setState(() {
          _isChecking = false;
          // Assume supported if check fails
          _versionCheck = VersionCheckResult(
            isSupported: true,
            isLatest: true,
            updateRequired: false,
            updateRecommended: false,
          );
        });
      }
    }
  }

  Future<void> _openUpdateUrl() async {
    if (_versionCheck?.updateUrl != null) {
      final url = Uri.parse(_versionCheck!.updateUrl!);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        AppLogger.log(
            '❌ ForcedUpdateWidget: Cannot launch URL: ${_versionCheck!.updateUrl}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // If update is required, block the app
    if (_versionCheck?.updateRequired == true) {
      return _buildForcedUpdateScreen();
    }

    // Show soft update banner if recommended
    if (widget.showSoftUpdateBanner &&
        _versionCheck?.updateRecommended == true) {
      return Stack(
        children: [
          widget.child,
          _buildSoftUpdateBanner(),
        ],
      );
    }

    // App is up to date, show normally
    return widget.child;
  }

  /// Build forced update screen (blocks app usage)
  Widget _buildForcedUpdateScreen() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade700,
              Colors.blue.shade900,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.system_update,
                  size: 80,
                  color: Colors.white,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Update Required',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _versionCheck?.updateMessage ??
                      'A new version of the app is available. Please update to continue.',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                AppButton(
                  onPressed: _openUpdateUrl,
                  label: 'Update Now',
                  variant: AppButtonVariant.primary,
                  size: AppButtonSize.large,
                ),
                if (_versionCheck?.currentVersion != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Current Version: ${_versionCheck!.currentVersion}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white60,
                    ),
                  ),
                ],
                if (_versionCheck?.latestVersion != null) ...[
                  Text(
                    'Latest Version: ${_versionCheck!.latestVersion}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build soft update banner (non-blocking)
  Widget _buildSoftUpdateBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        elevation: 4,
        child: Container(
          color: Colors.orange.shade600,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _versionCheck?.updateMessage ??
                      'A new version is available with exciting features!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                onPressed: _openUpdateUrl,
                label: 'Update',
                variant: AppButtonVariant.text,
                size: AppButtonSize.small,
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    // Hide banner for this session
                    _versionCheck = VersionCheckResult(
                      isSupported: _versionCheck!.isSupported,
                      isLatest: false,
                      updateRequired: false,
                      updateRecommended: false,
                    );
                  });
                },
                icon: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
