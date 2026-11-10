import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_card/data/claim_link.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';

void main() {
  const site = 'https://soolgyul.com';
  const ticket = TasteCardPendingConversion(
    anonymousSessionId: 'anon-session',
    resultId: '20000000-0000-4000-8000-000000000001',
    snapshotRef: 'snapshot/ref v3',
    conversionToken: 'a.b-c_d',
  );

  test('the link carries the whole ticket and parses back to it', () {
    final link = TasteCardClaimLink.build(site, ticket);
    expect(link.host, 'soolgyul.com');
    expect(link.path, '/claim');
    // Nothing of the ticket is in the part a server sees.
    expect(link.query, isEmpty);
    final parsed = TasteCardClaimLink.parse(link, baseUrl: site)!;
    expect(parsed.anonymousSessionId, ticket.anonymousSessionId);
    expect(parsed.resultId, ticket.resultId);
    expect(parsed.snapshotRef, ticket.snapshotRef);
    expect(parsed.conversionToken, ticket.conversionToken);
  });

  test('other links and incomplete tickets are not a claim', () {
    TasteCardPendingConversion? parse(String link) =>
        TasteCardClaimLink.parse(Uri.parse(link), baseUrl: site);
    expect(parse('https://soolgyul.com/'), isNull);
    expect(parse('https://soolgyul.com/claim#s=x&r=y'), isNull);
    expect(TasteCardClaimLink.parseInstallReferrer(null), isNull);
    expect(TasteCardClaimLink.parseInstallReferrer('utm_source=play'), isNull);
  });

  test('a link is a claim only on the intro site', () {
    final ticketPart = TasteCardClaimLink.build(site, ticket).fragment;
    TasteCardPendingConversion? parse(String link) =>
        TasteCardClaimLink.parse(Uri.parse(link), baseUrl: site);
    // The site answers on www and with a trailing slash.
    expect(parse('https://www.soolgyul.com/claim/#$ticketPart'), isNotNull);
    // Any page can write a link with the app's scheme or another host.
    expect(parse('soolgyul://x/claim#$ticketPart'), isNull);
    expect(parse('https://evil.example/claim#$ticketPart'), isNull);
    expect(parse('http://soolgyul.com/claim#$ticketPart'), isNull);
    // The ticket is read after the "#" only.
    expect(parse('https://soolgyul.com/claim?$ticketPart'), isNull);
  });

  test('the Play install referrer is the link\'s part after the #', () {
    final query = TasteCardClaimLink.build(site, ticket).fragment;
    final parsed = TasteCardClaimLink.parseInstallReferrer(query)!;
    expect(parsed.resultId, ticket.resultId);
    expect(parsed.snapshotRef, ticket.snapshotRef);
    expect(parsed.conversionToken, ticket.conversionToken);
  });
}
