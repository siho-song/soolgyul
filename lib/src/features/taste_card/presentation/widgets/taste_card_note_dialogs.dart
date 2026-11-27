import 'package:flutter/material.dart';

import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_dialog.dart';

/// Asks whether to stop writing a note whose form holds changes not kept;
/// true for 그만두기.
Future<bool> confirmDiscardNote(BuildContext context) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialogBody(
        title: '수정을 그만둘까요?',
        body: '수정 중인 내용은 저장되지 않고 사라져요.',
        actions: <Widget>[
          AppButton(
            key: const ValueKey<String>('taste-card-note-stay'),
            label: '계속 수정',
            variant: AppButtonVariant.neutral,
            size: AppButtonSize.popup,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            key: const ValueKey<String>('taste-card-note-leave'),
            label: '그만두기',
            size: AppButtonSize.popup,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    ) ==
    true;

/// Offers, on a card just made, to fill in the rest of its note now; true
/// for 지금 적기.
Future<bool> offerNoteForm(BuildContext context) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialogBody(
        title: '테이스팅 노트를 채웠어요.',
        // Only what the note's form asks for today.
        body: '평점과 페어링, 가격도 이어서 적어둘까요?',
        actions: <Widget>[
          AppButton(
            key: const ValueKey<String>('taste-card-note-offer-later'),
            label: '나중에',
            variant: AppButtonVariant.neutral,
            size: AppButtonSize.popup,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            key: const ValueKey<String>('taste-card-note-offer-now'),
            label: '지금 적기',
            size: AppButtonSize.popup,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    ) ==
    true;
