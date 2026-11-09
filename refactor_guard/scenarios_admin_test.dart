// Temporary: refactor guard. Deleted with refactor_guard/ when the refactor ends.
//
// Draws every state of the admin console on fixed data at a desktop and a
// narrow tablet size, so a refactor can prove it changed no pixel. Photos are
// small PNGs made in memory and served by a fake HTTP client; nothing leaves
// the machine.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/admin/admin_app.dart';
import 'package:soolgyul/src/admin/admin_editorial_models.dart';
import 'package:soolgyul/src/admin/data/admin_editorial_gateway.dart';
import 'package:soolgyul/src/admin/presentation/admin_file_drop.dart';
import 'package:soolgyul/src/features/editorial/editorial_article.dart';

import 'snap.dart';

const _desktop = Size(1440, 900);
const _narrow = Size(768, 1024);

void main() {
  setUpAll(() => HttpOverrides.global = _PhotoHttpOverrides());

  group('sign-in', () {
    testWidgets('admin.login.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop, session: null);
      await snap(tester, 'admin.login.desktop');
    });

    testWidgets('admin.login-error.desktop', (tester) async {
      await _pumpAdmin(
        tester,
        _desktop,
        session: null,
        signInFailure: const AdminEditorialException(
          AdminEditorialOperation.signIn,
          AdminEditorialException.invalidCredentials,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('admin-login-id')),
        'editor',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('admin-login-password')),
        'wrong',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('admin-login-submit')),
      );
      await tester.pumpAndSettle();
      await snap(tester, 'admin.login-error.desktop');
    });

    testWidgets('admin.denied.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop, role: null);
      await snap(tester, 'admin.denied.desktop');
    });

    testWidgets('admin.load-error.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop, loadFails: true);
      await snap(tester, 'admin.load-error.desktop');
    });
  });

  group('list', () {
    testWidgets('admin.list.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await snap(tester, 'admin.list.desktop');
    });

    testWidgets('admin.list-published.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await tester.tap(find.byKey(const ValueKey<String>('admin-stat-발행')));
      await tester.pumpAndSettle();
      await snap(tester, 'admin.list-published.desktop');
    });

    testWidgets('admin.list-search-empty.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await tester.tap(find.byKey(const ValueKey<String>('admin-stat-철회')));
      await tester.enterText(
        find.byKey(const ValueKey<String>('admin-list-search')),
        '산미',
      );
      await tester.pumpAndSettle();
      await snap(tester, 'admin.list-search-empty.desktop');
    });

    testWidgets('admin.list-none.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop, articles: <AdminEditorialArticle>[]);
      await snap(tester, 'admin.list-none.desktop');
    });

    testWidgets('admin.list-editor-menu.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop, role: AdminRole.editor);
      await tester.tap(find.byKey(ValueKey<String>('admin-menu-${_draft.id}')));
      await tester.pumpAndSettle();
      await snap(tester, 'admin.list-editor-menu.desktop');
    });

    testWidgets('admin.list-admin-menu.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await tester.tap(
        find.byKey(ValueKey<String>('admin-menu-${_published.id}')),
      );
      await tester.pumpAndSettle();
      await snap(tester, 'admin.list-admin-menu.desktop');
    });

    testWidgets('admin.list-picking.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await tester.tap(
        find.byKey(const ValueKey<String>('admin-pick-publish')),
      );
      await tester.pumpAndSettle();
      await tester.tap(_row(_photosOnly.id));
      await tester.pumpAndSettle();
      await tester.tap(_row(_draft.id));
      await tester.pumpAndSettle();
      await snap(tester, 'admin.list-picking.desktop');

      await tester.tap(
        find.byKey(const ValueKey<String>('admin-publish-picked')),
      );
      await tester.pumpAndSettle();
      await snap(tester, 'admin.list-publish-confirm.desktop');
    });

    testWidgets('admin.list-preview.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await tester.tap(
        find.byKey(ValueKey<String>('admin-preview-${_published.id}')),
      );
      await tester.pumpAndSettle();
      await snap(tester, 'admin.list-preview.desktop');
    });

    testWidgets('admin.list.narrow', (tester) async {
      await _pumpAdmin(tester, _narrow);
      await snapScrolled(tester, 'admin.list.narrow');
    });
  });

  group('editor', () {
    testWidgets('admin.editor-new.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await tester.tap(find.byKey(const ValueKey<String>('admin-new-article')));
      await tester.pumpAndSettle();
      await snap(tester, 'admin.editor-new.desktop');
    });

    testWidgets('admin.editor-draft.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await _open(tester, _draft.id);
      await snap(tester, 'admin.editor-draft.desktop.0');
      await _scrollFormToEnd(tester);
      await snap(tester, 'admin.editor-draft.desktop.1');
    });

    testWidgets('admin.editor-draft-feed.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await _open(tester, _draft.id);
      await tester.tap(find.text('탐색 탭'));
      await tester.pumpAndSettle();
      await snap(tester, 'admin.editor-draft-feed.desktop');
    });

    testWidgets('admin.editor-publish-confirm.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await _open(tester, _draft.id);
      await tester.tap(
        find.byKey(const ValueKey<String>('admin-publish-article')),
      );
      await tester.pumpAndSettle();
      await snap(tester, 'admin.editor-publish-confirm.desktop');
    });

    testWidgets('admin.editor-withdraw-confirm.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await _open(tester, _published.id);
      await tester.tap(
        find.byKey(const ValueKey<String>('admin-withdraw-article')),
      );
      await tester.pumpAndSettle();
      await snap(tester, 'admin.editor-withdraw-confirm.desktop');
    });

    testWidgets('admin.editor-delete-confirm.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await _open(tester, _draft.id);
      await tester.tap(find.byTooltip('초안 삭제'));
      await tester.pumpAndSettle();
      await snap(tester, 'admin.editor-delete-confirm.desktop');
    });

    testWidgets('admin.editor-photo-delete-confirm.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await _open(tester, _draft.id);
      await tester.tap(
        find.byKey(const ValueKey<String>('admin-media-delete-draft-cover')),
      );
      await tester.pumpAndSettle();
      await snap(tester, 'admin.editor-photo-delete-confirm.desktop');
    });

    testWidgets('admin.editor-unsaved-confirm.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop);
      await _open(tester, _draft.id);
      await tester.enterText(
        find.byKey(const ValueKey<String>('admin-body')),
        '바뀐 첫 줄이에요.\n\n둘째 문단도 새로 썼어요.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('admin-editor-back')));
      await tester.pumpAndSettle();
      await snap(tester, 'admin.editor-unsaved-confirm.desktop');
    });

    testWidgets('admin.editor-as-editor.desktop', (tester) async {
      await _pumpAdmin(tester, _desktop, role: AdminRole.editor);
      await _open(tester, _draft.id);
      await snap(tester, 'admin.editor-as-editor.desktop');
    });

    testWidgets('admin.editor.narrow', (tester) async {
      await _pumpAdmin(tester, _narrow);
      await _open(tester, _published.id);
      await snap(tester, 'admin.editor.narrow');
      await tester.tap(
        find.byKey(const ValueKey<String>('admin-toggle-preview')),
      );
      await tester.pumpAndSettle();
      await snap(tester, 'admin.editor-preview.narrow');
    });
  });
}

// --- Driving ---

Future<_FakeAdminGateway> _pumpAdmin(
  WidgetTester tester,
  Size size, {
  AdminAuthSession? session = _session,
  AdminRole? role = AdminRole.admin,
  List<AdminEditorialArticle>? articles,
  bool loadFails = false,
  AdminEditorialException? signInFailure,
}) async {
  useViewport(tester, size);
  final gateway = _FakeAdminGateway(
    session: session,
    bootstrap: role == null
        ? null
        : AdminEditorialBootstrap(role: role, articles: articles ?? _articles),
    loadFails: loadFails,
    signInFailure: signInFailure,
  );
  await tester.pumpWidget(AdminApp(gateway: gateway));
  await tester.pumpAndSettle();
  return gateway;
}

Finder _row(String id) => find.byKey(ValueKey<String>('admin-article-$id'));

Future<void> _open(WidgetTester tester, String id) async {
  await tester.tap(_row(id));
  await tester.pumpAndSettle();
}

/// Scrolls the editor form (not the preview beside it) to its end.
Future<void> _scrollFormToEnd(WidgetTester tester) async {
  final form = find
      .descendant(
        of: find.byType(AdminFileDrop),
        matching: find.byType(Scrollable),
      )
      .evaluate()
      .map((element) => (element as StatefulElement).state as ScrollableState)
      .firstWhere((state) => state.position.axis == Axis.vertical);
  form.position.jumpTo(form.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

// --- Fixed data ---

const _session = AdminAuthSession(
  userId: '10000000-0000-4000-8000-000000000001',
  email: 'admin@example.com',
);

EditorialMediaAsset _photo(String id, int order) => EditorialMediaAsset(
  id: id,
  storageBucket: 'soolgyul-editorial',
  storageObjectPath: 'articles/$id.png',
  sortOrder: order,
  publicUrl: '$_photoHost/$id.png',
);

final _draft = AdminEditorialArticle(
  id: '72000000-0000-4000-8000-000000000001',
  body:
      '산미는 이런 느낌이에요.\n\n레몬처럼 상큼한 감각이 혀 양옆에서 먼저 올라와요. '
      '침이 고이는 정도로 산미의 세기를 가늠해 보세요.\n\n'
      '산미가 높은 와인은 기름진 음식과 잘 어울려요.',
  status: AdminArticleStatus.draft,
  mediaAssets: <EditorialMediaAsset>[
    _photo('draft-cover', 0),
    _photo('draft-second', 1),
    _photo('draft-third', 2),
  ],
  interestKeys: const <String>{'wine'},
  updatedAt: DateTime(2026, 8, 18, 10, 30),
);

final _published = AdminEditorialArticle(
  id: '72000000-0000-4000-8000-000000000002',
  body: '오늘의 위스키 한 잔\n\n바닐라와 꿀 향이 먼저 와요.',
  status: AdminArticleStatus.published,
  publishedAt: DateTime(2026, 9, 1, 9),
  mediaAssets: <EditorialMediaAsset>[
    _photo('whisky-cover', 0),
    _photo('whisky-second', 1),
  ],
  interestKeys: const <String>{'whisky', 'korean_traditional'},
  updatedAt: DateTime(2026, 9, 1, 9),
  instagramUrl: 'https://www.instagram.com/p/ABC123/',
);

final _withdrawn = AdminEditorialArticle(
  id: '72000000-0000-4000-8000-000000000003',
  body: '막걸리를 차갑게 마시는 이유',
  status: AdminArticleStatus.withdrawn,
  publishedAt: DateTime(2026, 7, 1, 9),
  mediaAssets: <EditorialMediaAsset>[_photo('makgeolli-cover', 0)],
  interestKeys: const <String>{'korean_traditional'},
  updatedAt: DateTime(2026, 7, 10, 9),
);

final _photosOnly = AdminEditorialArticle(
  id: '72000000-0000-4000-8000-000000000004',
  body: '',
  status: AdminArticleStatus.draft,
  mediaAssets: <EditorialMediaAsset>[_photo('cardnews-cover', 0)],
  interestKeys: const <String>{},
  updatedAt: DateTime(2026, 8, 1, 9),
);

final _sake = AdminEditorialArticle(
  id: '72000000-0000-4000-8000-000000000005',
  body: '사케의 정미율이 뜻하는 것',
  status: AdminArticleStatus.published,
  publishedAt: DateTime(2026, 6, 20, 9),
  mediaAssets: const <EditorialMediaAsset>[],
  interestKeys: const <String>{'sake'},
  updatedAt: DateTime(2026, 6, 20, 9),
);

final _articles = <AdminEditorialArticle>[
  _draft,
  _published,
  _withdrawn,
  _photosOnly,
  _sake,
];

// --- Fakes ---

class _FakeAdminGateway implements AdminEditorialGateway {
  _FakeAdminGateway({
    required this.session,
    required this.bootstrap,
    required this.loadFails,
    this.signInFailure,
  });

  final AdminAuthSession? session;
  final AdminEditorialBootstrap? bootstrap;
  final bool loadFails;
  final AdminEditorialException? signInFailure;
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
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<AdminEditorialBootstrap?> loadBootstrap() async {
    if (loadFails) {
      throw const AdminEditorialException(AdminEditorialOperation.load);
    }
    return bootstrap;
  }

  @override
  Future<List<AdminEditorialArticle>> fetchArticles() async =>
      bootstrap?.articles ?? const <AdminEditorialArticle>[];

  @override
  Future<String> saveArticle(AdminArticleDraft draft) async =>
      draft.id ?? _draft.id;

  @override
  Future<void> changeStatus(
    String articleId,
    AdminArticleStatus status,
  ) async {}

  @override
  Future<void> deleteDraft(String articleId) async {}

  @override
  Future<EditorialMediaAsset> uploadMedia(AdminMediaUpload upload) async =>
      _photo('upload', 0);

  @override
  Future<void> deleteMedia(EditorialMediaAsset media) async {}

  @override
  Future<void> reorderMedia(String articleId, List<String> mediaIds) async {}

  @override
  Future<List<AdminSitePost>> fetchSitePosts() async => const <AdminSitePost>[];

  @override
  Future<String> saveSitePost(AdminSitePostDraft draft) async => 'site-post';

  @override
  Future<void> deleteSitePost(String id) async {}
}

// --- Photos made in memory, served by a fake HTTP client ---

const _photoHost = 'https://photos.guard.test';

/// Top and bottom colour of each photo's vertical gradient.
const _photoColors = <String, (int, int)>{
  'draft-cover': (0xE8C27A, 0x8A3B2E),
  'draft-second': (0xF2E6C9, 0xB5683C),
  'draft-third': (0xC9D8B6, 0x4E6B3A),
  'whisky-cover': (0xF0B45A, 0x5A2A12),
  'whisky-second': (0xD9A066, 0x2E1B10),
  'makgeolli-cover': (0xF7F3EA, 0xBFB59E),
  'cardnews-cover': (0x9EC5E8, 0x2B4C7E),
};

final Map<String, Uint8List> _photoBytes = <String, Uint8List>{
  for (final MapEntry(key: id, value: (top, bottom)) in _photoColors.entries)
    '$_photoHost/$id.png': _gradientPng(120, 160, top, bottom),
};

/// An RGB PNG, `width` by `height`, fading from `top` to `bottom`.
Uint8List _gradientPng(int width, int height, int top, int bottom) {
  int channel(int rgb, int shift) => (rgb >> shift) & 0xFF;
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    final t = y / (height - 1);
    final row = <int>[
      for (final shift in const <int>[16, 8, 0])
        (channel(top, shift) +
                (channel(bottom, shift) - channel(top, shift)) * t)
            .round(),
    ];
    for (var x = 0; x < width; x++) {
      raw.add(row);
    }
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  return (BytesBuilder()
        ..add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(_pngChunk('IHDR', header.buffer.asUint8List()))
        ..add(_pngChunk('IDAT', ZLibCodec(level: 6).encode(raw.takeBytes())))
        ..add(_pngChunk('IEND', const <int>[])))
      .takeBytes();
}

List<int> _pngChunk(String type, List<int> data) {
  final typed = <int>[...type.codeUnits, ...data];
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32(typed));
  return <int>[
    ...length.buffer.asUint8List(),
    ...typed,
    ...crc.buffer.asUint8List(),
  ];
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

class _PhotoHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _PhotoHttpClient();
}

class _PhotoHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _PhotoHttpRequest(_photoBytes[url.toString()]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhotoHttpRequest implements HttpClientRequest {
  _PhotoHttpRequest(this.bytes);

  final Uint8List? bytes;

  @override
  Future<HttpClientResponse> close() async => _PhotoHttpResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhotoHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _PhotoHttpResponse(this.bytes);

  final Uint8List? bytes;

  @override
  int get statusCode => bytes == null ? HttpStatus.notFound : HttpStatus.ok;

  @override
  int get contentLength => bytes?.length ?? 0;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable(<List<int>>[?bytes]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
