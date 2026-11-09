import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/async_shown.dart';

void main() {
  test('a reload after a change keeps the old data on screen; one after '
      'a sign-out does not', () async {
    var next = Completer<String>();
    final data = FutureProvider<String>((ref) => next.future);
    final container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);
    final shown = <String?>[];
    container.listen(
      data,
      (_, value) => shown.add(shownValue(value)),
      fireImmediately: true,
    );

    next.complete('account A');
    await container.read(data.future);
    expect(shown.last, 'account A');

    // A card was saved: the old letters stay until the new arrive.
    next = Completer<String>();
    container.invalidate(data);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(data).isLoading, isTrue);
    expect(shown.last, 'account A');
    next.complete('account A, one card more');
    await container.read(data.future);
    expect(shown.last, 'account A, one card more');

    // Signed out: nothing of the last account shows while the next loads.
    next = Completer<String>();
    container.invalidate(data, asReload: true);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(data).isLoading, isTrue);
    expect(shown.last, isNull);
    next.complete('account B');
    await container.read(data.future);
    expect(shown.last, 'account B');
  });

  test('a sign-out reload hides the old data even when nothing watched it '
      'at the time', () async {
    var next = Completer<String>()..complete('account A');
    final data = FutureProvider<String>((ref) => next.future);
    final container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);
    final first = container.listen(data, (_, _) {});
    await container.read(data.future);
    first.close();

    next = Completer<String>();
    container.invalidate(data, asReload: true);
    final shown = <String?>[];
    container.listen(
      data,
      (_, value) => shown.add(shownValue(value)),
      fireImmediately: true,
    );
    expect(shown.single, isNull);
  });
}
