part of '../label_camera_screen.dart';

// Everything drawn over the viewfinder: the ways out, the line that says
// what to shoot, the shutter with the photos taken and the way on beside
// it, and what shows when there is no camera.

/// The picture on screen, width to height.
const double labelCameraPictureRatio = 3 / 4;
const double _shutterSize = 76;
const double _topBarHeight = 48;

/// The band of the shutter: its margins, the line above it and the shutter.
const double _bandHeight =
    AppSpacing.md + 20 + AppSpacing.md + _shutterSize + AppSpacing.lg;

/// The band's veil where a short screen puts it on the picture.
const Color _bandColor = Color(0x8C000000);

/// Where the live picture goes: as wide as the screen, in the 3:4 of a
/// photo, resting on the band of the shutter. What height is left goes
/// above it; a screen too short for that starts the picture under the top
/// bar and the band lies over its foot.
class LabelCameraPictureArea extends StatelessWidget {
  const LabelCameraPictureArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final top = insets.top + _topBarHeight;
        final spare =
            constraints.maxHeight -
            top -
            constraints.maxWidth / labelCameraPictureRatio -
            _bandHeight -
            insets.bottom;
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: top + math.max(0, spare)),
            child: AspectRatio(
              aspectRatio: labelCameraPictureRatio,
              child: ClipRect(child: child),
            ),
          ),
        );
      },
    );
  }
}

/// Everything drawn over the viewfinder. Pure so tests can render it.
class LabelCameraOverlay extends StatelessWidget {
  const LabelCameraOverlay({
    required this.status,
    required this.flashOn,
    required this.textDetected,
    required this.shutterEnabled,
    required this.onClose,
    required this.onToggleFlash,
    required this.onOpenSettings,
    required this.onShoot,
    this.hint,
    this.shots = const <XFile>[],
    this.backToResults = false,
    this.onReviewShots,
    this.onResults,
    super.key,
  });

  final LabelCameraStatus status;

  /// What is wrong with the scene now (too dark, too many bottles, the
  /// photos full), in the line above the shutter. `null` leaves the line
  /// saying what to shoot before the first photo, and empty after it.
  final String? hint;
  final bool flashOn;

  /// Lights the shutter ring: the frame holds text, so a shot will read.
  final bool textDetected;
  final bool shutterEnabled;

  /// The photos taken and not read yet, oldest first. With one or more
  /// their stack stands at the left of the shutter and the way on to what
  /// they show at its right; before the first the shutter stands alone.
  final List<XFile> shots;

  /// The top left is the way back to the finds, not the way out.
  final bool backToResults;
  final VoidCallback onClose;
  final VoidCallback? onToggleFlash;
  final Future<void> Function() onOpenSettings;
  final VoidCallback onShoot;
  final VoidCallback? onReviewShots;
  final VoidCallback? onResults;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    return SafeArea(
      child: Column(
        children: <Widget>[
          Container(
            height: _topBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                AppIconButton(
                  key: const ValueKey<String>('label-camera-close'),
                  tooltip: backToResults ? '결과로 돌아가기' : '촬영 닫기',
                  onPressed: onClose,
                  variant: AppIconButtonVariant.scrim,
                  size: AppIconButtonSize.compact,
                  child: AppIcon(
                    backToResults ? AppIconAsset.previous : AppIconAsset.close,
                    size: AppSizes.iconLg,
                    color: Colors.white,
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
              LabelCameraStatus.opening ||
              LabelCameraStatus.ready => const SizedBox.shrink(),
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
          Container(
            // Unseen where the band is under the picture, a veil where a
            // short screen puts it on the picture.
            color: _bandColor,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // One line above the shutter, its words changing in place.
                // Its height stays when it is empty, so the shutter does
                // not move.
                SizedBox(
                  height: 20,
                  child: AnimatedSwitcher(
                    duration: AppDurations.standard,
                    child:
                        status != LabelCameraStatus.ready ||
                            (hint == null && shots.isNotEmpty)
                        ? const SizedBox.shrink()
                        : Text(
                            hint ?? labelCameraGuide,
                            key: ValueKey<String>(hint ?? labelCameraGuide),
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: const AppTextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: shots.isEmpty
                          ? const SizedBox.shrink()
                          : Center(
                              child: _ShotStack(
                                key: const ValueKey<String>(
                                  'label-camera-shots',
                                ),
                                shots: shots,
                                onTap: onReviewShots,
                              ),
                            ),
                    ),
                    _Shutter(
                      key: const ValueKey<String>('label-camera-shoot'),
                      enabled: shutterEnabled,
                      lit: textDetected,
                      onTap: onShoot,
                    ),
                    Expanded(
                      child: shots.isEmpty
                          ? const SizedBox.shrink()
                          : Center(
                              child: _ResultsButton(
                                key: const ValueKey<String>(
                                  'label-camera-results',
                                ),
                                onTap: onResults,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
          width: _shutterSize,
          height: _shutterSize,
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

/// A photo taken, small. One whose file cannot be drawn keeps its place.
class LabelShotImage extends StatelessWidget {
  const LabelShotImage(this.shot, {this.fit = BoxFit.cover, super.key});

  final XFile shot;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.file(
    File(shot.path),
    fit: fit,
    // Small places decode small: the photos are the camera's largest.
    cacheWidth: fit == BoxFit.cover ? 320 : null,
    errorBuilder: (_, _, _) => const ColoredBox(color: Colors.white24),
  );
}

/// The photos taken so far as cards lying on one another, the newest on
/// top, with their number at the corner.
class _ShotStack extends StatelessWidget {
  const _ShotStack({required this.shots, required this.onTap, super.key});

  final List<XFile> shots;
  final VoidCallback? onTap;

  static const _card = Size(42, 56);

  @override
  Widget build(BuildContext context) {
    // The newest three; older ones are under them.
    final top = shots.length > 3 ? shots.sublist(shots.length - 3) : shots;
    return Semantics(
      button: true,
      label: '찍은 사진 ${shots.length}장',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _card.width + 22,
          height: _card.height + 12,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              for (final (index, shot) in top.indexed)
                Positioned(
                  left: 4.0 + 4 * index,
                  top: 6,
                  child: Transform.rotate(
                    angle: (index - (top.length - 1)) * .09,
                    child: Container(
                      width: _card.width,
                      height: _card.height,
                      clipBehavior: Clip.antiAlias,
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: LabelShotImage(shot),
                    ),
                  ),
                ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.actionPrimary,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    '${shots.length}',
                    style: const AppTextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The way on to the finds: a round wine button with the arrow alone, as
/// round as the shutter beside it.
class _ResultsButton extends StatelessWidget {
  const _ResultsButton({required this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: labelCameraResultsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: AppColors.actionPrimary,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_forward_rounded,
            size: 26,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
