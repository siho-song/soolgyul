import 'package:flutter/services.dart';

/// A grey, downscaled viewfinder frame.
class LabelFrame {
  const LabelFrame({
    required this.luma,
    required this.width,
    required this.height,
    required this.rotationDegrees,
  });

  /// One byte per pixel, row after row, [width] bytes per row.
  final Uint8List luma;
  final int width;
  final int height;

  /// How far the sensor image is turned from upright.
  final int rotationDegrees;
}

/// Tells whether a viewfinder frame holds text, cheaply enough to run a few
/// times a second while the reader aims.
abstract interface class LabelFrameTextDetector {
  Future<bool> hasText(LabelFrame frame);
}

/// Reads the text lines off a label photo on the device. Nothing leaves the
/// phone: iOS uses Apple Vision, Android the ML Kit Korean model.
abstract interface class LabelTextRecognizer {
  /// Lines in reading order, top of the label first. Empty when the photo
  /// holds no legible text.
  Future<List<String>> recognizeLines(String imagePath);
}

class LabelTextRecognitionException implements Exception {
  const LabelTextRecognitionException();
}

class PlatformLabelTextRecognizer
    implements LabelTextRecognizer, LabelFrameTextDetector {
  const PlatformLabelTextRecognizer();

  static const MethodChannel _channel = MethodChannel('soolgyul/label-ocr');

  @override
  Future<bool> hasText(LabelFrame frame) async {
    try {
      return await _channel.invokeMethod<bool>('hasText', <String, Object>{
            'luma': frame.luma,
            'width': frame.width,
            'height': frame.height,
            'rotation': frame.rotationDegrees,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens this app's page in the system settings, where the camera
  /// permission lives.
  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on PlatformException {
      // Nothing to do; the reader can still use the album.
    } on MissingPluginException {
      // Same on platforms without the channel.
    }
  }

  @override
  Future<List<String>> recognizeLines(String imagePath) async {
    try {
      final lines = await _channel.invokeListMethod<String>(
        'recognizeLines',
        <String, String>{'path': imagePath},
      );
      return lines ?? const <String>[];
    } on PlatformException {
      throw const LabelTextRecognitionException();
    } on MissingPluginException {
      throw const LabelTextRecognitionException();
    }
  }
}
