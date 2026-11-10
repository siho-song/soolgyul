import 'package:flutter/material.dart';

import '../widgets/app_icon.dart';
import '../widgets/app_badge.dart';
import '../widgets/app_button.dart';
import '../widgets/app_chip.dart';
import '../widgets/app_list_row.dart';
import '../widgets/app_segmented_control.dart';
import '../widgets/app_surface.dart';
import '../widgets/app_switch.dart';
import '../widgets/app_text_field.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

class DesignSystemPreviewScreen extends StatefulWidget {
  const DesignSystemPreviewScreen({
    required this.onOpenScreen,
    super.key,
    this.initialView = 0,
    this.onViewChanged,
  });

  final ValueChanged<int> onOpenScreen;
  final int initialView;
  final ValueChanged<int>? onViewChanged;

  @override
  State<DesignSystemPreviewScreen> createState() =>
      _DesignSystemPreviewScreenState();
}

class DesignReviewNavigationOverlay extends StatefulWidget {
  const DesignReviewNavigationOverlay({
    required this.child,
    required this.onBack,
    super.key,
  });

  final Widget child;
  final VoidCallback onBack;

  @override
  State<DesignReviewNavigationOverlay> createState() =>
      _DesignReviewNavigationOverlayState();
}

class _DesignReviewNavigationOverlayState
    extends State<DesignReviewNavigationOverlay> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: widget.child),
        SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: _collapsed
                ? _CollapsedDesignReviewHandle(
                    onExpand: () => setState(() => _collapsed = false),
                  )
                : _ExpandedDesignReviewControls(
                    onBack: widget.onBack,
                    onCollapse: () => setState(() => _collapsed = true),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ExpandedDesignReviewControls extends StatelessWidget {
  const _ExpandedDesignReviewControls({
    required this.onBack,
    required this.onCollapse,
  });

  final VoidCallback onBack;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfacePrimary.withValues(alpha: .96),
      elevation: 5,
      shadowColor: const Color(0x30000000),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.horizontal(left: Radius.circular(14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Design Lab으로 돌아가기',
              onPressed: onBack,
              icon: const AppIcon(
                AppIconAsset.previous,
                size: 22,
                color: AppColors.actionPrimary,
              ),
            ),
            const Divider(height: 1),
            IconButton(
              tooltip: '검수 도구 접기',
              onPressed: onCollapse,
              icon: const AppIcon(
                AppIconAsset.next,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapsedDesignReviewHandle extends StatelessWidget {
  const _CollapsedDesignReviewHandle({required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.actionPrimary.withValues(alpha: .88),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: '검수 도구 펼치기',
        onPressed: onExpand,
        constraints: const BoxConstraints.tightFor(width: 24, height: 52),
        padding: EdgeInsets.zero,
        icon: const AppIcon(
          AppIconAsset.previous,
          size: 14,
          color: AppColors.textOnPrimary,
        ),
      ),
    );
  }
}

class _DesignSystemPreviewScreenState extends State<DesignSystemPreviewScreen> {
  late int _selectedView;
  int _selectedSegment = 0;
  bool _switchValue = true;
  bool _chipSelected = true;

  @override
  void initState() {
    super.initState();
    _selectedView = widget.initialView;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _DesignLabHeader(
          selectedView: _selectedView,
          onViewChanged: (value) {
            setState(() => _selectedView = value);
            widget.onViewChanged?.call(value);
          },
        ),
        Expanded(
          child: _selectedView == 0
              ? _buildComponentCatalog()
              : _ScreenLauncher(onOpenScreen: widget.onOpenScreen),
        ),
      ],
    );
  }

  Widget _buildComponentCatalog() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        AppSpacing.lg,
        AppSpacing.screenX,
        AppSpacing.massive,
      ),
      children: <Widget>[
        const _CatalogSectionTitle(
          title: 'Typography',
          description: '크기, 굵기, 행간의 기준 역할',
        ),
        const SizedBox(height: AppSpacing.md),
        const _TypographySpecimen(
          role: 'Display',
          sample: '술결을 발견하는 시간',
          style: AppTextStyles.displayTitle,
        ),
        const _TypographySpecimen(
          role: 'Screen',
          sample: '다음 한 잔',
          style: AppTextStyles.screenTitle,
        ),
        const _TypographySpecimen(
          role: 'Section',
          sample: '최근 술결',
          style: AppTextStyles.sectionTitle,
        ),
        const _TypographySpecimen(
          role: 'Card',
          sample: '부드럽고 달큰한 위스키',
          style: AppTextStyles.cardTitle,
        ),
        const _TypographySpecimen(
          role: 'Body L',
          sample: '오늘도 술결로 내 취향을 더 알아보세요.',
          style: AppTextStyles.bodyLarge,
        ),
        const _TypographySpecimen(
          role: 'Body',
          sample: '은은한 단맛과 향의 여운을 즐겨요.',
          style: AppTextStyles.body,
        ),
        const _TypographySpecimen(
          role: 'Caption',
          sample: '2024.05.18 · 위스키',
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: AppSpacing.xxxl),
        const _CatalogSectionTitle(
          title: 'Spacing',
          description: '화면, 섹션, 컴포넌트 내부 간격',
        ),
        const SizedBox(height: AppSpacing.md),
        const _SpacingSpecimens(),
        const SizedBox(height: AppSpacing.xxxl),
        const _CatalogSectionTitle(
          title: 'Buttons',
          description: '명령의 중요도와 크기 상태',
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: '기록 시작하기',
          leadingIcon: AppIconAsset.memo,
          variant: AppButtonVariant.accent,
          size: AppButtonSize.large,
          onPressed: () {},
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: '다른 제안 보기',
          leadingIcon: AppIconAsset.smooth,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.regular,
          onPressed: () {},
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                label: '보조 액션',
                size: AppButtonSize.compact,
                variant: AppButtonVariant.tertiary,
                onPressed: () {},
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: '비활성',
                variant: AppButtonVariant.destructive,
                isDisabled: true,
                onPressed: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxxl),
        const _CatalogSectionTitle(
          title: 'Chips & Badges',
          description: '선택, 필터, 정보 상태',
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            AppChip(
              label: '부드러움',
              selected: _chipSelected,
              leadingIcon: AppIconAsset.smooth,
              onPressed: () => setState(() => _chipSelected = !_chipSelected),
            ),
            const AppChip(label: '은은한 단맛', variant: AppChipVariant.outline),
            const AppChip(
              label: '취향 필터',
              tone: AppChipTone.preference,
              size: AppChipSize.filter,
            ),
            const AppBadge(label: 'NEW'),
            const AppBadge(
              label: '저장됨',
              icon: AppIconAsset.check,
              variant: AppBadgeVariant.solid,
              size: AppBadgeSize.regular,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxxl),
        const _CatalogSectionTitle(title: 'Controls', description: '입력과 선택 상태'),
        const SizedBox(height: AppSpacing.md),
        AppSegmentedControl<int>(
          segments: const <AppSegment<int>>[
            AppSegment<int>(value: 0, label: '월별'),
            AppSegment<int>(value: 1, label: '계절별'),
          ],
          selectedValue: _selectedSegment,
          onSelected: (value) => setState(() => _selectedSegment = value),
          variant: AppSegmentedControlVariant.pill,
        ),
        const SizedBox(height: AppSpacing.md),
        const AppTextField(
          hintText: '술 이름을 입력해주세요',
          helperText: '최대 20자까지 입력할 수 있어요.',
        ),
        const SizedBox(height: AppSpacing.md),
        AppSurface(
          variant: AppSurfaceVariant.outlined,
          borderRadius: AppRadii.control,
          child: Column(
            children: <Widget>[
              AppListRow(
                title: '알림 받기',
                subtitle: '새로운 취향 제안을 알려드려요.',
                leadingIcon: AppIconAsset.info,
                showChevron: false,
                trailing: AppSwitch(
                  value: _switchValue,
                  semanticLabel: '알림 받기',
                  onChanged: (value) => setState(() => _switchValue = value),
                ),
              ),
              AppListRow(
                title: '저장한 취향 카드',
                leadingIcon: AppIconAsset.memo,
                showDivider: false,
                onPressed: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        const _CatalogSectionTitle(
          title: 'Icons',
          description: '화면에서 쓰는 선 아이콘',
        ),
        const SizedBox(height: AppSpacing.md),
        const _IconSpecimens(),
      ],
    );
  }
}

class _DesignLabHeader extends StatelessWidget {
  const _DesignLabHeader({
    required this.selectedView,
    required this.onViewChanged,
  });

  final int selectedView;
  final ValueChanged<int> onViewChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surfacePrimary,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenX,
          AppSpacing.lg,
          AppSpacing.screenX,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Design Lab',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.screenTitle.copyWith(fontSize: 24),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const AppBadge(
                  label: 'DEBUG',
                  variant: AppBadgeVariant.outline,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppSegmentedControl<int>(
              segments: const <AppSegment<int>>[
                AppSegment<int>(value: 0, label: '컴포넌트'),
                AppSegment<int>(value: 1, label: '실제 화면'),
              ],
              selectedValue: selectedView,
              onSelected: onViewChanged,
              variant: AppSegmentedControlVariant.pill,
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogSectionTitle extends StatelessWidget {
  const _CatalogSectionTitle({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(title, style: AppTextStyles.sectionTitle),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption,
          ),
        ),
      ],
    );
  }
}

class _TypographySpecimen extends StatelessWidget {
  const _TypographySpecimen({
    required this.role,
    required this.sample,
    required this.style,
  });

  final String role;
  final String sample;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(role, style: AppTextStyles.labelSmall),
          ),
          Expanded(child: Text(sample, style: style)),
        ],
      ),
    );
  }
}

class _SpacingSpecimens extends StatelessWidget {
  const _SpacingSpecimens();

  @override
  Widget build(BuildContext context) {
    const spacings = <(String, double)>[
      ('XS', AppSpacing.xs),
      ('SM', AppSpacing.sm),
      ('MD', AppSpacing.md),
      ('LG', AppSpacing.lg),
      ('XL', AppSpacing.xl),
      ('XXL', AppSpacing.xxl),
      ('Screen', AppSpacing.screenX),
      ('Section', AppSpacing.xxl),
    ];

    return Column(
      children: <Widget>[
        for (final (label, value) in spacings)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: Text(
                    '$label  ${value.toInt()}',
                    style: AppTextStyles.labelSmall,
                  ),
                ),
                Container(
                  width: value * 3,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.actionPrimary,
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _IconSpecimens extends StatelessWidget {
  const _IconSpecimens();

  @override
  Widget build(BuildContext context) {
    const icons = <AppIconAsset>[
      AppIconAsset.navHome,
      AppIconAsset.memo,
      AppIconAsset.search,
      AppIconAsset.check,
      AppIconAsset.edit,
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        for (final icon in icons)
          Column(
            children: <Widget>[
              AppIcon(icon, size: 28, color: AppColors.textPrimary),
              const SizedBox(height: AppSpacing.sm),
              AppIcon(icon, size: 28, color: AppColors.actionPrimary),
            ],
          ),
      ],
    );
  }
}

class _ScreenLauncher extends StatelessWidget {
  const _ScreenLauncher({required this.onOpenScreen});

  final ValueChanged<int> onOpenScreen;

  static const screens = <_ReviewScreen>[
    _ReviewScreen(
      screen: 0,
      title: '온보딩 시작',
      coverage: '브랜드, 대형 제목, 본문, 주요 버튼',
      icon: AppIconAsset.photoUpload,
    ),
    _ReviewScreen(
      screen: 13,
      title: '홈',
      coverage: '기본 위계, 카드, 섹션, 하단 내비게이션',
      icon: AppIconAsset.navHome,
    ),
    _ReviewScreen(
      screen: 14,
      title: '히스토리',
      coverage: '기록 흐름, 칩, 데이터 카드',
      icon: AppIconAsset.calendar,
    ),
    _ReviewScreen(
      screen: 15,
      title: '탐색',
      coverage: '세그먼트, 콘텐츠 카드, 이미지 타일',
      icon: AppIconAsset.navExplore,
    ),
    _ReviewScreen(
      screen: 16,
      title: '마이',
      coverage: '리스트 행, 배지, 설정 요소',
      icon: AppIconAsset.navProfile,
    ),
    _ReviewScreen(
      screen: 40,
      title: '취향 카드 공유',
      coverage: '긴 문장, 이미지, 3열 액션 카드',
      icon: AppIconAsset.edit,
    ),
    _ReviewScreen(
      screen: 43,
      title: '기록 질문',
      coverage: '질문 위계, 선택 상태, 진행 버튼',
      icon: AppIconAsset.memo,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        AppSpacing.lg,
        AppSpacing.screenX,
        AppSpacing.massive,
      ),
      children: <Widget>[
        const Text('대표 화면 검수', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Text('선택하면 현재 앱의 실제 화면이 전체 크기로 열립니다.', style: AppTextStyles.body),
        const SizedBox(height: AppSpacing.lg),
        const _ViewportBaseline(),
        const SizedBox(height: AppSpacing.lg),
        for (var index = 0; index < screens.length; index++)
          AppListRow(
            title: '${screens[index].screen}  ${screens[index].title}',
            subtitle: screens[index].coverage,
            leadingIcon: screens[index].icon,
            showDivider: index != screens.length - 1,
            onPressed: () => onOpenScreen(screens[index].screen),
          ),
      ],
    );
  }
}

class _ViewportBaseline extends StatelessWidget {
  const _ViewportBaseline();

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      variant: AppSurfaceVariant.tinted,
      borderRadius: AppRadii.control,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: <Widget>[
          const AppIcon(
            AppIconAsset.search,
            size: 24,
            color: AppColors.actionPrimary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Galaxy S26  411 × 891\n'
              'iPhone 17  402 × 874',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewScreen {
  const _ReviewScreen({
    required this.screen,
    required this.title,
    required this.coverage,
    required this.icon,
  });

  final int screen;
  final String title;
  final String coverage;
  final AppIconAsset icon;
}
