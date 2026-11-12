import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_layout.dart';

import '../support/app_test_harness.dart';

void main() {
  testWidgets('a long page of options keeps 다음 on screen without scrolling', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      OnboardingStepScaffold(
        title: '기억에 남거나 아쉬웠던 향이 있나요?',
        description: '한 번 터치 좋아요',
        childrenBuilder: (context, layout) => <Widget>[
          for (var i = 0; i < 30; i++)
            SizedBox(height: 56, child: Text('선택지 $i')),
        ],
        primaryAction: OnboardingStepAction(label: '다음', onPressed: () {}),
      ),
      viewport: const Size(390, 844),
    );

    final next = tester.getRect(find.text('다음'));
    expect(next.bottom, lessThanOrEqualTo(844));
    expect(find.text('선택지 29').hitTestable(), findsNothing);
  });
}
