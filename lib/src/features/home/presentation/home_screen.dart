import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/async_shown.dart';
import '../../../design/app_feature_layouts.dart';
import '../../../widgets/kept_text.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_chip.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../../../widgets/app_surface.dart';
import '../data/home_providers.dart';
import 'first_record_invite.dart';
import 'soolgyul_letters_card.dart';
import 'taste_fit_search_entry.dart';

/// The home tab: the fit search and the member's taste letters. A member
/// who has no record yet is shown the first-record invite in their place.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    required this.onOpenSoolgyulLetters,
    required this.onOpenTasteFit,
    required this.onStartRecord,
    this.onScanLabel,
    this.onRefresh,
    super.key,
  });

  final VoidCallback onOpenSoolgyulLetters;
  final VoidCallback onOpenTasteFit;

  /// Starts a record: 기록하기 at the top right, and the invite's button.
  final VoidCallback onStartRecord;

  /// Opens the taste-fit search straight into a label photo; `null` hides
  /// the camera button (the web reads no labels).
  final VoidCallback? onScanLabel;

  /// Pulling home down asks for the letters again, for a card saved on
  /// the web or another device.
  final Future<void> Function()? onRefresh;

  /// Whether the member is known to have no record. Not while the letters
  /// load or after they failed to, where the home stays as it is.
  bool _hasNoRecord(WidgetRef ref) {
    if (ref.watch(tasteLettersGatewayProvider) == null) return false;
    final loaded = shownValue(ref.watch(tasteLettersProvider));
    return loaded != null && (loaded.state?.recordCount ?? 0) == 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MainTabScrollView(
      topPadding: 0,
      onRefresh: onRefresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The room above the logo is the same as under it, so the chip
          // centred on this box is level with the logo and has its whole
          // tap target inside the page.
          Stack(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.lg),
                child: _HomeLogo(),
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AppChip(
                    key: const ValueKey<String>('home-record-chip'),
                    label: '기록하기',
                    leadingIcon: AppIconAsset.edit,
                    onPressed: onStartRecord,
                  ),
                ),
              ),
            ],
          ),
          if (_hasNoRecord(ref))
            FirstRecordInvite(onStart: onStartRecord)
          else
            ..._boxes(),
        ],
      ),
    );
  }

  /// The home's two boxes: the fit search and the letters.
  List<Widget> _boxes() => <Widget>[
    AppPanel(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('고민 중인 술이 있나요?', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          const KeptText(
            '라벨을 촬영하거나 검색해\n내 입맛과의 궁합을 확인해 보세요.',
            style: AppTextStyles.detail,
          ),
          const SizedBox(height: AppSpacing.s14),
          TasteFitSearchEntry(onOpen: onOpenTasteFit, onScanLabel: onScanLabel),
        ],
      ),
    ),
    const SizedBox(height: HomeLayoutSpacing.cardGap),
    SoolgyulLettersCard(onOpen: onOpenSoolgyulLetters),
  ];
}

/// The 술결 logo at the top left of the home, where the other main tabs
/// write their name, with the same room under it. It is the app's mark
/// here, not a way home, so it is read as 술결 only.
class _HomeLogo extends StatelessWidget {
  const _HomeLogo();

  /// About as tall as a main tab's name, whose place it takes.
  static const _height = 24.0;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        header: true,
        label: '술결',
        excludeSemantics: true,
        child: Image.asset(
          'assets/brand/soolgyul_wordmark.webp',
          key: const ValueKey<String>('home-logo'),
          height: _height,
          filterQuality: FilterQuality.medium,
        ),
      ),
    ),
  );
}
