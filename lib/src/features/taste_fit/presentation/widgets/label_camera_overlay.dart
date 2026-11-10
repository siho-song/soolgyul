part of '../label_camera_screen.dart';

// Everything drawn over the viewfinder: the frame, the hint, the shutter
// and the ways out, and what shows when there is no camera.

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
                AppIconButton(
                  key: const ValueKey<String>('label-camera-close'),
                  tooltip: '촬영 닫기',
                  onPressed: onClose,
                  variant: AppIconButtonVariant.scrim,
                  size: AppIconButtonSize.compact,
                  child: const AppIcon(
                    AppIconAsset.close,
                    size: AppSizes.iconLg,
                    color: Colors.white,
                    weight: AppIconWeight.strong,
                  ),
                ),
                const Spacer(),
                AppIconButton(
                  key: const ValueKey<String>('label-camera-flash'),
                  tooltip: flashOn ? '플래시 끄기' : '플래시 켜기',
                  onPressed: onToggleFlash,
                  variant: AppIconButtonVariant.scrim,
                  size: AppIconButtonSize.compact,
                  child: Icon(
                    flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    size: AppSizes.iconLg,
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
                    label: '직접 검색',
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
        borderRadius: BorderRadius.circular(AppRadii.chip),
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
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppIcon(
                icon,
                size: AppSizes.iconLg,
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
      label: '사진 촬영',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: AppDurations.standard,
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
