import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../catalog/data/catalog_search_gateway.dart';
import '../../../catalog/data/discovery_events.dart';
import '../../data/label_text_recognizer.dart';
import '../../data/saved_drinks_gateway.dart';
import '../../data/taste_fit_gateway.dart';
import '../label_camera_screen.dart';
import '../label_scan_flow.dart';
import '../taste_fit_search_screen.dart';

const String tasteFitLabelButtonLabel = '라벨 사진으로 찾기';
const String tasteFitLabelReadingHint = '라벨을 분석하고 있어요. 잠시만 기다려 주세요.';
const String tasteFitLabelUnreadableHint =
    '라벨을 인식하지 못했어요. 라벨이 잘 보이도록 다시 촬영해 주세요.';
const String tasteFitLabelNoMatchHint =
    '라벨에서 술 이름을 찾지 못했어요. 다시 찍거나 이름으로 검색해 보세요.';

const String tasteFitLabelTiedHint =
    '라벨에서 브랜드까지만 읽혔어요. 품종이나 종류가 적힌 곳이 가려지지 않게 다시 찍거나, 아래에서 골라 주세요.';

/// Under the drinks a photo of several surely shows, over the candidates
/// of the bottle in its middle.
const String tasteFitLabelTiedAmongHint =
    '가운데 병은 브랜드까지만 읽혔어요. 품종이나 종류가 적힌 곳이 가려지지 않게 다시 찍거나, 아래에서 골라 주세요.';

const String tasteFitLabelBackSideHint =
    '뒷면에서 술 이름을 찾지 못했어요. 이름이 크게 적힌 앞면도 찍어 보세요.';

/// Opens the label camera for one photo and hands it back: the camera
/// closes as soon as it is taken. `null` when it was closed without one.
Future<XFile?> takeLabelPhoto(BuildContext context) =>
    Navigator.of(context).push<XFile>(
      MaterialPageRoute<XFile>(
        fullscreenDialog: true,
        builder: (context) => LabelCameraScreen(
          onShot: (shot) => Navigator.of(context).pop(shot.file),
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );

/// Opens the label camera that lists what its photos show ([LabelScanFlow])
/// and completes when the reader has closed it.
Future<void> openLabelScanFlow(
  BuildContext context, {
  required CatalogSearchGateway catalogSearchGateway,
  required LabelTextRecognizer recognizer,
  required ValueChanged<TasteFitSelection> onSelect,
  TasteFitGateway? tasteFitGateway,
  SavedDrinksGateway? savedDrinks,
  DiscoveryEventGateway? discoveryEvents,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => LabelScanFlow(
      catalogSearchGateway: catalogSearchGateway,
      recognizer: recognizer,
      onSelect: onSelect,
      tasteFitGateway: tasteFitGateway,
      savedDrinks: savedDrinks,
      discoveryEvents: discoveryEvents,
    ),
  ),
);
