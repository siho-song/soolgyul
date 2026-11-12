import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../label_camera_screen.dart';

const String tasteFitLabelButtonLabel = '라벨 사진으로 찾기';
const String tasteFitLabelReadingHint = '라벨을 분석하고 있어요. 잠시만 기다려 주세요.';
const String tasteFitLabelUnreadableHint =
    '라벨을 인식하지 못했어요. 라벨이 잘 보이도록 다시 촬영해 주세요.';
const String tasteFitLabelNoMatchHint =
    '라벨에서 술 이름을 찾지 못했어요. 다시 찍거나 이름으로 검색해 보세요.';

/// The no-match hint with the words the photo was read as, so the reader
/// sees whether the label or something else was read.
String tasteFitLabelNoMatchMessage(List<String> readWords) {
  final words = readWords.join(' ');
  if (words.isEmpty) return tasteFitLabelNoMatchHint;
  final shown = words.length > 40 ? '${words.substring(0, 40)}…' : words;
  return '$tasteFitLabelNoMatchHint\n읽은 글자: $shown';
}

const String tasteFitLabelBackSideHint =
    '뒷면에서 술 이름을 찾지 못했어요. 이름이 크게 적힌 앞면도 찍어 보세요.';

final ImagePicker _imagePicker = ImagePicker();

/// Opens the label camera and hands back the photo. The camera screen can
/// also send the reader to the album, or back to typing, which calls
/// [onTypeInstead]; closing it calls [onClosed]. `null` when no photo came
/// out of it.
Future<XFile?> takeLabelPhoto(
  BuildContext context, {
  required VoidCallback onTypeInstead,
  VoidCallback? onClosed,
}) async {
  final outcome = await Navigator.of(context).push<LabelCameraOutcome>(
    MaterialPageRoute<LabelCameraOutcome>(
      fullscreenDialog: true,
      builder: (_) => const LabelCameraScreen(),
    ),
  );
  if (!context.mounted) return null;
  switch (outcome) {
    case LabelPhotoTaken(:final file):
      return file;
    case LabelAlbumRequested():
      return _pickFromAlbum();
    case LabelNameSearchRequested():
      onTypeInstead();
      return null;
    case null:
      onClosed?.call();
      return null;
  }
}

Future<XFile?> _pickFromAlbum() async {
  try {
    return await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 88,
      requestFullMetadata: false,
    );
  } catch (_) {
    return null;
  }
}
