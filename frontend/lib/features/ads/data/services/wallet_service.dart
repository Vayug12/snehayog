import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/features/ads/data/wallet_model.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Thrown for any wallet call that did not return a usable balance.
///
/// Typed rather than a bare `Exception` so the UI can distinguish "not signed
/// in" from "server said no" without string-matching a message.
class WalletException implements Exception {
  final String message;
  final int? statusCode;

  const WalletException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'WalletException($statusCode): $message';
}

/// Read-only client for the ad-credit wallet.
///
/// Deliberately uncached. The wallet endpoints are served `no-store` precisely
/// because a balance is money; caching it locally would reintroduce the stale
/// read the server header exists to prevent. Every call is a fresh read.
class WalletService {
  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;
  WalletService._internal();

  final AuthService _authService = AuthService();

  static const Duration _timeout = Duration(seconds: 15);

  Future<Map<String, String>> _authHeaders() async {
    final userData = await _authService.getUserData();
    final token = userData?['token'];

    if (token == null || (token is String && token.isEmpty)) {
      throw const WalletException('Not signed in', statusCode: 401);
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Current credit balance. Creates the wallet server-side on first read, so
  /// a brand-new user gets a zero balance rather than a 404.
  Future<AdWallet> getBalance() async {
    try {
      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      final headers = await _authHeaders();

      final response = await httpClientService.get(
        Uri.parse('$baseUrl/api/ads/wallet'),
        headers: headers,
        timeout: _timeout,
      );

      if (response.statusCode != 200) {
        throw WalletException(
          _errorFrom(response.body, 'Failed to load wallet'),
          statusCode: response.statusCode,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final wallet = json['wallet'];
      if (wallet is! Map<String, dynamic>) {
        throw const WalletException('Malformed wallet response');
      }

      return AdWallet.fromJson(wallet);
    } on WalletException {
      rethrow;
    } catch (e) {
      AppLogger.log('❌ WalletService: getBalance failed: $e');
      throw WalletException('Could not reach the wallet service: $e');
    }
  }

  Future<void> recordPurchaseIntent(String productId) async {
    try {
      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      final headers = await _authHeaders();
      final response = await httpClientService.post(
        Uri.parse('$baseUrl/api/ads/wallet/purchase-intents'),
        headers: headers,
        body: jsonEncode({'productId': productId}),
        timeout: _timeout,
      );

      if (response.statusCode != 201) {
        throw WalletException(
          _errorFrom(response.body, 'Could not prepare purchase recovery'),
          statusCode: response.statusCode,
        );
      }
    } on WalletException {
      rethrow;
    } catch (e) {
      throw WalletException('Could not prepare purchase recovery: $e');
    }
  }

  Future<AdWallet?> syncPurchases() async {
    try {
      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      final headers = await _authHeaders();
      final response = await httpClientService.post(
        Uri.parse('$baseUrl/api/ads/wallet/sync-purchases'),
        headers: headers,
        body: '{}',
        timeout: _timeout,
      );

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final wallet = json['wallet'];
      return wallet is Map<String, dynamic> ? AdWallet.fromJson(wallet) : null;
    } catch (e) {
      AppLogger.log('WalletService: purchase sync unavailable: $e');
      return null;
    }
  }

  /// One page of ledger history, newest first.
  ///
  /// `limit` is capped at 100 to match the server's pagination validator —
  /// sending more is a guaranteed 400.
  Future<AdCreditTransactionPage> getTransactions({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      final headers = await _authHeaders();

      final uri = Uri.parse('$baseUrl/api/ads/wallet/transactions').replace(
        queryParameters: {
          'page': '${page < 1 ? 1 : page}',
          'limit': '${limit.clamp(1, 100)}',
        },
      );

      final response = await httpClientService.get(
        uri,
        headers: headers,
        timeout: _timeout,
      );

      if (response.statusCode != 200) {
        throw WalletException(
          _errorFrom(response.body, 'Failed to load transactions'),
          statusCode: response.statusCode,
        );
      }

      return AdCreditTransactionPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on WalletException {
      rethrow;
    } catch (e) {
      AppLogger.log('❌ WalletService: getTransactions failed: $e');
      throw WalletException('Could not load transactions: $e');
    }
  }

  /// Pull a readable message out of an error body without leaking a raw HTML
  /// error page into a SnackBar.
  String _errorFrom(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // Not JSON — fall through to the generic message.
    }
    return fallback;
  }
}

final walletServiceProvider = Provider<WalletService>((ref) => WalletService());

/// Caller's balance. `autoDispose` so leaving the create-ad screen drops it and
/// the next visit re-reads rather than showing a balance from an hour ago.
final adWalletProvider = FutureProvider.autoDispose<AdWallet>((ref) async {
  return ref.watch(walletServiceProvider).getBalance();
});

/// First page of ledger history. Deeper pages are fetched imperatively by the
/// transactions screen so scrolling does not re-run this provider.
final adWalletTransactionsProvider =
    FutureProvider.autoDispose<AdCreditTransactionPage>((ref) async {
  return ref.watch(walletServiceProvider).getTransactions();
});
