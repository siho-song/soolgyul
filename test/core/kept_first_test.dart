import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/async_shown.dart';
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

  test('after a sign-out, a load that fails shows nothing of the last '
      'account, however often it is tried again', () async {
    start();
    _Words.server.complete("account A's letters");
    await container.read(_words.future);
    final shown = <String?>[];
    container.listen(
      _words,
      (_, next) => shown.add(shownValue(next)),
      fireImmediately: true,
    );
    expect(shown.last, "account A's letters");

    // Signed out, and the next account's first load fails.
    _Words.server = Completer<String>();
    container.invalidate(_words, asReload: true);
    await _settle();
    _Words.server.completeError(StateError('offline'));
    await _settle();
    // Riverpod still carries the earlier value beside the error.
    expect(container.read(_words).hasError, isTrue);
    expect(container.read(_words).value, "account A's letters");
    expect(shown.last, isNull);

    // Tried again, as a pull-to-refresh does, and it fails again.
    _Words.server = Completer<String>();
    container.invalidate(_words);
    await _settle();
    expect(shown.last, isNull);
    _Words.server.completeError(StateError('still offline'));
    await _settle();
    expect(shown.last, isNull);

    // The next account's own data shows once it arrives.
    _Words.server = Completer<String>();
    container.invalidate(_words);
    await _settle();
    _Words.server.complete("account B's letters");
    await _settle();
    expect(shown.last, "account B's letters");
  });

  test('after a sign-out, the next account sees its own kept copy even '
      'when the server cannot be reached', () async {
    start();
    _Words.server.complete("account A's letters");
    await container.read(_words.future);

    _Words.onPhone = "account B's kept letters";
    _Words.server = Completer<String>();
    container.invalidate(_words, asReload: true);
    container.listen(_words, (_, _) {});
    await _settle();
    _Words.server.completeError(StateError('offline'));
    await _settle();
    expect(shownValue(container.read(_words)), "account B's kept letters");
  });
}
