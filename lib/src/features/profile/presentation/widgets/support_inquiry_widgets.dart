import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_surface.dart';
import '../../../../widgets/app_state_view.dart';
import '../../../../widgets/app_tap_slop.dart';

/// The photos attached so far, each with its own remove mark, and a tile
/// that adds more until there are [max]. Another pick adds to the ones
/// already here instead of replacing them.
class InquiryAttachments extends StatelessWidget {
  const InquiryAttachments({
    super.key,
    required this.images,
    required this.picking,
    required this.onPick,
    required this.onRemove,
  });

  static const max = 5;
  static const _tile = 72.0;

  final List<XFile> images;
  final bool picking;
  final VoidCallback? onPick;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: '첨부 이미지 '),
            TextSpan(text: '(선택)', style: AppTextStyles.detail),
          ],
        ),
        style: AppTextStyles.supportFieldLabel,
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final (index, image) in images.indexed)
            _AttachedPhoto(
              key: ValueKey<String>('support-inquiry-image-$index'),
              file: image,
              size: _tile,
              onRemove: onRemove == null ? null : () => onRemove!(index),
            ),
          if (images.length < max)
            AppSurface(
              key: const ValueKey<String>('support-inquiry-images'),
              onPressed: onPick,
              semanticLabel: '사진 첨부하기',
              width: _tile,
              height: _tile,
              variant: AppSurfaceVariant.outlined,
              borderRadius: AppRadii.control,
              borderColor: AppColors.borderSubtle,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (picking)
                    const AppSmallSpinner()
                  else
                    const AppIcon(
                      AppIconAsset.camera,
                      size: AppSizes.iconLg,
                      color: AppColors.supportIconWarm,
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${images.length}/$max',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.supportIconWarm,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

/// One attached photo as a square thumbnail with a remove mark on its
/// corner. The file is read once, not on every rebuild of the form.
class _AttachedPhoto extends StatefulWidget {
  const _AttachedPhoto({
    required this.file,
    required this.size,
    required this.onRemove,
    super.key,
  });

  final XFile file;
  final double size;
  final VoidCallback? onRemove;

  @override
  State<_AttachedPhoto> createState() => _AttachedPhotoState();
}

class _AttachedPhotoState extends State<_AttachedPhoto> {
  static const _markSize = 22.0;

  /// Makes the part of the mark's tap area that lies on the photo a full
  /// tap target; the mark hangs [AppSpacing.xs] outside it.
  static const _markSlop =
      AppSizes.minimumTapTarget - _markSize + AppSpacing.xs;

  late Future<Uint8List> _bytes = widget.file.readAsBytes();

  @override
  void didUpdateWidget(_AttachedPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _bytes = widget.file.readAsBytes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final decodeSize = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: ColoredBox(
                color: AppColors.surfaceSoft,
                child: FutureBuilder<Uint8List>(
                  future: _bytes,
                  builder: (context, snapshot) => switch (snapshot.data) {
                    final bytes? => Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      cacheWidth: decodeSize,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                    null => const SizedBox.shrink(),
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: -AppSpacing.xs,
            right: -AppSpacing.xs,
            // The mark is small and hangs over the corner; the photo's
            // corner under it takes the tap too.
            child: AppTapSlop(
              slop: const EdgeInsets.only(left: _markSlop, bottom: _markSlop),
              child: Semantics(
                button: true,
                label: '첨부한 사진 빼기',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onRemove,
                  child: Container(
                    width: _markSize,
                    height: _markSize,
                    decoration: const BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: AppIcon(
                        AppIconAsset.close,
                        size: 14,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InquiryFieldLabel extends StatelessWidget {
  const InquiryFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTextStyles.supportFieldLabel);
}

InputDecoration inquiryFieldDecoration() => InputDecoration(
  filled: true,
  fillColor: AppColors.surfacePrimary,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.s14,
  ),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
    borderSide: const BorderSide(color: AppColors.borderSubtle),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
    borderSide: const BorderSide(color: AppColors.borderSubtle),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
    borderSide: const BorderSide(color: AppColors.borderFocused, width: 1.6),
  ),
);
