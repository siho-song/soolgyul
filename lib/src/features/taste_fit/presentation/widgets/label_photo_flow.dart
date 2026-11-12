import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../label_camera_screen.dart';

const String tasteFitLabelButtonLabel = '라벨 사진으로 찾기';
const String tasteFitLabelReadingHint = '라벨을 분석하고 있어요. 잠시만 기다려 주세요.';
const String tasteFitLabelUnreadableHint =
    '라벨을 인식하지 못했어요. 라벨이 잘 보이도록 다시 촬영해 주세요.';
const String tasteFitLabelNoMatchHint = '등록되지 않은 술이에요. 직접 검색해서 찾아보세요.';
const String tasteFitLabelBackSideHint =
    '뒷면에서 술 이름을 찾지 못했어요. 이름이 크게 적힌 앞면도 찍어 보세요.';

final ImagePicker _imagePicker = ImagePicker();

/// Opens the label camera and hands back the photo. The camera screen can
/// also send the reader to the album, or back to typing, which calls
/// [onTypeInstead]. `null` when no photo came out of it.
Future<XFile?> takeLabelPhoto(
  BuildContext context, {
  required VoidCallback onTypeInstead,
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
