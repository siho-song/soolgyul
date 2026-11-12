import 'package:flutter/material.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../data/drink_interest_catalog.dart';
import '../data/profile_setup_draft.dart';
import 'widgets/drink_select_card.dart';
import '../../../widgets/app_sheet.dart';

/// Stores the chosen drink interests and reports whether the save went
/// through.
typedef DrinkInterestSaver = Future<bool> Function(Set<DrinkInterest> chosen);

/// Opens 관심 주종 설정 over My Page. It closes only after a save went through;
/// a failed save keeps it open with the message over the button.
Future<void> showDrinkInterestSheet(
  BuildContext context, {
  required Set<DrinkInterest> initialSelection,
  required DrinkInterestSaver onSave,
}) => showAppSheet<void>(
  context: context,
  builder: (context) =>
      DrinkInterestSheet(initialSelection: initialSelection, onSave: onSave),
);

class DrinkInterestSheet extends StatefulWidget {
  const DrinkInterestSheet({
    required this.initialSelection,
    required this.onSave,
    super.key,
  });

  final Set<DrinkInterest> initialSelection;
  final DrinkInterestSaver onSave;

  @override
  State<DrinkInterestSheet> createState() => _DrinkInterestSheetState();
}

class _DrinkInterestSheetState extends State<DrinkInterestSheet> {
  late final Set<DrinkInterest> _selected = Set<DrinkInterest>.of(
    widget.initialSelection,
  );
  bool _saving = false;
  bool _saveFailed = false;

  void _toggle(DrinkInterest interest) => setState(() {
    _saveFailed = false;
    if (!_selected.remove(interest)) _selected.add(interest);
  });

  Future<void> _save() async {
    if (_selected.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final saved = await widget.onSave(
      Set<DrinkInterest>.unmodifiable(_selected),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _saveFailed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final cardHeight = 56 + ((textScale - 1) * 32);
    return SingleChildScrollView(
      padding: appSheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AppSheetHeading(
            title: '관심 주종 설정',
            description: '관심 있는 주종을 선택해 주세요.\n내 취향에 맞는 이야기와 추천을 먼저 보여드릴게요.',
          ),
          const SizedBox(height: AppSpacing.lg),
          GridView.builder(
            key: const ValueKey<String>('profile-drink-grid'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: drinkInterestOptions.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: cardHeight,
            ),
            itemBuilder: (context, index) {
              final option = drinkInterestOptions[index];
              return DrinkSelectCard(
                option: option,
                selected: _selected.contains(option.value),
                onTap: () => _toggle(option.value),
              );
            },
          ),
          if (_saveFailed) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              '관심 주종을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.',
              key: const ValueKey<String>('profile-drink-feedback'),
              style: AppTextStyles.body.copyWith(
                color: AppColors.actionPrimary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          AppButton(
            key: const ValueKey<String>('profile-drink-complete'),
            label: '저장',
            onPressed: _selected.isEmpty || _saving ? null : _save,
            isLoading: _saving,
            variant: AppButtonVariant.accent,
            size: AppButtonSize.sheet,
          ),
        ],
      ),
    );
  }
}
