import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_icon.dart';
import '../data/label_text_recognizer.dart';

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

const String labelCameraHint = '라벨 글자가 선명하게 보이도록 맞춰주세요';
const String labelCameraDarkHint = '어두워요. 플래시를 켜보세요';
const String labelCameraFrameHint = '라벨이 네모 안에 쏙 들어가게, 빛 반사 없이';
const String labelCameraTip = '💡 수입 술은 뒷면 한글 라벨이 더 잘 인식돼요';
const String labelCameraDenied = '카메라 사용이 꺼져 있어요.\n설정에서 허용하면 라벨을 찍을 수 있어요.';
const String labelCameraNoCamera =
    '이 기기에서는 카메라를 쓸 수 없어요.\n앨범에서 고르거나 이름으로 찾아보세요.';
const String labelCameraSettingsLabel = '설정에서 카메라 허용하기';

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
      unawaited(_close());
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      unawaited(_open());
    }
  }

  Future<void> _open() async {
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

/// Everything drawn over the viewfinder. Pure so tests can render it.
class LabelCameraOverlay extends StatelessWidget {
  const LabelCameraOverlay({
    required this.status,
    required this.hint,
    required this.flashOn,
    required this.textDetected,
    required this.shutterEnabled,
    required this.onClose,
    required this.onToggleFlash,
    required this.onOpenSettings,
    required this.onAlbum,
    required this.onShoot,
    required this.onSearch,
    super.key,
  });

  final LabelCameraStatus status;

  /// Shown above the frame while the viewfinder is up.
  final String hint;
  final bool flashOn;

  /// Lights the shutter ring: the frame holds text, so a shot will read.
  final bool textDetected;
  final bool shutterEnabled;
  final VoidCallback onClose;
  final VoidCallback? onToggleFlash;
  final Future<void> Function() onOpenSettings;
  final VoidCallback onAlbum;
  final VoidCallback onShoot;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                _RoundIconButton(
                  key: const ValueKey<String>('label-camera-close'),
                  semanticLabel: '닫기',
                  onTap: onClose,
                  child: const AppIcon(
                    AppIconAsset.close,
                    size: 24,
                    color: Colors.white,
                    weight: AppIconWeight.strong,
                  ),
                ),
                const Spacer(),
                _RoundIconButton(
                  key: const ValueKey<String>('label-camera-flash'),
                  semanticLabel: flashOn ? '플래시 끄기' : '플래시 켜기',
                  onTap: onToggleFlash,
                  child: Icon(
                    flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    size: 24,
                    color: flashOn ? Colors.amber : Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (status) {
              LabelCameraStatus.opening => const SizedBox.shrink(),
              LabelCameraStatus.ready => _Aim(hint: hint),
              LabelCameraStatus.denied => _Unavailable(
                message: labelCameraDenied,
                onOpenSettings: onOpenSettings,
              ),
              LabelCameraStatus.noCamera => const _Unavailable(
                message: labelCameraNoCamera,
                onOpenSettings: null,
              ),
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _SideAction(
                    key: const ValueKey<String>('label-camera-album'),
                    label: '앨범',
                    icon: AppIconAsset.photoUpload,
                    onTap: onAlbum,
                  ),
                ),
                _Shutter(
                  key: const ValueKey<String>('label-camera-shoot'),
                  enabled: shutterEnabled,
                  lit: textDetected,
                  onTap: onShoot,
                ),
                Expanded(
                  child: _SideAction(
                    key: const ValueKey<String>('label-camera-search'),
                    label: '이름검색',
                    icon: AppIconAsset.search,
                    onTap: onSearch,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The framing hint, the empty frame and the tip, stacked around the
/// middle of the viewfinder. The frame stays empty so nothing covers the
/// label.
class _Aim extends StatelessWidget {
  const _Aim({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            labelCameraFrameHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 14,
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              shadows: _textShadows,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _LabelFrame(),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            hint,
            key: const ValueKey<String>('label-camera-hint'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w800,
              shadows: _textShadows,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _TipChip(),
      ],
    );
  }
}

/// The tip in a translucent capsule, one line on a phone.
class _TipChip extends StatelessWidget {
  const _TipChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        labelCameraTip,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 13,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Replaces the frame when there is no viewfinder: why, and the way to the
/// settings when the permission is the reason.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, required this.onOpenSettings});

  final String message;
  final Future<void> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            message,
            key: const ValueKey<String>('label-camera-unavailable'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 16,
              height: 1.5,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onOpenSettings case final open?) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: const ValueKey<String>('label-camera-settings'),
              label: labelCameraSettingsLabel,
              widthMode: AppButtonWidthMode.intrinsic,
              onPressed: () => unawaited(open()),
            ),
          ],
        ],
      ),
    );
  }
}

/// Corner brackets in the proportion of a bottle label, empty inside.
class _LabelFrame extends StatelessWidget {
  const _LabelFrame();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * .64;
    return SizedBox(
      width: width,
      height: width * 4 / 3,
      child: const CustomPaint(painter: _CornerPainter()),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const arm = 28.0;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, arm)
      ..lineTo(0, 0)
      ..lineTo(arm, 0)
      ..moveTo(w - arm, 0)
      ..lineTo(w, 0)
      ..lineTo(w, arm)
      ..moveTo(w, h - arm)
      ..lineTo(w, h)
      ..lineTo(w - arm, h)
      ..moveTo(arm, h)
      ..lineTo(0, h)
      ..lineTo(0, h - arm);
    canvas.drawPath(path, paint);
    final dashed = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dash = 6.0;
    for (var x = arm + dash; x < w - arm - dash; x += dash * 2) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), dashed);
      canvas.drawLine(Offset(x, h), Offset(x + dash, h), dashed);
    }
    for (var y = arm + dash; y < h - arm - dash; y += dash * 2) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dash), dashed);
      canvas.drawLine(Offset(w, y), Offset(w, y + dash), dashed);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.black38,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(dimension: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;
  final AppIconAsset icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppIcon(
                icon,
                size: 26,
                color: Colors.white,
                weight: AppIconWeight.strong,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const AppTextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({
    required this.enabled,
    required this.lit,
    required this.onTap,
    super.key,
  });

  final bool enabled;

  /// Text is in the frame: the ring turns the brand colour.
  final bool lit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '촬영',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: lit ? AppColors.actionPrimary : Colors.white,
              width: 4,
            ),
          ),
          padding: const EdgeInsets.all(5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}
