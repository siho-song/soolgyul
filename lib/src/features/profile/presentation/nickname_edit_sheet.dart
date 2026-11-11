import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/app_sheet.dart';

/// Stores a nickname and reports whether the save went through.
typedef NicknameSaver = Future<bool> Function(String nickname);

/// Opens the nickname sheet over My Page. It closes only after a save went
/// through; a failed save keeps it open with the message under the field.
Future<void> showNicknameEditSheet(
  BuildContext context, {
  required String initialNickname,
  required NicknameSaver onSave,
}) => showAppSheet<void>(
  context: context,
  builder: (context) =>
      NicknameEditSheet(initialNickname: initialNickname, onSave: onSave),
);

class NicknameEditSheet extends StatefulWidget {
  const NicknameEditSheet({
    required this.initialNickname,
    required this.onSave,
    super.key,
  });

  final String initialNickname;
  final NicknameSaver onSave;

  @override
  State<NicknameEditSheet> createState() => _NicknameEditSheetState();
}

class _NicknameEditSheetState extends State<NicknameEditSheet> {
  static const _nicknameMinLength = 2;
  static const _nicknameMaxLength = 12;
  static final _nicknamePattern = RegExp(r'^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ]+$');

  late final _controller = TextEditingController(text: widget.initialNickname);
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _nicknameLength => _controller.text.runes.length;

  String? get _nicknameError {
    final nickname = _controller.text;
    if (nickname.isEmpty) {
      return '닉네임을 입력해 주세요.';
    }
    if (nickname.contains(RegExp(r'\s'))) {
      return '띄어쓰기 없이 입력해 주세요.';
    }
    if (!_nicknamePattern.hasMatch(nickname)) {
      return '한글, 영문, 숫자만 사용할 수 있어요.';
    }
    if (_nicknameLength < _nicknameMinLength) {
      return '2자 이상으로 입력해 주세요.';
    }
    if (_nicknameLength > _nicknameMaxLength) {
      return '12자 이내로 입력해 주세요.';
    }
    return null;
  }

  String? get _feedbackError =>
      _saveFailed ? '저장하지 못했어요. 잠시 후 다시 시도해 주세요.' : _nicknameError;

  bool get _canSave => _nicknameError == null && !_saving;

  void _handleChanged(String value) => setState(() => _saveFailed = false);

  void _clear() {
    _controller.clear();
    setState(() => _saveFailed = false);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    final saved = await widget.onSave(_controller.text);
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
    final error = _feedbackError;
    return Padding(
      padding: appSheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AppSheetHeading(
            title: '닉네임 수정',
            description: '술결에서 사용할 닉네임을 설정해 보세요.',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            key: const ValueKey<String>('profile-nickname-field'),
            controller: _controller,
            autofocus: true,
            hintText: '닉네임을 입력해 주세요',
            maxLength: _nicknameMaxLength,
            size: AppTextFieldSize.large,
            hasError: _saveFailed,
            textInputAction: TextInputAction.done,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(_nicknameMaxLength),
            ],
            onChanged: _handleChanged,
            onClear: _controller.text.isEmpty ? null : _clear,
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  error ?? '사용 가능한 닉네임이에요.',
                  key: const ValueKey<String>('profile-nickname-feedback'),
                  style: AppTextStyles.body.copyWith(
                    color: error == null
                        ? AppColors.preferencePrimary
                        : AppColors.actionPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '$_nicknameLength / $_nicknameMaxLength',
                key: const ValueKey<String>('profile-nickname-count'),
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppButton(
            key: const ValueKey<String>('profile-save-button'),
            label: '저장',
            onPressed: _canSave ? _save : null,
            isLoading: _saving,
            variant: AppButtonVariant.accent,
            size: AppButtonSize.prominent,
          ),
        ],
      ),
    );
  }
}
