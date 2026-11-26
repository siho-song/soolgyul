import 'package:flutter/services.dart';

import 'label_layout.dart';

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

/// Reads the text lines off a label photo on the device: iOS uses Apple
/// Vision, Android the ML Kit Korean and Japanese models. Reading sends
/// nothing anywhere.
abstract interface class LabelTextRecognizer {
  /// Every line read, with where it sits in the photo. Empty when the
  /// photo holds no legible text.
  Future<List<ReadLine>> recognizeLines(String imagePath);
}

/// Where one drink a photo of several shows stands: fractions of the
/// photo's width and height from its top left corner.
class BottleBox {
  const BottleBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, double> toChannel() => <String, double>{
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  static BottleBox? fromChannel(Object? value) {
    if (value is! Map) return null;
    final left = value['left'];
    final top = value['top'];
    final right = value['right'];
    final bottom = value['bottom'];
    if (left is! num || top is! num || right is! num || bottom is! num) {
      return null;
    }
    return BottleBox(
      left: left.toDouble(),
      top: top.toDouble(),
      right: right.toDouble(),
      bottom: bottom.toDouble(),
    );
  }
}

/// Finds the drinks in a photo with the on-device detector and reads each
/// by itself, so the words of one bottle are not taken for another's. Each
/// is read on its own call, so the first can be searched while the next is
/// read.
abstract interface class LabelBottleReader {
  /// The drinks [imagePath] shows. Empty when it shows fewer than two: such
  /// a photo is read whole.
  Future<List<BottleBox>> findBottles(String imagePath);

  /// What [bottle], cut out of [imagePath], reads; positions within the
  /// cut-out.
  Future<List<ReadLine>> readBottle(String imagePath, BottleBox bottle);

  /// The one bottle of [imagePath] as a small JPEG, for the server's judge
  /// ([LabelPhotoJudge]): [bottle] cut out, or with none given the largest
  /// thing the detector finds, or the whole photo when it finds nothing.
  Future<Uint8List> bottlePhoto(String imagePath, [BottleBox? bottle]);
}

class LabelTextRecognitionException implements Exception {
  const LabelTextRecognitionException();
}

class PlatformLabelTextRecognizer
    implements LabelTextRecognizer, LabelBottleReader, LabelFrameTextDetector {
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
  Future<List<ReadLine>> recognizeLines(String imagePath) async {
    try {
      final lines = await _channel.invokeListMethod<Object?>(
        'recognizeLines',
        <String, String>{'path': imagePath},
      );
      return <ReadLine>[
        for (final line in lines ?? const <Object?>[])
          ?ReadLine.fromChannel(line),
      ];
    } on PlatformException {
      throw const LabelTextRecognitionException();
    } on MissingPluginException {
      throw const LabelTextRecognitionException();
    }
  }

  @override
  Future<List<BottleBox>> findBottles(String imagePath) async {
    try {
      final bottles = await _channel.invokeListMethod<Object?>(
        'findBottles',
        <String, String>{'path': imagePath},
      );
      return <BottleBox>[
        for (final bottle in bottles ?? const <Object?>[])
          ?BottleBox.fromChannel(bottle),
      ];
    } on PlatformException {
      throw const LabelTextRecognitionException();
    } on MissingPluginException {
      throw const LabelTextRecognitionException();
    }
  }

  @override
  Future<List<ReadLine>> readBottle(String imagePath, BottleBox bottle) async {
    try {
      final lines = await _channel.invokeListMethod<Object?>(
        'readBottle',
        <String, Object>{'path': imagePath, ...bottle.toChannel()},
      );
      return <ReadLine>[
        for (final line in lines ?? const <Object?>[])
          ?ReadLine.fromChannel(line),
      ];
    } on PlatformException {
      throw const LabelTextRecognitionException();
    } on MissingPluginException {
      throw const LabelTextRecognitionException();
    }
  }

  @override
  Future<Uint8List> bottlePhoto(String imagePath, [BottleBox? bottle]) async {
    try {
      final jpeg = await _channel.invokeMethod<Uint8List>(
        'bottlePhoto',
        <String, Object>{'path': imagePath, ...?bottle?.toChannel()},
      );
      if (jpeg == null || jpeg.isEmpty) {
        throw const LabelTextRecognitionException();
      }
      return jpeg;
    } on PlatformException {
      throw const LabelTextRecognitionException();
    } on MissingPluginException {
      throw const LabelTextRecognitionException();
    }
  }
}
