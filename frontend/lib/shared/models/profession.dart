class Profession {
  final String id;
  final String label;
  final List<String> searchTerms;

  const Profession({
    required this.id,
    required this.label,
    this.searchTerms = const [],
  });

  factory Profession.fromJson(Map<String, dynamic> json) {
    return Profession(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      searchTerms: (json['searchTerms'] as List<dynamic>?)
              ?.map((term) => term.toString())
              .toList(growable: false) ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'searchTerms': searchTerms,
      };

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return label.toLowerCase().contains(normalized) ||
        searchTerms.any((term) => term.toLowerCase().contains(normalized));
  }
}

