import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/features/ads/data/services/wallet_service.dart';
import 'package:vayug/features/ads/data/wallet_model.dart';
import 'package:vayug/features/ads/presentation/widgets/wallet/top_up_sheet.dart';
import 'package:vayug/shared/config/app_config.dart';

/// Ad-credit balance and ledger history.
///
/// The ledger is append-only on the server, so rows never change once written.
/// That means pages already loaded can be appended to without invalidation —
/// only page 1 is re-read on pull-to-refresh, to pick up new rows at the top.
class WalletTransactionsScreen extends ConsumerStatefulWidget {
  const WalletTransactionsScreen({super.key});

  @override
  ConsumerState<WalletTransactionsScreen> createState() =>
      _WalletTransactionsScreenState();
}

class _WalletTransactionsScreenState
    extends ConsumerState<WalletTransactionsScreen> {
  final ScrollController _scrollController = ScrollController();

  /// Rows beyond page 1. Page 1 stays owned by the provider so a refresh has a
  /// single source of truth for the top of the list.
  final List<AdCreditTransaction> _extraPages = [];

  int _lastLoadedPage = 1;
  bool _hasMore = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    // 400px of runway so the next page is usually already there by the time
    // the user reaches the bottom.
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    // The guard is the whole point: the scroll listener fires on every frame
    // of a fling, and without it one flick would issue a dozen requests.
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final page = await ref
          .read(walletServiceProvider)
          .getTransactions(page: _lastLoadedPage + 1);

      if (!mounted) return;
      setState(() {
        _extraPages.addAll(page.items);
        _lastLoadedPage = page.page;
        _hasMore = page.hasMore;
      });
    } on WalletException catch (e) {
      if (!mounted) return;
      // Stop paging on failure rather than retrying into a loop; pull-to-
      // refresh is the recovery path.
      setState(() => _hasMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _extraPages.clear();
      _lastLoadedPage = 1;
      _hasMore = false;
    });
    ref.invalidate(adWalletProvider);
    ref.invalidate(adWalletTransactionsProvider);
    await ref.read(adWalletTransactionsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(adWalletProvider);
    final transactionsAsync = ref.watch(adWalletTransactionsProvider);

    // Keep paging state in sync with whatever the provider currently holds.
    transactionsAsync.whenData((page) {
      if (_lastLoadedPage == 1 && _hasMore != page.hasMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hasMore = page.hasMore);
        });
      }
    });

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Ad Credits',
          style: AppTypography.headlineSmall.copyWith(
            fontWeight: AppTypography.weightBold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        backgroundColor: AppColors.surfacePrimary,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildBalanceCard(walletAsync)),
            ...transactionsAsync.when(
              loading: () => [
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
              ],
              error: (error, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildMessage(
                    Icons.error_outline_rounded,
                    error is WalletException
                        ? error.message
                        : 'Could not load your credit history',
                    AppColors.error,
                  ),
                ),
              ],
              data: (page) {
                final rows = [...page.items, ..._extraPages];
                if (rows.isEmpty) {
                  return [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildMessage(
                        Icons.receipt_long_rounded,
                        'No credit activity yet.\nYour purchases and campaign spend will appear here.',
                        AppColors.textSecondary,
                      ),
                    ),
                  ];
                }

                return [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildRow(rows[index]),
                        childCount: rows.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: _isLoadingMore
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(AsyncValue<AdWallet> walletAsync) {
    final wallet = walletAsync.valueOrNull ?? AdWallet.empty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.borderPrimary.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available balance',
            style: AppTypography.labelMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            walletAsync.isLoading ? '—' : '₹${wallet.balance}',
            style: AppTypography.displaySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: AppTypography.weightBold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '1 credit = ₹1 of ad spend',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textTertiary),
          ),
          if (AppConfig.adCreditPurchasesEnabled) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => TopUpSheet.show(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add credits'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                ),
              ),
            ),
          ],
          if (wallet.isFrozen) ...[
            const SizedBox(height: 12),
            _buildNotice(
              Icons.pause_circle_outline_rounded,
              'Your wallet is on hold. Campaign spend is paused while we review it.',
              AppColors.warning,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStat('Purchased', wallet.lifetimePurchased),
              ),
              Container(
                width: 1,
                height: 32,
                color: AppColors.borderPrimary.withValues(alpha: 0.5),
              ),
              Expanded(child: _buildStat('Spent', wallet.lifetimeSpent)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, int value) {
    return Column(
      children: [
        Text(
          '₹$value',
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: AppTypography.weightBold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTypography.labelSmall
              .copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildNotice(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(AdCreditTransaction txn) {
    final isCredit = txn.isCredit;
    final color = isCredit ? AppColors.success : AppColors.textPrimary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfacePrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderPrimary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isCredit ? AppColors.success : AppColors.primary)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isCredit
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              size: 16,
              color: isCredit ? AppColors.success : AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  txn.label,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(txn.createdAt),
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${txn.signedAmount} credits',
                style: AppTypography.bodyMedium.copyWith(
                  color: color,
                  fontWeight: AppTypography.weightBold,
                ),
              ),
              if (txn.balanceAfter != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Bal ₹${txn.balanceAfter}',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: color.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/${local.year} · $h:$min';
  }
}
