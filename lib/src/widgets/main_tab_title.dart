import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';

/// The name of a main tab at the top left of its page, in place of a header
/// bar, with the room under it down to the page's first part.
class MainTabTitle extends StatelessWidget {
  const MainTabTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: Semantics(
      header: true,
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.tabTitle,
      ),
    ),
  );
}
