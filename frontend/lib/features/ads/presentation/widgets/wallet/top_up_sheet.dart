import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/features/ads/data/services/ad_credit_purchase_service.dart';
import 'package:vayug/features/ads/data/services/wallet_service.dart';

/// Buy ad credits.
///
/// Opened from the wallet chip, the wallet screen, and the "not enough credits"
/// error on the create-ad screen — the last of which passes a [shortfall] so
/// the sheet can point at the smallest package that actually covers it.
class TopUpSheet extends ConsumerStatefulWidget {
  /// Credits the user is short by, when opened from a failed ad creation.
  final int? shortfall;

  const TopUpSheet({super.key, this.shortfall});

  /// Returns `true` if the balance went up while the sheet was open, so the
  /// caller can retry whatever it was doing.
  static Future<bool> show(BuildContext context, {int? shortfall}) async {
    final credited = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TopUpSheet(shortfall: shortfall),
    );
    return credited ?? false;
  }

  @override
  ConsumerState<TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends ConsumerState<TopUpSheet> {
  /// Identifier of the package currently being bought, if any.
  String? _purchasing;
  String? _status;
  bool _credited = false;
  int _pendingWatchGeneration = 0;

  bool get _isBusy => _purchasing != null;

  Future<void> _buy(Package package) async {
    if (_isBusy) return;
    final watchGeneration = ++_pendingWatchGeneration;

    setState(() {
      _purchasing = package.identifier;
      _status = null;
    });

    final result =
        await ref.read(adCreditPurchaseServiceProvider).purchase(package);

    if (!mounted) return;

    if (result.isPaid) {
      // The balance is authoritative on the server, so refresh rather than
      // trusting anything this process computed.
      ref.invalidate(adWalletProvider);
      ref.invalidate(adWalletTransactionsProvider);
      _credited = result.outcome == TopUpOutcome.credited;
    }

    setState(() {
      _purchasing = null;
      _status = result.message;
    });

    if (result.outcome == TopUpOutcome.pending) {
      unawaited(_watchPendingCredit(
        result.balanceBefore,
        watchGeneration,
      ));
    }

    // Only close on a confirmed credit. "Pending" stays open so the message
    // explaining that credits are still on the way is actually read.
    if (result.outcome == TopUpOutcome.credited && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _watchPendingCredit(
    int? balanceBefore,
    int watchGeneration,
  ) async {
    final balance =
        await ref.read(adCreditPurchaseServiceProvider).waitForCredit(
              balanceBefore,
              backoff: List<Duration>.filled(
                12,
                const Duration(seconds: 5),
              ),
            );

    if (!mounted ||
        watchGeneration != _pendingWatchGeneration ||
        balance == null) {
      return;
    }

    ref.invalidate(adWalletProvider);
    ref.invalidate(adWalletTransactionsProvider);
    setState(() {
      _credited = true;
      _status = 'Credits added to your wallet.';
    });

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted && watchGeneration == _pendingWatchGeneration) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packagesAsync = ref.watch(adCreditPackagesProvider);

    return PopScope(
      // A purchase is mid-flight against the Play billing client; letting the
      // sheet go now would leave the user with no feedback about their money.
      canPop: !_isBusy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add ad credits',
                    style: AppTypography.headlineSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: AppTypography.weightBold,
                    ),
                  ),
                ),
                if (!_isBusy)
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(_credited),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.shortfall != null
                  ? 'You need ₹${widget.shortfall} more to run this campaign.'
                  : '1 credit = ₹1 of ad spend.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            packagesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
              error: (_, __) => _buildUnavailable(
                'Could not load credit packs. Check your connection and try again.',
              ),
              data: (packages) {
                if (packages.isEmpty) {
                  return _buildUnavailable(
                    'Buying credits in the app is not available yet. '
                    'Contact support to have credits added to your account.',
                  );
                }
                return Column(
                  children: [
                    for (final package in packages) _buildPackage(package),
                  ],
                );
              },
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              _buildStatus(_status!),
            ],
            const SizedBox(height: 12),
            Text(
              'Credits are added by our servers once Google confirms the '
              'payment, so they can take a moment to appear.',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackage(Package package) {
    final product = package.storeProduct;
    final isThisOne = _purchasing == package.identifier;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _isBusy ? null : () => _buy(package),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.borderPrimary.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.title.isEmpty
                            ? package.identifier
                            : product.title,
                        style: AppTypography.titleSmall.copyWith(
                          color: _isBusy && !isThisOne
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                          fontWeight: AppTypography.weightBold,
                        ),
                      ),
                      if (product.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          product.description,
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isThisOne)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                else
                  Text(
                    // The store's own localised price string — never a price
                    // this app formats, which would be wrong in any other
                    // currency or tax regime.
                    product.priceString,
                    style: AppTypography.titleMedium.copyWith(
                      color:
                          _isBusy ? AppColors.textTertiary : AppColors.primary,
                      fontWeight: AppTypography.weightBold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnavailable(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(String message) {
    final good = _credited;
    final color = good ? AppColors.success : AppColors.info;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(good ? Icons.check_circle_rounded : Icons.schedule_rounded,
              size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
