import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_icon_button.dart';
import '../data/label_text_recognizer.dart';
import '../../../core/errors/error_report.dart';

part 'widgets/label_camera_overlay.dart';

/// What the reader did on the camera screen.
sealed class LabelCameraOutcome {
  const LabelCameraOutcome();
}

class LabelPhotoTaken extends LabelCameraOutcome {
  const LabelPhotoTaken(this.file);

  final XFile file;
}

class LabelAlbumRequested extends LabelCameraOutcome {
  const LabelAlbumRequested();
}

class LabelNameSearchRequested extends LabelCameraOutcome {
  const LabelNameSearchRequested();
}

const String labelCameraHint = '라벨이 선명하게 보이도록 맞춰 주세요.';
const String labelCameraDarkHint = '주변이 어두워요. 플래시를 켜 보세요.';
const String labelCameraFrameHint = '라벨을 영역 안에 맞추고 빛 반사를 피해 주세요.';
const String labelCameraTip = '💡 수입 주류는 뒷면 한글 표시사항이 더 잘 인식돼요.';
const String labelCameraDenied = '카메라 접근 권한이 필요해요.\n설정에서 허용하면 라벨을 촬영할 수 있어요.';
const String labelCameraNoCamera =
    '카메라를 사용할 수 없는 기기예요.\n앨범에서 사진을 선택하거나 검색해 보세요.';
const String labelCameraSettingsLabel = '권한 설정하러 가기';

/// Whether the viewfinder is up, and if not, why.
enum LabelCameraStatus { opening, ready, denied, noCamera }

/// Mean luma below this (0-255) reads as too dark for the label text.
const int _darkLuma = 60;
const Duration _frameInterval = Duration(milliseconds: 900);
const List<Shadow> _textShadows = <Shadow>[
  Shadow(color: Colors.black54, blurRadius: 8),
];

/// The viewfinder for a label photo: a frame to put the label in, a hint
/// that turns into a flash prompt in the dark, and ways out to the album
/// or to typing the name. Pops with a [LabelCameraOutcome], or null when
/// closed.
class LabelCameraScreen extends StatefulWidget {
  const LabelCameraScreen({
    this.textDetector = const PlatformLabelTextRecognizer(),
    this.openSettings = _openPlatformSettings,
    super.key,
  });

  /// Lights the shutter while the frame holds text; `null` never lights it.
  final LabelFrameTextDetector? textDetector;
  final Future<void> Function() openSettings;

  static Future<void> _openPlatformSettings() =>
      const PlatformLabelTextRecognizer().openAppSettings();

  @override
  State<LabelCameraScreen> createState() => _LabelCameraScreenState();
}

class _LabelCameraScreenState extends State<LabelCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  LabelCameraStatus _status = LabelCameraStatus.opening;
  bool _flashOn = false;
  bool _dark = false;
  bool _textDetected = false;
  bool _capturing = false;
  bool _frameBusy = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (_controller == null) return;
      // The preview leaves the screen in the frame its camera is let go;
      // drawing a closed camera throws.
      setState(() => _status = LabelCameraStatus.opening);
      unawaited(_close());
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      unawaited(_open());
    }
  }

  /// The permission prompt of a first use takes the app out of the front
  /// and back, which asks for the camera a second time while the first
  /// request is still open. One request at a time.
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', 'no camera');
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      await controller.startImageStream(_onFrame);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _status = LabelCameraStatus.ready;
        _flashOn = false;
      });
    } on CameraException catch (error) {
      if (mounted) setState(() => _status = _statusFor(error));
    } catch (_) {
      if (mounted) setState(() => _status = LabelCameraStatus.noCamera);
    } finally {
      _opening = false;
    }
  }

  static LabelCameraStatus _statusFor(CameraException error) {
    final code = error.code.toLowerCase();
    final denied =
        code.contains('denied') ||
        code.contains('permission') ||
        code.contains('restricted');
    return denied ? LabelCameraStatus.denied : LabelCameraStatus.noCamera;
  }

  Future<void> _close() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Already stopped.
    }
    await controller.dispose();
  }

  /// A few times a second: the frame's brightness decides the hint, and
  /// the text detector decides whether the shutter lights up.
  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_frameBusy || now.difference(_lastFrame) < _frameInterval) return;
    _lastFrame = now;
    final controller = _controller;
    final frame = _halfSizeLuma(
      image,
      rotationDegrees: controller?.description.sensorOrientation ?? 0,
    );
    if (frame == null) return;
    final dark = _meanLuma(frame.luma) < _darkLuma;
    if (dark != _dark && mounted) setState(() => _dark = dark);
    final detector = widget.textDetector;
    if (detector == null) return;
    _frameBusy = true;
    unawaited(
      detector.hasText(frame).then((found) {
        _frameBusy = false;
        if (found != _textDetected && mounted) {
          setState(() => _textDetected = found);
        }
      }),
    );
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = !_flashOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _flashOn = next);
    } on CameraException {
      // No torch on this device; the hint still helps.
    }
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final file = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(LabelPhotoTaken(file));
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _status = _statusFor(error);
      });
    } catch (error, stack) {
      // Whatever went wrong, the shutter works again.
      reportError(error, stack, where: 'camera');
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (controller != null) _Viewfinder(controller: controller),
            LabelCameraOverlay(
              status: _status,
              hint: _dark ? labelCameraDarkHint : labelCameraHint,
              flashOn: _flashOn,
              textDetected: _textDetected,
              shutterEnabled: controller != null && !_capturing,
              onClose: () => Navigator.of(context).pop(),
              onToggleFlash: controller == null ? null : _toggleFlash,
              onOpenSettings: widget.openSettings,
              onAlbum: () =>
                  Navigator.of(context).pop(const LabelAlbumRequested()),
              onShoot: _shoot,
              onSearch: () =>
                  Navigator.of(context).pop(const LabelNameSearchRequested()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The preview filling the screen, cropped rather than letterboxed.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return const SizedBox.shrink();
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // The sensor reports landscape; the phone holds it upright.
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

/// Every other pixel of the luma plane, which is enough to judge light and
/// find label-sized text at a fraction of the work.
LabelFrame? _halfSizeLuma(CameraImage image, {required int rotationDegrees}) {
  if (image.planes.isEmpty) return null;
  final plane = image.planes.first;
  final source = plane.bytes;
  final stride = plane.bytesPerRow;
  final width = image.width ~/ 2;
  final height = image.height ~/ 2;
  if (width == 0 || height == 0) return null;
  final luma = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final sourceRow = y * 2 * stride;
    if (sourceRow + width * 2 > source.length) return null;
    final targetRow = y * width;
    for (var x = 0; x < width; x++) {
      luma[targetRow + x] = source[sourceRow + x * 2];
    }
  }
  return LabelFrame(
    luma: luma,
    width: width,
    height: height,
    rotationDegrees: rotationDegrees,
  );
}

int _meanLuma(Uint8List luma) {
  var sum = 0;
  var count = 0;
  for (var i = 0; i < luma.length; i += 41) {
    sum += luma[i];
    count += 1;
  }
  return count == 0 ? 255 : sum ~/ count;
}
