import 'package:flutter/material.dart';

import '../design/app_tokens.dart';

/// 탐색의 글 상세 화면에서 사용하는 기본 배경입니다.
class AppArticleBackground extends StatelessWidget {
  const AppArticleBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: AppColors.surfaceCanvas),
    child: child,
  );
}
