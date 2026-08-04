/// Ad-credit wallet models.
///
/// 1 credit = ₹1 of ad spend. The backend keeps balances as whole integers, so
/// these are `int` — a double here would invite a UI that shows ₹599.99 for a
/// balance the server considers 600.
class AdWallet {
  final int balance;
  final String currency;
  final String status;
  final int lifetimePurchased;
  final int lifetimeSpent;

  const AdWallet({
    required this.balance,
    this.currency = 'INR',
    this.status = 'active',
    this.lifetimePurchased = 0,
    this.lifetimeSpent = 0,
  });

  /// A wallet the user has never funded. Used as the pre-load placeholder so
  /// the UI never has to render a null balance.
  static const AdWallet empty = AdWallet(balance: 0);

  bool get isFrozen => status == 'frozen';

  factory AdWallet.fromJson(Map<String, dynamic> json) {
    return AdWallet(
      balance: _asInt(json['balance']),
      currency: json['currency'] as String? ?? 'INR',
      status: json['status'] as String? ?? 'active',
      lifetimePurchased: _asInt(json['lifetimePurchased']),
      lifetimeSpent: _asInt(json['lifetimeSpent']),
    );
  }

  /// Tolerates the server sending a number as int, double, or string — a
  /// balance that fails to parse would otherwise crash the create-ad screen.
  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.floor();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// The advertiser does not have enough credits for the budget they chose.
///
/// Typed rather than a generic failure because it is the one ad-creation error
/// the user can actually fix, and fixing it needs a number: how many more
/// credits to buy. The server computes [shortfall] so the client never has to.
class InsufficientCreditsException implements Exception {
  final int required;
  final int available;
  final int shortfall;

  const InsufficientCreditsException({
    required this.required,
    required this.available,
    required this.shortfall,
  });

  factory InsufficientCreditsException.fromJson(Map<String, dynamic> json) {
    final required = AdWallet._asInt(json['required']);
    final available = AdWallet._asInt(json['available']);
    return InsufficientCreditsException(
      required: required,
      available: available,
      // Recomputed if the server omitted it, so the UI always has a number.
      shortfall: json['shortfall'] == null
          ? (required - available).clamp(0, required)
          : AdWallet._asInt(json['shortfall']),
    );
  }

  @override
  String toString() =>
      'InsufficientCreditsException(need $required, have $available)';
}

/// One row of the append-only credit ledger.
class AdCreditTransaction {
  final String id;
  final String type;
  final int amount;
  final String source;
  final int? balanceAfter;
  final String? reason;
  final String? campaignId;
  final DateTime? createdAt;

  const AdCreditTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.source,
    this.balanceAfter,
    this.reason,
    this.campaignId,
    this.createdAt,
  });

  /// Whether this row added credits. The backend stores `amount` unsigned and
  /// implies direction from `type`, so the sign is derived here too — never
  /// read from the number.
  bool get isCredit => type != 'spend' && type != 'reversal';

  String get signedAmount => '${isCredit ? '+' : '-'}$amount';

  String get label {
    switch (type) {
      case 'purchase':
        return 'Credits purchased';
      case 'spend':
        return 'Campaign spend';
      case 'refund':
        return 'Refund';
      case 'grant':
        return 'Credits added';
      case 'reversal':
        return 'Purchase reversed';
      default:
        return type;
    }
  }

  factory AdCreditTransaction.fromJson(Map<String, dynamic> json) {
    return AdCreditTransaction(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      type: json['type'] as String? ?? 'unknown',
      amount: AdWallet._asInt(json['amount']),
      source: json['source'] as String? ?? 'system',
      balanceAfter:
          json['balanceAfter'] == null ? null : AdWallet._asInt(json['balanceAfter']),
      reason: json['reason'] as String?,
      campaignId: json['campaignId']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

/// A page of ledger rows plus enough state to drive infinite scroll.
class AdCreditTransactionPage {
  final List<AdCreditTransaction> items;
  final int page;
  final int totalPages;
  final bool hasMore;

  const AdCreditTransactionPage({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.hasMore,
  });

  static const AdCreditTransactionPage empty = AdCreditTransactionPage(
    items: [],
    page: 1,
    totalPages: 1,
    hasMore: false,
  );

  factory AdCreditTransactionPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['transactions'] as List<dynamic>? ?? const [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? const {};

    return AdCreditTransactionPage(
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(AdCreditTransaction.fromJson)
          .toList(),
      page: AdWallet._asInt(pagination['page'] ?? 1),
      totalPages: AdWallet._asInt(pagination['totalPages'] ?? 1),
      hasMore: pagination['hasMore'] == true,
    );
  }
}
