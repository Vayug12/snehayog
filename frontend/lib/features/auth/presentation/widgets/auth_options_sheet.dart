import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/features/auth/presentation/controllers/google_sign_in_controller.dart';

Future<Map<String, dynamic>?> showAuthOptionsSheet({
  required BuildContext context,
  required GoogleSignInController authController,
  bool startWithPhone = false,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AuthOptionsSheet(
      authController: authController,
      startWithPhone: startWithPhone,
    ),
  );
}

class _AuthOptionsSheet extends StatefulWidget {
  const _AuthOptionsSheet({
    required this.authController,
    required this.startWithPhone,
  });

  final GoogleSignInController authController;
  final bool startWithPhone;

  @override
  State<_AuthOptionsSheet> createState() => _AuthOptionsSheetState();
}

class _AuthOptionsSheetState extends State<_AuthOptionsSheet> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  String? _challengeId;
  String? _maskedPhone;
  String? _error;
  String? _debugOtp;
  bool _busy = false;
  late bool _phoneMode;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _phoneMode = widget.startWithPhone;
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _requestOtp() async {
    final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      setState(() => _error = 'Enter a valid 10-digit Indian mobile number');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.authController.requestPhoneOtp('+91$phone');
      if (!mounted) return;
      setState(() {
        _challengeId = result['challengeId']?.toString();
        _maskedPhone = result['maskedPhone']?.toString();
        _debugOtp = result['debugOtp']?.toString();
      });
      _startResendTimer((result['resendAfterSeconds'] as num?)?.toInt() ?? 45);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(otp) || _challengeId == null) {
      setState(() => _error = 'Enter the 6-digit OTP');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.authController.verifyPhoneOtp(
        challengeId: _challengeId!,
        otp: otp,
      );
      if (mounted && user != null) Navigator.of(context).pop(user);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.authController.signIn();
      if (!mounted) return;
      if (result.isSuccess) {
        Navigator.of(context).pop(result.user);
      } else if (result.isFailure) {
        // Cancelling leaves the sheet untouched; only real failures explain.
        setState(() => _error = result.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF171717),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _challengeId == null
                  ? 'Sign in to continue'
                  : 'Verify your number',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _challengeId == null
                  ? 'Use your mobile number or Google account.'
                  : 'Enter the OTP sent to ${_maskedPhone ?? 'your mobile'}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            if (!_phoneMode && _challengeId == null) ...[
              FilledButton.icon(
                onPressed:
                    _busy ? null : () => setState(() => _phoneMode = true),
                icon: const Icon(Icons.phone_android),
                label: const Text('Continue with phone number'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: const Color(0xFF2EAD65),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _googleSignIn,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedGoogle,
                  color: Colors.white,
                  size: 22,
                ),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                ),
              ),
            ] else if (_challengeId == null) ...[
              TextField(
                controller: _phoneController,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                autofocus: true,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  counterText: '',
                  prefixText: '+91  ',
                  prefixStyle: const TextStyle(color: Colors.white),
                  hintText: 'Mobile number',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) {
                  if (!_busy) _requestOtp();
                },
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _requestOtp,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: const Color(0xFF2EAD65),
                ),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send OTP'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _busy ? null : _googleSignIn,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedGoogle,
                  color: Colors.white,
                  size: 18,
                ),
                label: const Text('Use Google instead'),
              ),
            ] else ...[
              TextField(
                controller: _otpController,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  letterSpacing: 8,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) {
                  if (!_busy) _verifyOtp();
                },
              ),
              if (_debugOtp != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Development OTP: $_debugOtp',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amber),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _verifyOtp,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: const Color(0xFF2EAD65),
                ),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify and continue'),
              ),
              TextButton(
                onPressed: _busy || _resendSeconds > 0 ? null : _requestOtp,
                child: Text(
                  _resendSeconds > 0
                      ? 'Resend OTP in ${_resendSeconds}s'
                      : 'Resend OTP',
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _challengeId = null;
                          _otpController.clear();
                          _error = null;
                        }),
                child: const Text('Change phone number'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
