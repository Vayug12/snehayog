import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/features/ads/data/services/wallet_service.dart';
import 'package:vayug/features/ads/presentation/screens/wallet_transactions_screen.dart';
import 'package:vayug/features/ads/presentation/widgets/wallet/top_up_sheet.dart';
import 'package:vayug/shared/config/app_config.dart';

/// Ad-credit balance shown on the create-ad screen.
///
/// Read-only by design: there is no top-up path yet (that ships with in-app
/// purchases), so the chip states the balance and links to history rather than
/// offering a button that would dead-end.
class WalletBalanceChip extends ConsumerWidget {
  const WalletBalanceChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(adWalletProvider);

    return walletAsync.when(
      loading: () => _Shell(
        child: Row(
          children: [
            const _Icon(Icons.account_balance_wallet_rounded, AppColors.primary),
            const SizedBox(width: 12),
            Text(
              'Loading credits…',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      // A failed balance read must not block ad creation — the server is the
      // authority on whether a campaign is affordable, not this chip.
      error: (error, _) => _Shell(
        onTap: () => ref.invalidate(adWalletProvider),
        child: Row(
          children: [
            const _Icon(Icons.error_outline_rounded, AppColors.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error is WalletException && error.isUnauthorized
                    ? 'Sign in to see your ad credits'
                    : 'Could not load your credits',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            Text(
              'Retry',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
      data: (wallet) => _Shell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const WalletTransactionsScreen(),
            ),
          );
        },
        child: Row(
          children: [
            _Icon(
              Icons.account_balance_wallet_rounded,
              wallet.isFrozen ? AppColors.warning : AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ad credits',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${wallet.balance}',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: AppTypography.weightBold,
                    ),
                  ),
                ],
              ),
            ),
            if (wallet.isFrozen)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'On hold',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.warning),
                ),
              )
            else if (AppConfig.adCreditPurchasesEnabled)
              TextButton(
                onPressed: () => TopUpSheet.show(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Add',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.primary),
                ),
              )
            else
              Row(
                children: [
                  Text(
                    'History',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.primary),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.primary),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _Shell({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.borderPrimary.withValues(alpha: 0.5),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _Icon(this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
