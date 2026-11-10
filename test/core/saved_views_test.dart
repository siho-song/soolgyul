import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/saved_views.dart';

void main() {
  late Directory folder;
  String? account;
  var now = DateTime(2026, 11, 11, 9);

  SavedViews views() => SavedViewFiles(
    accountId: () => account,
    folder: () async => folder,
    now: () => now,
  );

  setUp(() {
    folder = Directory.systemTemp.createTempSync('saved_views_test');
    addTearDown(() {
      if (folder.existsSync()) folder.deleteSync(recursive: true);
    });
    account = 'member-a';
    now = DateTime.now();
  });

  test('a copy is read back as it was written', () async {
    await views().write('letters', <String, Object?>{
      'record_count': 3,
      'axes': <String, Object?>{'aroma': 'F'},
      'name': '발베니 더블우드 12년',
    });

    expect(await views().read('letters'), <String, Object?>{
      'record_count': 3,
      'axes': <String, Object?>{'aroma': 'F'},
      'name': '발베니 더블우드 12년',
    });
    expect(await views().read('guides'), isNull);
  });

  test('one account never reads another account\'s copy', () async {
    await views().write('letters', <String>['of member a']);

    account = 'member-b';
    expect(await views().read('letters'), isNull);
    await views().write('letters', <String>['of member b']);

    account = 'member-a';
    expect(await views().read('letters'), <String>['of member a']);
  });

  test('signed out, nothing is read or kept', () async {
    account = null;
    await views().write('letters', <String>['nobody']);

    expect(await views().read('letters'), isNull);
    expect(folder.listSync(), isEmpty);
  });

  test('clearing forgets every account', () async {
    await views().write('letters', <String>['a']);
    account = 'member-b';
    await views().write('letters', <String>['b']);

    await views().clear();

    expect(await views().read('letters'), isNull);
    account = 'member-a';
    expect(await views().read('letters'), isNull);
  });

  test('a copy past its time is not used', () async {
    await views().write('letters', <String>['old']);

    now = DateTime.now().add(const Duration(days: 31));
    expect(await views().read('letters'), isNull);
  });

  test('only the newest copies of a kind stay', () async {
    for (var card = 1; card <= 5; card++) {
      await views().write('card-$card', <String, Object?>{
        'n': card,
      }, keepNewest: 3);
      // File times have one-second steps on some systems.
      File(
        '${folder.path}/member-a/card-$card.json',
      ).setLastModifiedSync(DateTime(2026, 11, 1, 0, card));
    }
    await views().write('letters', <String>['stays']);
    await views().write('card-6', <String, Object?>{'n': 6}, keepNewest: 3);

    expect(await views().read('card-1'), isNull);
    expect(await views().read('card-3'), isNull);
    expect(await views().read('card-5'), isNotNull);
    expect(await views().read('card-6'), isNotNull);
    expect(await views().read('letters'), <String>['stays']);
  });

  test('a copy that cannot be read is no copy', () async {
    await views().write('letters', <String>['fine']);
    File('${folder.path}/member-a/letters.json').writeAsStringSync('{broken');

    expect(await views().read('letters'), isNull);
  });

  test('a removed copy is gone', () async {
    await views().write('card-1', <String>['x']);
    await views().remove('card-1');

    expect(await views().read('card-1'), isNull);
  });
}
