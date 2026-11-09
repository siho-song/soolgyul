import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary_store.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';

void main() {
  testWidgets(
    'shows pending placeholders then server counts without photo editor',
    (tester) async {
      final pending = Completer<ProfileSummary>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ProfileScreen(
              onNavigate: (_) {},
              onSaveNickname: (_) async => true,
              onSaveInterests: (_) async => true,
              summaryStore: ProfileSummaryStore(() => pending.future),
            ),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('—'), findsNWidgets(2));
      pending.complete(
        const ProfileSummary(
          cardCount: 37,
          savedArticleCount: 12,
          likedCardCount: 8,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('37'), findsNothing);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(find.textContaining('프로필 사진'), findsNothing);
    },
  );

  testWidgets('failed query does not show false zero and can retry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ProfileScreen(
            onNavigate: (_) {},
            onSaveNickname: (_) async => true,
            onSaveInterests: (_) async => true,
            summaryStore: ProfileSummaryStore(() async {
              if (++attempts == 1) throw StateError('offline');
              return const ProfileSummary(
                cardCount: 0,
                savedArticleCount: 0,
                likedCardCount: 0,
              );
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('—'), findsNWidgets(2));
    final retry = find.text('내 기록을 불러오지 못했어요. 다시 시도');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('0'), findsNWidgets(2));
    expect(retry, findsNothing);
  });

  testWidgets('opening My Page again shows the kept counts without asking', (
    tester,
  ) async {
    var loads = 0;
    final store = ProfileSummaryStore(() async {
      loads++;
      return ProfileSummary(
        cardCount: 3,
        savedArticleCount: loads,
        likedCardCount: 5,
      );
    });
    addTearDown(store.dispose);
    Widget page() => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ProfileScreen(
          onNavigate: (_) {},
          onSaveNickname: (_) async => true,
          onSaveInterests: (_) async => true,
          summaryStore: store,
        ),
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(loads, 1);

    // Leaving and coming back reads the store; nothing is fetched again.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    expect(find.text('—'), findsNothing);
    await tester.pumpAndSettle();
    expect(loads, 1);

    // A change elsewhere reloads, and the old count stays until the new one.
    store.refresh();
    await tester.pump();
    expect(find.text('—'), findsNothing);
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('2'), findsOneWidget);
  });
}
