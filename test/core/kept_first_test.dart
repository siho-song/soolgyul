import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/kept_first.dart';

class _Words extends KeptFirstNotifier<String> {
  static String? onPhone;
  static Completer<String> server = Completer<String>();
  static int keptReads = 0;

  @override
  Future<String?> kept() async {
    keptReads += 1;
    return onPhone;
  }

  @override
  Future<String> load() => server.future;
}

final _words = AsyncNotifierProvider<_Words, String>(_Words.new);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late ProviderContainer container;
  late List<String?> seen;

  /// Starts watching with [onPhone] as the copy kept from last time.
  void start({String? onPhone}) {
    _Words.onPhone = onPhone;
    _Words.server = Completer<String>();
    _Words.keptReads = 0;
    container = ProviderContainer();
    addTearDown(container.dispose);
    seen = <String?>[];
    container.listen(_words, (_, next) => seen.add(next.value));
  }

  test(
    'the kept copy shows first, then the server answer replaces it',
    () async {
      start(onPhone: 'from last time');

      // The first thing there is to show is what the first load completes with.
      expect(await container.read(_words.future), 'from last time');

      _Words.server.complete('from the server');
      await _settle();
      expect(container.read(_words).value, 'from the server');
      expect(seen.whereType<String>().toList(), <String>[
        'from last time',
        'from the server',
      ]);
    },
  );

  test('without a kept copy it loads as before', () async {
    start();
    await _settle();
    expect(container.read(_words).isLoading, isTrue);
    expect(container.read(_words).hasValue, isFalse);

    _Words.server.complete('from the server');
    expect(await container.read(_words.future), 'from the server');
  });

  test('a failed load keeps the kept copy on screen', () async {
    start(onPhone: 'from last time');
    await _settle();

    _Words.server.completeError(StateError('offline'));
    await _settle();

    final state = container.read(_words);
    expect(state.hasError, isTrue);
    expect(state.value, 'from last time');
  });

  test(
    'a reload after a change waits for the server and skips the copy',
    () async {
      start(onPhone: 'from last time');
      await _settle();
      _Words.server.complete('first answer');
      await _settle();
      expect(container.read(_words).value, 'first answer');

      _Words.server = Completer<String>();
      container.invalidate(_words);
      final reload = container.read(_words.future);
      await _settle();
      expect(
        container.read(_words).value,
        'first answer',
        reason: 'stays shown',
      );
      _Words.server.complete('second answer');

      expect(await reload, 'second answer');
      expect(_Words.keptReads, 1);
      expect(seen.whereType<String>().toSet(), <String>{
        'from last time',
        'first answer',
        'second answer',
      });
      expect(seen.last, 'second answer');
    },
  );
}
