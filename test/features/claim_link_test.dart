import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_card/data/claim_link.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';

void main() {
  const ticket = TasteCardPendingConversion(
    anonymousSessionId: 'anon-session',
    resultId: '20000000-0000-4000-8000-000000000001',
    snapshotRef: 'snapshot/ref v3',
    conversionToken: 'a.b-c_d',
  );

  test('the link carries the whole ticket and parses back to it', () {
    final link = TasteCardClaimLink.build('https://soolgyul.com', ticket);
    expect(link.host, 'soolgyul.com');
    expect(link.path, '/claim');
    final parsed = TasteCardClaimLink.parse(link)!;
    expect(parsed.anonymousSessionId, ticket.anonymousSessionId);
    expect(parsed.resultId, ticket.resultId);
    expect(parsed.snapshotRef, ticket.snapshotRef);
    expect(parsed.conversionToken, ticket.conversionToken);
  });

  test('other links and incomplete tickets are not a claim', () {
    expect(
      TasteCardClaimLink.parse(Uri.parse('https://soolgyul.com/')),
      isNull,
    );
    expect(
      TasteCardClaimLink.parse(Uri.parse('https://soolgyul.com/claim?s=x&r=y')),
      isNull,
    );
    expect(TasteCardClaimLink.parseInstallReferrer(null), isNull);
    expect(TasteCardClaimLink.parseInstallReferrer('utm_source=play'), isNull);
  });

  test('the Play install referrer is the link\'s query', () {
    final query = TasteCardClaimLink.build(
      'https://soolgyul.com',
      ticket,
    ).query;
    final parsed = TasteCardClaimLink.parseInstallReferrer(query)!;
    expect(parsed.resultId, ticket.resultId);
    expect(parsed.snapshotRef, ticket.snapshotRef);
    expect(parsed.conversionToken, ticket.conversionToken);
  });
}
