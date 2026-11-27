import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_top_bar.dart';
import '../label_camera_screen.dart';

String labelReadingTitle(int photos) => '사진 $photos장을 읽고 있어요';
const String labelReadingNote = '완료되면 잘 맞는 술부터 순서대로 보여드릴게요.';
const String labelReadingFailedTitle = '사진을 읽지 못했어요';
const String labelReadingFailedNote = '잠시 후 다시 시도해 주세요.';
const String labelReadingRetryLabel = '다시 시도';

/// What the gauge says: the bottles are counted first, then read.
String labelReadingStep(int read, int bottles) =>
    bottles == 0 ? '병을 찾고 있어요' : '$bottles병 중 $read병을 읽었어요';

/// Between the camera and the finds: the photos taken are read together,
/// and a gauge with its percentage says how far that is.
class LabelReadingScreen extends StatelessWidget {
  const LabelReadingScreen({
    required this.shots,
    required this.bottles,
    required this.read,
    required this.onBack,
    this.failed = false,
    this.onRetry,
    super.key,
  });

  /// The photos being read, oldest first.
  final List<XFile> shots;

  /// The bottles counted on them and how many are read; 0 bottles while
  /// they are still being counted.
  final int bottles;
  final int read;

  /// Back to the camera, the photos kept.
  final VoidCallback onBack;

  /// The reading stopped on an error: the gauge gives way to 다시 시도.
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final done = bottles == 0 ? 0.0 : (read / bottles).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: AppColors.surfaceCanvas,
      appBar: AppTopBar.back(onPressed: onBack),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sheetX),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: 99,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (final shot in shots.take(4))
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          child: SizedBox(
                            width: 74,
                            height: 99,
                            child: LabelShotImage(shot),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                failed
                    ? labelReadingFailedTitle
                    : labelReadingTitle(shots.length),
                textAlign: TextAlign.center,
                style: AppTextStyles.sheetTitle,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                failed ? labelReadingFailedNote : labelReadingNote,
                textAlign: TextAlign.center,
                style: AppTextStyles.sheetBody,
              ),
              const SizedBox(height: AppSpacing.xxxl),
              if (failed)
                Center(
                  child: AppButton(
                    key: const ValueKey<String>('label-reading-retry'),
                    label: labelReadingRetryLabel,
                    widthMode: AppButtonWidthMode.intrinsic,
                    onPressed: onRetry,
                  ),
                )
              else ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        labelReadingStep(read, bottles),
                        style: AppTextStyles.bodyMuted,
                      ),
                    ),
                    Text(
                      '${(100 * done).round()}%',
                      style: AppTextStyles.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                  child: LinearProgressIndicator(
                    value: done,
                    minHeight: 6,
                    color: AppColors.actionPrimary,
                    backgroundColor: AppColors.surfaceMuted,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.massive),
            ],
          ),
        ),
      ),
    );
  }
}
