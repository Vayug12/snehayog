import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vayug/features/ads/data/services/wallet_service.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Buying ad credits through Google Play, via RevenueCat.
///
/// **The client never credits the wallet.** A purchase result in this process
/// is a claim, not a fact — it can be replayed, patched, or faked on a rooted
/// device. Credits are written by the server when RevenueCat's webhook arrives,
/// verified against the store. All this class does after a successful purchase
/// is *wait* for that to land, by polling the balance.
///
/// That is why [purchase] can return [TopUpOutcome.pending]: Play may still be
/// processing the payment, or RevenueCat may be delivering its server event.
/// In either case the UI waits for the authoritative wallet balance.
enum TopUpOutcome {
  /// Paid, and the balance has already gone up.
  credited,

  /// Play is processing, or payment succeeded but credits have not landed yet.
  pending,

  /// The user backed out. Not an error.
  cancelled,

  /// Purchases are not available (no key built in, or the store said no).
  unavailable,

  /// Something went wrong. [TopUpResult.message] says what.
  failed,
}

class TopUpResult {
  final TopUpOutcome outcome;
  final String message;
  final int? newBalance;
  final int? balanceBefore;

  const TopUpResult(
    this.outcome,
    this.message, {
    this.newBalance,
    this.balanceBefore,
  });

  bool get isPaid =>
      outcome == TopUpOutcome.credited || outcome == TopUpOutcome.pending;
}

class AdCreditPurchaseService {
  static final AdCreditPurchaseService _instance =
      AdCreditPurchaseService._internal();
  factory AdCreditPurchaseService() => _instance;
  AdCreditPurchaseService._internal();

  final AuthService _authService = AuthService();
  final WalletService _walletService = WalletService();

  /// The RevenueCat Offering that carries the credit packages. Must match
  /// `AD_CREDITS_OFFERING_ID` on the server and the Offering id in the
  /// RevenueCat dashboard.
  static const String offeringId = 'ad_credits';
  static const Set<String> supportedProductIds = {
    'ad_credits_30',
    'ad_credits_100',
  };

  bool _configured = false;
  String? _loggedInAs;

  /// How long to wait for the webhook before calling it "pending".
  ///
  /// Backoff rather than a tight loop: the webhook usually lands in a second or
  /// two, and hammering the wallet endpoint while it does not helps nobody.
  static const List<Duration> _pollBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 4),
    Duration(seconds: 5),
    Duration(seconds: 5),
  ];

  bool get isAvailable => AppConfig.adCreditPurchasesEnabled;

  /// Configure the SDK and bind it to the signed-in account.
  ///
  /// `logIn` is not optional: it sets `app_user_id`, which is the only thing
  /// the webhook has to work out whose wallet to credit. An anonymous purchase
  /// is money we cannot attribute to anyone — a support ticket by construction.
  Future<bool> _ensureReady() async {
    if (!isAvailable) return false;

    final userData = await _authService.getUserData();
    final googleId = (userData?['googleId'] ?? userData?['id'])?.toString();
    if (googleId == null || googleId.isEmpty) {
      AppLogger.log(
          '⚠️ AdCreditPurchase: not signed in, cannot attribute a purchase');
      return false;
    }

    if (!_configured) {
      await Purchases.configure(
        PurchasesConfiguration(AppConfig.revenueCatAndroidKey)
          ..appUserID = googleId,
      );
      _configured = true;
      _loggedInAs = googleId;
      return true;
    }

    // Account switch on the same install — re-bind before purchasing, or the
    // credits land in the previous account's wallet.
    if (_loggedInAs != googleId) {
      await Purchases.logIn(googleId);
      _loggedInAs = googleId;
    }

    return true;
  }

  /// The credit packages on sale, cheapest first.
  ///
  /// Returns an empty list when purchases are unavailable, so callers can hide
  /// the top-up UI without special-casing an exception.
  Future<List<Package>> getPackages() async {
    try {
      if (!await _ensureReady()) return const [];

      final offerings = await Purchases.getOfferings();
      final offering = offerings.all[offeringId];

      if (offering == null) {
        AppLogger.log('⚠️ AdCreditPurchase: offering "$offeringId" not found');
        return const [];
      }

      final packages = offering.availablePackages
          .where((package) => supportedProductIds.contains(
                package.storeProduct.identifier.split(':').first,
              ))
          .toList()
        ..sort((a, b) => a.storeProduct.price.compareTo(b.storeProduct.price));
      return packages;
    } catch (e) {
      AppLogger.log('❌ AdCreditPurchase: could not load offerings: $e');
      return const [];
    }
  }

  /// Buy a package, then wait for the server to credit it.
  Future<TopUpResult> purchase(Package package) async {
    if (!await _ensureReady()) {
      return const TopUpResult(
        TopUpOutcome.unavailable,
        'Credit purchases are not available in this build.',
      );
    }

    final balanceBefore = await _currentBalance();

    try {
      await _walletService.recordPurchaseIntent(
        package.storeProduct.identifier,
      );
    } catch (e) {
      AppLogger.log('AdCreditPurchase: purchase intent failed: $e');
      return const TopUpResult(
        TopUpOutcome.failed,
        'Could not safely start this purchase. Check your connection and try again.',
      );
    }

    try {
      await Purchases.purchase(PurchaseParams.package(package));
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);

      switch (code) {
        case PurchasesErrorCode.purchaseCancelledError:
          return const TopUpResult(
              TopUpOutcome.cancelled, 'Purchase cancelled.');

        case PurchasesErrorCode.paymentPendingError:
          // Slow payment methods (UPI mandates, cash). The purchase completes
          // later and the webhook will credit it then.
          return TopUpResult(
            TopUpOutcome.pending,
            'Payment is still processing. Your credits will appear once it clears.',
            balanceBefore: balanceBefore,
          );

        case PurchasesErrorCode.productAlreadyPurchasedError:
          // Should not happen for consumables, but if the previous purchase was
          // never consumed the credits may simply be in flight.
          return TopUpResult(
            TopUpOutcome.pending,
            'This purchase is already being processed.',
            balanceBefore: balanceBefore,
          );

        case PurchasesErrorCode.purchaseNotAllowedError:
        case PurchasesErrorCode.storeProblemError:
          return const TopUpResult(
            TopUpOutcome.unavailable,
            'Google Play could not complete the purchase. Try again shortly.',
          );

        default:
          AppLogger.log(
              '❌ AdCreditPurchase: purchase failed ($code): ${e.message}');
          return TopUpResult(
            TopUpOutcome.failed,
            e.message ?? 'The purchase could not be completed.',
          );
      }
    } catch (e) {
      AppLogger.log('❌ AdCreditPurchase: unexpected purchase error: $e');
      return const TopUpResult(
        TopUpOutcome.failed,
        'The purchase could not be completed.',
      );
    }

    // If the webhook was delayed or dropped, ask RevenueCat from the backend.
    // This never trusts the client purchase result to mint credits.
    await _walletService.syncPurchases();

    // Paid. From here the only question is whether the webhook has landed —
    // never whether to credit, which is not this process's decision to make.
    final credited = await waitForCredit(balanceBefore);

    if (credited != null) {
      return TopUpResult(
        TopUpOutcome.credited,
        'Credits added to your wallet.',
        newBalance: credited,
        balanceBefore: balanceBefore,
      );
    }

    return TopUpResult(
      TopUpOutcome.pending,
      'Payment received. Your credits are on the way — this can take a minute.',
      balanceBefore: balanceBefore,
    );
  }

  Future<int?> _currentBalance() async {
    try {
      return (await _walletService.getBalance()).balance;
    } catch (e) {
      // A failed read here is not fatal: it only costs us the ability to detect
      // the increase, which downgrades "credited" to "pending".
      AppLogger.log('⚠️ AdCreditPurchase: balance read failed: $e');
      return null;
    }
  }

  /// Poll until the balance exceeds what it was before the purchase.
  ///
  /// Comparing against the prior balance rather than a target amount means this
  /// stays correct if the server credits a different number than the client
  /// expected — the server's product map is the authority on that.
  Future<int?> waitForCredit(
    int? balanceBefore, {
    List<Duration> backoff = _pollBackoff,
  }) async {
    if (balanceBefore == null) return null;

    for (final delay in backoff) {
      await Future<void>.delayed(delay);

      final balance = await _currentBalance();
      if (balance != null && balance > balanceBefore) return balance;
    }

    return null;
  }
}

final adCreditPurchaseServiceProvider =
    Provider<AdCreditPurchaseService>((ref) => AdCreditPurchaseService());

/// Packages on sale. Empty when purchases are unavailable.
final adCreditPackagesProvider =
    FutureProvider.autoDispose<List<Package>>((ref) async {
  return ref.watch(adCreditPurchaseServiceProvider).getPackages();
});
