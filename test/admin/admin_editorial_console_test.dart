import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/admin/admin_app.dart';
import 'package:soolgyul/src/admin/data/admin_editorial_gateway.dart';
import 'package:soolgyul/src/admin/admin_editorial_models.dart';
import 'package:soolgyul/src/admin/presentation/admin_article_editor.dart';
import 'package:soolgyul/src/admin/presentation/admin_dropped_file.dart';
import 'package:soolgyul/src/admin/presentation/admin_dashboard_screen.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:soolgyul/src/features/explore/presentation/widgets/explore_feed_widgets.dart';
import 'package:soolgyul/src/widgets/app_bottom_nav.dart';

void main() {
  testWidgets('signed-out administrator signs in with id and password', (
    tester,
  ) async {
    final gateway = _FakeAdminGateway(session: null, bootstrap: null);

    await tester.pumpWidget(AdminApp(gateway: gateway));
    await tester.pumpAndSettle();

    expect(find.text('술결 관리자'), findsOneWidget);
    expect(find.text('카카오로 로그인'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('admin-login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('아이디와 비밀번호를 입력해 주세요.'), findsOneWidget);
    expect(gateway.signIns, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-login-id')),
      ' Editor ',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-login-password')),
      'secret',
    );
    await tester.tap(find.byKey(const ValueKey<String>('admin-login-submit')));
    await tester.pumpAndSettle();

    expect(gateway.signIns, <(String, String)>[('Editor', 'secret')]);
    expect(
      find.byKey(const ValueKey<String>('admin-login-error')),
      findsNothing,
    );
  });

  testWidgets('wrong id or password is named on the login card', (
    tester,
  ) async {
    final gateway = _FakeAdminGateway(
      session: null,
      bootstrap: null,
      signInFailure: const AdminEditorialException(
        AdminEditorialOperation.signIn,
        AdminEditorialException.invalidCredentials,
      ),
    );

    await tester.pumpWidget(AdminApp(gateway: gateway));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-login-id')),
      'editor',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-login-password')),
      'wrong',
    );
    await tester.tap(find.byKey(const ValueKey<String>('admin-login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('아이디 또는 비밀번호가 맞지 않습니다.'), findsOneWidget);
  });

  testWidgets('authenticated account without a role is denied', (tester) async {
    final gateway = _FakeAdminGateway(session: _session, bootstrap: null);

    await tester.pumpWidget(AdminApp(gateway: gateway));
    await tester.pumpAndSettle();

    expect(find.text('관리자 권한이 없습니다'), findsOneWidget);
  });

  testWidgets('the list counts posts by status, filters them and opens one', (
    tester,
  ) async {
    final gateway = await _pumpDashboard(
      tester,
      AdminRole.admin,
      articles: <AdminEditorialArticle>[_article, _published],
    );

    expect(find.text('게시글'), findsWidgets);
    expect(_row(_article.id), findsOneWidget);
    expect(_row(_published.id), findsOneWidget);
    expect(find.text('(사진만 있는 글)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('admin-stat-발행')));
    await tester.pumpAndSettle();
    expect(_row(_article.id), findsNothing);
    expect(_row(_published.id), findsOneWidget);
    expect(find.text('발행 1개'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('admin-stat-전체')));
    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-list-search')),
      '산미',
    );
    await tester.pumpAndSettle();
    expect(_row(_article.id), findsOneWidget);
    expect(_row(_published.id), findsNothing);

    await tester.tap(_row(_article.id));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('admin-save-article')),
      findsOneWidget,
    );
    expect(gateway.savedDrafts, isEmpty);
  });

  testWidgets('drafts picked in order publish in that order', (tester) async {
    final gateway = await _pumpDashboard(
      tester,
      AdminRole.admin,
      articles: <AdminEditorialArticle>[
        _article,
        _articleWithPhotos,
        _published,
      ],
    );

    await tester.tap(find.byKey(const ValueKey<String>('admin-pick-publish')));
    await tester.pumpAndSettle();
    expect(find.text('발행할 글을 순서대로 눌러요'), findsOneWidget);
    // A published post cannot be picked.
    expect(
      find.byKey(ValueKey<String>('admin-pick-${_published.id}')),
      findsNothing,
    );

    // Picked second-then-first; the numbers show the order.
    await tester.tap(_row(_articleWithPhotos.id));
    await tester.pumpAndSettle();
    await tester.tap(_row(_article.id));
    await tester.pumpAndSettle();
    expect(find.text('2개 고름 · 누른 순서대로 발행돼요'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ValueKey<String>('admin-pick-${_articleWithPhotos.id}')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey<String>('admin-pick-${_article.id}')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('admin-publish-picked')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2개를 발행할까요?'), findsOneWidget);
    expect(
      find.textContaining('1. ${_articleWithPhotos.label}'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('admin-confirm-publish-picked')),
    );
    await tester.pumpAndSettle();

    expect(gateway.statusChanges, <(String, AdminArticleStatus)>[
      (_articleWithPhotos.id, AdminArticleStatus.published),
      (_article.id, AdminArticleStatus.published),
    ]);
    expect(find.text('2개를 고른 순서대로 발행했습니다.'), findsOneWidget);
    // Picking mode is over; rows open again.
    expect(
      find.byKey(const ValueKey<String>('admin-pick-publish')),
      findsOneWidget,
    );
  });

  testWidgets('an editor has no pick-and-publish mode', (tester) async {
    await _pumpDashboard(tester, AdminRole.editor);
    expect(
      find.byKey(const ValueKey<String>('admin-pick-publish')),
      findsNothing,
    );
  });

  testWidgets('a post can be previewed from the list', (tester) async {
    await _pumpDashboard(tester, AdminRole.admin);

    await tester.tap(
      find.byKey(ValueKey<String>('admin-preview-${_article.id}')),
    );
    await tester.pumpAndSettle();

    // The post page is the app's own article screen.
    expect(find.text('#와인'), findsOneWidget);
    expect(find.text(_article.body), findsOneWidget);

    await tester.tap(find.text('탐색 탭'));
    await tester.pumpAndSettle();

    // The explore page is the app's own feed with this post on it.
    expect(
      find.byKey(const ValueKey<String>('explore-tag-row')),
      findsOneWidget,
    );
    expect(find.byType(ExploreArticleCard), findsOneWidget);
    expect(find.byType(AppBottomNav), findsOneWidget);
  });

  testWidgets('a post without interests is previewed on the feed too', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      AdminRole.admin,
      articles: <AdminEditorialArticle>[_published],
    );

    await tester.tap(
      find.byKey(ValueKey<String>('admin-preview-${_published.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('탐색 탭'));
    await tester.pumpAndSettle();

    expect(find.byType(ExploreArticleCard), findsOneWidget);
  });

  testWidgets('admin can edit, save, and is back on the list', (tester) async {
    final gateway = await _pumpDashboard(tester, AdminRole.admin);
    await _openEditor(tester, _article.id);

    expect(
      find.byKey(const ValueKey<String>('admin-save-article')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-publish-article')),
      findsOneWidget,
    );
    expect(find.text('수정 2026.08.18'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('admin-body')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('admin-dirty')), findsNothing);

    final instagram = find.byKey(const ValueKey<String>('admin-instagram-url'));
    await tester.scrollUntilVisible(
      instagram,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(instagram, 'https://www.instagram.com/p/ABC123/');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('admin-dirty')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('admin-save-article')));
    await tester.pumpAndSettle();

    expect(gateway.savedDrafts, hasLength(1));
    final saved = gateway.savedDrafts.single;
    expect(saved.id, _article.id);
    expect(saved.body, _article.body);
    expect(saved.instagramUrl, 'https://www.instagram.com/p/ABC123/');
    expect(saved.interestKeys, <String>{'wine'});
    // Saving is done, so the list is back with the post in it.
    expect(find.text('저장했습니다.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('admin-save-article')),
      findsNothing,
    );
    expect(_row(_article.id), findsOneWidget);
  });

  testWidgets('publishing from the editor returns to the list', (tester) async {
    final gateway = await _pumpDashboard(tester, AdminRole.admin);
    await _openEditor(tester, _article.id);

    await tester.tap(
      find.byKey(const ValueKey<String>('admin-publish-article')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('admin-confirm-status')),
    );
    await tester.pumpAndSettle();

    expect(gateway.statusChanges, <(String, AdminArticleStatus)>[
      (_article.id, AdminArticleStatus.published),
    ]);
    expect(find.text('발행했습니다.'), findsOneWidget);
    expect(_row(_article.id), findsOneWidget);
  });

  testWidgets('a new post starts with the 술결 Instagram link', (tester) async {
    final gateway = await _pumpDashboard(tester, AdminRole.admin);

    await tester.tap(find.byKey(const ValueKey<String>('admin-new-article')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('admin-instagram-url')),
    );
    expect(field.controller!.text, AdminArticleEditor.defaultInstagramUrl);
    // The default alone is not a change worth warning about.
    expect(find.byKey(const ValueKey<String>('admin-dirty')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('admin-save-article')));
    await tester.pumpAndSettle();
    expect(
      gateway.savedDrafts.single.instagramUrl,
      AdminArticleEditor.defaultInstagramUrl,
    );

    // A saved post without a link keeps its empty field.
    await _openEditor(tester, _article.id);
    final existing = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('admin-instagram-url')),
    );
    expect(existing.controller!.text, '');
  });

  testWidgets('photos picked for a new post save it once and all upload', (
    tester,
  ) async {
    final picked = <AdminDroppedFile>[
      const AdminDroppedFile(name: 'one.png', bytes: <int>[1]),
      const AdminDroppedFile(name: 'two.jpg', bytes: <int>[2]),
      const AdminDroppedFile(name: 'three.webp', bytes: <int>[3]),
    ];
    final gateway = await _pumpDashboard(
      tester,
      AdminRole.admin,
      pickPhotos: () async => picked,
    );

    await tester.tap(find.byKey(const ValueKey<String>('admin-new-article')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('admin-upload-content')),
    );
    await tester.pumpAndSettle();

    // One quiet save gives the post its id; every photo then goes up.
    expect(gateway.savedDrafts, hasLength(1));
    expect(gateway.savedDrafts.single.id, isNull);
    expect(gateway.uploads.map((u) => u.fileName), <String>[
      'one.png',
      'two.jpg',
      'three.webp',
    ]);
    expect(gateway.uploads.map((u) => u.articleId).toSet(), <String>{
      _article.id,
    });
    expect(find.text('사진 3장을 올렸어요.'), findsOneWidget);
  });

  testWidgets('the body may be left empty', (tester) async {
    final gateway = await _pumpDashboard(tester, AdminRole.admin);
    await _openEditor(tester, _article.id);

    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-body')),
      '',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('admin-dirty')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('admin-save-article')));
    await tester.pumpAndSettle();

    expect(gateway.savedDrafts.single.body, '');
  });

  testWidgets('the preview beside the form follows what is typed', (
    tester,
  ) async {
    await _pumpDashboard(tester, AdminRole.admin);
    await _openEditor(tester, _article.id);

    expect(
      find.byKey(const ValueKey<String>('admin-preview-mode')),
      findsOneWidget,
    );
    expect(find.text(_article.body), findsNWidgets(2));

    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-body')),
      '바뀐 본문이에요.',
    );
    await tester.pumpAndSettle();

    // Once in the field, once in the preview.
    expect(find.text('바뀐 본문이에요.'), findsNWidgets(2));
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await _pumpDashboard(tester, AdminRole.admin);
    await _openEditor(tester, _article.id);

    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-body')),
      '다른 본문',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('admin-editor-back')));
    await tester.pumpAndSettle();

    expect(find.text('저장하지 않은 변경이 있어요'), findsOneWidget);
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('admin-save-article')),
      findsOneWidget,
    );
  });

  testWidgets('moving a photo stores the photos in the new order', (
    tester,
  ) async {
    final gateway = await _pumpDashboard(
      tester,
      AdminRole.admin,
      articles: <AdminEditorialArticle>[_articleWithPhotos],
    );
    await _openEditor(tester, _articleWithPhotos.id);

    // The first photo is the cover, so nothing is to its left.
    expect(find.text('표지'), findsOneWidget);
    final coverLeft = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('admin-media-left-cover')),
    );
    expect(coverLeft.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('admin-media-left-second')),
    );
    await tester.pumpAndSettle();

    expect(gateway.reorders, hasLength(1));
    expect(gateway.reorders.single.articleId, _articleWithPhotos.id);
    expect(gateway.reorders.single.mediaIds, <String>[
      'cover',
      'second',
      'first',
    ]);
  });

  testWidgets('an admin writes and publishes a notice, and orders FAQ', (
    tester,
  ) async {
    final gateway = await _pumpDashboard(tester, AdminRole.admin);
    await tester.tap(
      find.byKey(const ValueKey<String>('admin-nav-site-posts')),
    );
    await tester.pumpAndSettle();
    expect(find.text('서비스 점검 안내'), findsOneWidget);
    expect(find.text('탈퇴했는데 다시 쓰고 싶어요.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('admin-site-post-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-site-post-title')),
      ' 새 기능 안내 ',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-site-post-body')),
      '첫 줄\n둘째 줄',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('admin-site-post-publish')),
    );
    await tester.pumpAndSettle();
    final notice = gateway.savedSitePosts.single;
    expect(notice.id, isNull);
    expect(notice.kind, AdminSitePostKind.notice);
    expect(notice.title, '새 기능 안내');
    expect(notice.body, '첫 줄\n둘째 줄');
    expect(notice.status, AdminArticleStatus.published);

    await tester.tap(find.text('FAQ'));
    await tester.pumpAndSettle();
    expect(find.text('탈퇴했는데 다시 쓰고 싶어요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('admin-site-post-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-site-post-title')),
      '새 질문',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('admin-site-post-save-draft')),
    );
    await tester.pumpAndSettle();
    final faq = gateway.savedSitePosts.last;
    expect(faq.kind, AdminSitePostKind.faq);
    expect(faq.sortOrder, 5, reason: 'a new answer goes after the last one');
    expect(faq.status, AdminArticleStatus.draft);

    await tester.tap(find.text('탈퇴했는데 다시 쓰고 싶어요.'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('admin-site-post-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('admin-site-post-delete-confirm')),
    );
    await tester.pumpAndSettle();
    expect(gateway.deletedSitePosts, <String>[_faq.id]);
  });

  testWidgets('an editor drafts notices and only reads published ones', (
    tester,
  ) async {
    final gateway = await _pumpDashboard(tester, AdminRole.editor);
    await tester.tap(
      find.byKey(const ValueKey<String>('admin-nav-site-posts')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('admin-site-post-new')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('admin-site-post-publish')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-site-post-save-draft')),
      findsOneWidget,
    );
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('서비스 점검 안내'));
    await tester.pumpAndSettle();
    expect(find.text('발행했거나 내린 글은 ADMIN만 고칠 수 있습니다.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('admin-site-post-save-draft')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('admin-site-post-delete')),
      findsNothing,
    );
    expect(gateway.savedSitePosts, isEmpty);
  });

  testWidgets('editor cannot see publish or permanent delete actions', (
    tester,
  ) async {
    await _pumpDashboard(tester, AdminRole.editor);
    await _openEditor(tester, _article.id);

    expect(
      find.byKey(const ValueKey<String>('admin-publish-article')),
      findsNothing,
    );
    expect(find.byTooltip('초안 삭제'), findsNothing);
  });
}

Finder _row(String id) => find.byKey(ValueKey<String>('admin-article-$id'));

Future<_FakeAdminGateway> _pumpDashboard(
  WidgetTester tester,
  AdminRole role, {
  List<AdminEditorialArticle>? articles,
  AdminPhotoPicker? pickPhotos,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final bootstrap = AdminEditorialBootstrap(
    role: role,
    articles: articles ?? <AdminEditorialArticle>[_article],
  );
  final gateway = _FakeAdminGateway(session: _session, bootstrap: bootstrap);
  await tester.pumpWidget(
    MaterialApp(
      home: AdminDashboardScreen(
        gateway: gateway,
        session: _session,
        initialBootstrap: bootstrap,
        pickPhotos: pickPhotos,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return gateway;
}

Future<void> _openEditor(WidgetTester tester, String id) async {
  await tester.tap(_row(id));
  await tester.pumpAndSettle();
}

const _session = AdminAuthSession(
  userId: '10000000-0000-4000-8000-000000000001',
  email: 'admin@example.com',
);

final _article = AdminEditorialArticle(
  id: '72000000-0000-4000-8000-000000000001',
  body: '산미는 이런 느낌이에요.\n\n레몬처럼 상큼한 감각이에요.',
  status: AdminArticleStatus.draft,
  mediaAssets: const <EditorialMediaAsset>[],
  interestKeys: const <String>{'wine'},
  updatedAt: DateTime(2026, 8, 18),
);

final _published = AdminEditorialArticle(
  id: '72000000-0000-4000-8000-000000000003',
  body: '',
  status: AdminArticleStatus.published,
  publishedAt: DateTime(2026, 9, 1),
  mediaAssets: const <EditorialMediaAsset>[],
  interestKeys: const <String>{},
  updatedAt: DateTime(2026, 9, 1),
);

EditorialMediaAsset _photo(String id, int order) => EditorialMediaAsset(
  id: id,
  storageBucket: 'soolgyul-editorial',
  storageObjectPath: 'articles/$id.webp',
  sortOrder: order,
);

final _articleWithPhotos = AdminEditorialArticle(
  id: '72000000-0000-4000-8000-000000000002',
  body: '사진이 있는 글',
  status: AdminArticleStatus.draft,
  mediaAssets: <EditorialMediaAsset>[
    _photo('cover', 0),
    _photo('first', 1),
    _photo('second', 2),
  ],
  interestKeys: const <String>{},
  updatedAt: DateTime(2026, 8, 18),
);

class _FakeAdminGateway implements AdminEditorialGateway {
  _FakeAdminGateway({
    required this.session,
    required this.bootstrap,
    this.signInFailure,
  });

  final AdminAuthSession? session;
  final AdminEditorialException? signInFailure;
  final AdminEditorialBootstrap? bootstrap;
  final List<(String, String)> signIns = <(String, String)>[];
  final List<AdminArticleDraft> savedDrafts = <AdminArticleDraft>[];
  final List<(String, AdminArticleStatus)> statusChanges =
      <(String, AdminArticleStatus)>[];
  final List<({String articleId, List<String> mediaIds})> reorders =
      <({String articleId, List<String> mediaIds})>[];
  final List<AdminMediaUpload> uploads = <AdminMediaUpload>[];
  List<AdminSitePost> sitePosts = <AdminSitePost>[_notice, _faq];
  final List<AdminSitePostDraft> savedSitePosts = <AdminSitePostDraft>[];
  final List<String> deletedSitePosts = <String>[];
  final StreamController<AdminAuthSession?> _sessions =
      StreamController<AdminAuthSession?>.broadcast();

  @override
  AdminAuthSession? get currentSession => session;

  @override
  Stream<AdminAuthSession?> get sessionChanges => _sessions.stream;

  @override
  Future<void> signIn({
    required String loginId,
    required String password,
  }) async {
    if (signInFailure case final failure?) throw failure;
    signIns.add((loginId, password));
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<AdminEditorialBootstrap?> loadBootstrap() async => bootstrap;

  @override
  Future<List<AdminEditorialArticle>> fetchArticles() async =>
      bootstrap?.articles ?? const <AdminEditorialArticle>[];

  @override
  Future<String> saveArticle(AdminArticleDraft draft) async {
    savedDrafts.add(draft);
    return draft.id ?? _article.id;
  }

  @override
  Future<void> changeStatus(String articleId, AdminArticleStatus status) async {
    statusChanges.add((articleId, status));
  }

  @override
  Future<void> deleteDraft(String articleId) async {}

  @override
  Future<EditorialMediaAsset> uploadMedia(AdminMediaUpload upload) async {
    uploads.add(upload);
    return _photo('upload-${uploads.length}', uploads.length - 1);
  }

  @override
  Future<void> deleteMedia(EditorialMediaAsset media) async {}

  @override
  Future<void> reorderMedia(String articleId, List<String> mediaIds) async {
    reorders.add((articleId: articleId, mediaIds: mediaIds));
  }

  @override
  Future<List<AdminSitePost>> fetchSitePosts() async => sitePosts;

  @override
  Future<String> saveSitePost(AdminSitePostDraft draft) async {
    savedSitePosts.add(draft);
    return draft.id ?? 'new-site-post';
  }

  @override
  Future<void> deleteSitePost(String id) async {
    deletedSitePosts.add(id);
  }
}

final _notice = AdminSitePost(
  id: 'notice-1',
  kind: AdminSitePostKind.notice,
  title: '서비스 점검 안내',
  body: '11월 10일 새벽에 점검해요.',
  sortOrder: 0,
  status: AdminArticleStatus.published,
  publishedAt: DateTime.utc(2026, 11, 9),
  updatedAt: DateTime.utc(2026, 11, 9),
);

final _faq = AdminSitePost(
  id: 'faq-1',
  kind: AdminSitePostKind.faq,
  title: '탈퇴했는데 다시 쓰고 싶어요.',
  body: '탈퇴 후 30일 안에 다시 로그인하면 그대로 복구돼요.',
  sortOrder: 4,
  status: AdminArticleStatus.published,
  updatedAt: DateTime.utc(2026, 11, 9),
);
