import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/shared/models/profession.dart';

void main() {
  const profession = Profession(
    id: 'software_engineer',
    label: 'Software Engineer',
    searchTerms: ['developer', 'programmer', 'coding'],
  );

  test('matches the visible profession label', () {
    expect(profession.matches('software'), isTrue);
    expect(profession.matches('ENGINEER'), isTrue);
  });

  test('matches picker-only aliases', () {
    expect(profession.matches('developer'), isTrue);
    expect(profession.matches('coding'), isTrue);
    expect(profession.matches('doctor'), isFalse);
  });

  test('round-trips through JSON', () {
    final decoded = Profession.fromJson(profession.toJson());
    expect(decoded.id, profession.id);
    expect(decoded.label, profession.label);
    expect(decoded.searchTerms, profession.searchTerms);
  });
}
