import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_input_popup.dart';
import '../../../widgets/app_snack_bar.dart';
import '../../../widgets/app_text_field.dart';
import '../data/nickname_rule.dart';

/// Saves the nickname: true once saved. A save that failed gives false, or
/// throws what it failed with so the popup can say why.
typedef NicknameSaver = Future<bool> Function(String nickname);

/// Opens the nickname popup over 내 정보, just over the keyboard. 저장
/// closes it only after the save went through; a failed save keeps it open
/// with the message under the field. 취소 closes it as it is.
Future<void> showNicknameEditPopup(
  BuildContext context, {
  required String initialNickname,
  required NicknameSaver onSave,
}) => showAppInputPopup<void>(
  context: context,
  builder: (context) =>
      NicknameEditPopup(initialNickname: initialNickname, onSave: onSave),
);

class NicknameEditPopup extends StatefulWidget {
  const NicknameEditPopup({
    required this.initialNickname,
    required this.onSave,
    super.key,
  });

  final String initialNickname;
  final NicknameSaver onSave;

  @override
  State<NicknameEditPopup> createState() => _NicknameEditPopupState();
}

class _NicknameEditPopupState extends State<NicknameEditPopup> {
  static const _nicknameMinLength = 2;
  static const _nicknameMaxLength = 12;

  late final _controller = TextEditingController(text: widget.initialNickname);
  bool _saving = false;
  static const _saveFailure = '저장하지 못했어요. 잠시 후 다시 시도해 주세요.';

  bool _saveFailed = false;

  /// What the save failed with, when it said.
  Object? _saveError;

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
    // The field lets in neither a space nor a mark, so these two are said
    // only of a name given from outside or one a 천지인 dot was left in.
    if (nickname.contains(RegExp(r'\s'))) {
      return '띄어쓰기 없이 입력해 주세요.';
    }
    if (!nicknamePattern.hasMatch(nickname)) {
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
      _saveFailed ? failureLine(_saveError, _saveFailure) : _nicknameError;

  bool get _canSave => _nicknameError == null && !_saving;

  void _handleChanged(String value) => setState(() => _saveFailed = false);

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    // Found now: a popup closed while its save runs has no context left.
    final messenger = ScaffoldMessenger.maybeOf(context);
    var saved = false;
    Object? failure;
    try {
      saved = await widget.onSave(_controller.text);
    } catch (error) {
      failure = error;
    }
    if (!mounted) {
      // The popup was closed meanwhile and cannot say that the save did
      // not go through: the page under it does.
      if (!saved) {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(appSnackBar(failureLine(failure, _saveFailure)));
      }
      return;
    }
    if (saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _saveFailed = true;
      _saveError = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _feedbackError;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('닉네임 변경', style: AppTextStyles.popupTitle),
          const SizedBox(height: AppSpacing.xs),
          const Text('술결에서 사용할 닉네임을 입력해주세요.', style: AppTextStyles.sheetBody),
          const SizedBox(height: AppSpacing.lg),
          // More than twelve letters are not taken, so no count is shown.
          AppTextField(
            key: const ValueKey<String>('profile-nickname-field'),
            controller: _controller,
            autofocus: true,
            hintText: '닉네임을 입력해 주세요',
            maxLength: _nicknameMaxLength,
            size: AppTextFieldSize.small,
            hasError: _saveFailed,
            textInputAction: TextInputAction.done,
            inputFormatters: <TextInputFormatter>[
              nicknameInput,
              LengthLimitingTextInputFormatter(_nicknameMaxLength),
            ],
            onChanged: _handleChanged,
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            error ?? '사용 가능한 닉네임이에요.',
            key: const ValueKey<String>('profile-nickname-feedback'),
            style: AppTextStyles.body.copyWith(
              color: error == null
                  ? AppColors.preferencePrimary
                  : AppColors.actionPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  key: const ValueKey<String>('profile-nickname-cancel'),
                  label: '취소',
                  variant: AppButtonVariant.neutral,
                  size: AppButtonSize.popup,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  key: const ValueKey<String>('profile-save-button'),
                  label: '저장',
                  onPressed: _canSave ? _save : null,
                  isLoading: _saving,
                  variant: AppButtonVariant.accent,
                  size: AppButtonSize.popup,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
