import '../taste_card_result.dart';
import '../../onboarding/presentation/taste_card_snapshot_view_data.dart';
import 'taste_card_wire_requests.dart';

part 'taste_card_wire_reading.dart';

const tasteCardWireSchemaVersion = 'taste-card-result-wire-v3';

/// A section never holds more paragraphs than the server writes.
const tasteCardMaxParagraphs = 12;

/// Strict reader for taste card responses: unknown fields or values fail.
abstract final class TasteCardWireParser {
  static TasteCardCreateOutcome parseCreateResponse(Object? value) {
    final object = _record(value, r'$response');
    final state = _string(object['state'], r'$response.state');
    switch (state) {
      case 'final':
        _exact(object, const <String>{'state', 'result'}, r'$response');
        return TasteCardFinalOutcome(parseResult(object['result']));
      case 'retryable':
        _exact(object, const <String>{
          'state',
          'idempotency_key',
          'attempt_ref',
          'error_code',
          'retry_after_ms',
        }, r'$response');
        return TasteCardRetryableOutcome(
          idempotencyKey: _nonEmpty(
            object['idempotency_key'],
            r'$response.idempotency_key',
          ),
          attemptRef: _nonEmpty(
            object['attempt_ref'],
            r'$response.attempt_ref',
          ),
          error: _retryError(object['error_code'], r'$response.error_code'),
          retryAfter: _durationMilliseconds(
            object['retry_after_ms'],
            r'$response.retry_after_ms',
          ),
        );
      default:
        _fail('unknown_response_state', r'$response.state');
    }
  }

  static TasteCardResult parseResult(Object? value) {
    final object = _record(value, r'$result');
    _exact(object, const <String>{
      'wire_schema_version',
      'result_id',
      'record_id',
      'snapshot_ref',
      'ownership_state',
      'alcohol_identification',
      'view',
      'conversion',
      'created_at',
    }, r'$result');
    if (_string(
          object['wire_schema_version'],
          r'$result.wire_schema_version',
        ) !=
        tasteCardWireSchemaVersion) {
      _fail('unknown_wire_schema_version', r'$result.wire_schema_version');
    }
    final resultId = _nonEmpty(object['result_id'], r'$result.result_id');
    final snapshotRef = _nonEmpty(
      object['snapshot_ref'],
      r'$result.snapshot_ref',
    );
    final ownership = switch (_string(
      object['ownership_state'],
      r'$result.ownership_state',
    )) {
      'anonymous' => TasteCardOwnership.anonymous,
      'saved' => TasteCardOwnership.saved,
      _ => _fail('unknown_ownership_state', r'$result.ownership_state'),
    };
    _parseAlcoholIdentification(
      object['alcohol_identification'],
      r'$result.alcohol_identification',
    );
    final viewData = _parseView(object['view'], r'$result.view');
    if (viewData.snapshotRef != snapshotRef) {
      _fail('snapshot_ref_mismatch', r'$result.view.snapshot_ref');
    }
    final pendingConversion = object['conversion'] == null
        ? null
        : _parseConversion(
            object['conversion'],
            r'$result.conversion',
            resultId: resultId,
            snapshotRef: snapshotRef,
          );
    if ((ownership == TasteCardOwnership.anonymous) !=
        (pendingConversion != null)) {
      _fail('conversion_ownership_mismatch', r'$result.conversion');
    }
    final recordId = _nullableNonEmpty(
      object['record_id'],
      r'$result.record_id',
    );
    // Validated for the contract; the app does not read it.
    _timestamp(object['created_at'], r'$result.created_at');
    return TasteCardResult(
      resultId: resultId,
      recordId: recordId,
      snapshotRef: snapshotRef,
      ownership: ownership,
      viewData: viewData,
      pendingConversion: pendingConversion,
    );
  }

  static TasteCardSnapshotViewData _parseView(Object? value, String path) {
    final object = _record(value, path);
    _exact(object, const <String>{
      'product',
      'bite',
      'positive',
      'burden',
      'balanced',
      'metadata',
    }, path);

    final product = _record(object['product'], '$path.product');
    _exact(product, const <String>{
      'drink_name_snapshot',
      'user_name',
      'image_reference',
      'category_label',
    }, '$path.product');

    final bite = _record(object['bite'], '$path.bite');
    // Cards made before the brief was written have no such key.
    _exact(bite, <String>{
      'nickname',
      'tags',
      'summary',
      if (bite.containsKey('brief')) 'brief',
      'guide',
    }, '$path.bite');

    final metadata = _record(object['metadata'], '$path.metadata');
    _exact(metadata, const <String>{
      'snapshot_ref',
      'schema_version',
      'engine_version',
      'generated_at',
      'generated_from_record_ref',
    }, '$path.metadata');
    if (metadata['schema_version'] != 3) {
      _fail('schema_version_required', '$path.metadata.schema_version');
    }
    // Validated for the contract; the app does not keep them.
    _nonEmpty(metadata['engine_version'], '$path.metadata.engine_version');
    _timestamp(metadata['generated_at'], '$path.metadata.generated_at');
    _nonEmpty(
      metadata['generated_from_record_ref'],
      '$path.metadata.generated_from_record_ref',
    );

    return TasteCardSnapshotViewData(
      product: TasteCardProductViewData(
        drinkNameSnapshot: _nonEmpty(
          product['drink_name_snapshot'],
          '$path.product.drink_name_snapshot',
        ),
        userName: _nullableNonEmpty(
          product['user_name'],
          '$path.product.user_name',
        ),
        imageReference: product['image_reference'] == null
            ? null
            : _parseImageReference(
                product['image_reference'],
                '$path.product.image_reference',
              ),
        categoryLabel: _nullableNonEmpty(
          product['category_label'],
          '$path.product.category_label',
        ),
      ),
      bite: TasteCardBiteViewData(
        nickname: _nonEmpty(bite['nickname'], '$path.bite.nickname'),
        tags: <TasteCardTagViewData>[
          for (final (index, tag) in _indexed(bite['tags'], '$path.bite.tags'))
            _parseTag(tag, '$path.bite.tags[$index]'),
        ],
        summary: _nonEmpty(bite['summary'], '$path.bite.summary'),
        brief: _nullableNonEmpty(bite['brief'], '$path.bite.brief'),
        guide: bite['guide'] == null
            ? null
            : parseGuide(bite['guide'], '$path.bite.guide'),
      ),
      positive: _parseParagraphs(object['positive'], '$path.positive'),
      burden: _parseParagraphs(object['burden'], '$path.burden'),
      balanced: _parseParagraphs(object['balanced'], '$path.balanced'),
      snapshotRef: _nonEmpty(
        metadata['snapshot_ref'],
        '$path.metadata.snapshot_ref',
      ),
    );
  }

  /// The 다음 술 가이드 of a card, as the home's carousel also receives it.
  static TasteCardGuideViewData parseGuide(Object? value, String path) {
    final object = _record(value, path);
    _exact(object, const <String>{
      'head',
      'picks',
      'tip',
      'levels',
      'directions',
    }, path);
    return TasteCardGuideViewData(
      head: _nonEmpty(object['head'], '$path.head'),
      picks: <TasteCardGuidePickViewData>[
        for (final (index, item) in _indexed(object['picks'], '$path.picks'))
          _parsePick(item, '$path.picks[$index]'),
      ],
      tip: _nullableNonEmpty(object['tip'], '$path.tip'),
      levels: <TasteCardGuideLevelViewData>[
        for (final (index, item) in _indexed(object['levels'], '$path.levels'))
          _parseLevel(item, '$path.levels[$index]'),
      ],
      directions: <TasteCardGuideDirectionViewData>[
        for (final (index, item) in _indexed(
          object['directions'],
          '$path.directions',
        ))
          _parseDirection(item, '$path.directions[$index]'),
      ],
    );
  }

  static TasteCardGuidePickViewData _parsePick(Object? value, String path) {
    final object = _record(value, path);
    _exact(object, const <String>{'country', 'place', 'keyword', 'note'}, path);
    return TasteCardGuidePickViewData(
      country: _nullableNonEmpty(object['country'], '$path.country'),
      place: _nullableNonEmpty(object['place'], '$path.place'),
      keyword: _nonEmpty(object['keyword'], '$path.keyword'),
      note: _nullableNonEmpty(object['note'], '$path.note'),
    );
  }

  static TasteCardGuideLevelViewData _parseLevel(Object? value, String path) {
    final object = _record(value, path);
    _exact(object, const <String>{'label', 'mark', 'range'}, path);
    final mark = object['mark'];
    if (mark is! int || mark < 1 || mark > 5) {
      _fail('level_mark_invalid', '$path.mark');
    }
    return TasteCardGuideLevelViewData(
      label: _nonEmpty(object['label'], '$path.label'),
      mark: mark,
      range: _nonEmpty(object['range'], '$path.range'),
    );
  }

  static TasteCardGuideDirectionViewData _parseDirection(
    Object? value,
    String path,
  ) {
    final object = _record(value, path);
    _exact(object, const <String>{'word', 'change'}, path);
    final change = switch (object['change']) {
      'keep' => TasteCardGuideChange.keep,
      'lower' => TasteCardGuideChange.lower,
      'higher' => TasteCardGuideChange.higher,
      _ => _fail('direction_change_invalid', '$path.change'),
    };
    return TasteCardGuideDirectionViewData(
      word: _nonEmpty(object['word'], '$path.word'),
      change: change,
    );
  }

  static TasteCardTagViewData _parseTag(Object? value, String path) {
    final object = _record(value, path);
    final explained = object.containsKey('term');
    _exact(
      object,
      explained
          ? const <String>{'label', 'kind', 'term'}
          : const <String>{'label', 'kind'},
      path,
    );
    final kind = switch (object['kind']) {
      'liked' => TasteCardTagKind.liked,
      'less' => TasteCardTagKind.less,
      'burden' => TasteCardTagKind.burden,
      'more' => TasteCardTagKind.more,
      'fine' => TasteCardTagKind.fine,
      _ => _fail('tag_kind_invalid', '$path.kind'),
    };
    return TasteCardTagViewData(
      label: _nonEmpty(object['label'], '$path.label'),
      kind: kind,
      term: explained && object['term'] != null
          ? _parseTerm(object['term'], '$path.term')
          : null,
    );
  }

  /// A served card's explanation of one word; a stored view carries none.
  static TasteCardTermViewData _parseTerm(Object? value, String path) {
    final object = _record(value, path);
    _exact(object, const <String>{
      'word',
      'label',
      'kind',
      'description',
    }, path);
    return TasteCardTermViewData(
      word: _nonEmpty(object['word'], '$path.word'),
      label: _nonEmpty(object['label'], '$path.label'),
      kind: _nonEmpty(object['kind'], '$path.kind'),
      description: _nonEmpty(object['description'], '$path.description'),
    );
  }

  static List<TasteCardParagraphViewData> _parseParagraphs(
    Object? value,
    String path,
  ) {
    final items = _indexed(value, path);
    if (items.length > tasteCardMaxParagraphs) {
      _fail('paragraph_count_invalid', path);
    }
    return <TasteCardParagraphViewData>[
      for (final (index, item) in items) _parseParagraph(item, '$path[$index]'),
    ];
  }

  static TasteCardParagraphViewData _parseParagraph(
    Object? value,
    String path,
  ) {
    final object = _record(value, path);
    final explained = object.containsKey('terms');
    _exact(
      object,
      explained
          ? const <String>{'answer', 'text', 'terms'}
          : const <String>{'answer', 'text'},
      path,
    );
    return TasteCardParagraphViewData(
      answer: _nonEmpty(object['answer'], '$path.answer'),
      text: _nonEmpty(object['text'], '$path.text'),
      terms: <TasteCardTermViewData>[
        if (explained)
          for (final (index, term) in _indexed(object['terms'], '$path.terms'))
            _parseTerm(term, '$path.terms[$index]'),
      ],
    );
  }

  static void _parseAlcoholIdentification(Object? value, String path) {
    final object = _record(value, path);
    // Drinks entered by name no longer exist; the old key and mode fail closed.
    if (object.containsKey('entered_alcohol_name')) {
      _fail('entered_alcohol_name_removed', '$path.entered_alcohol_name');
    }
    if (object['mode'] == 'direct_input') {
      _fail('direct_input_removed', '$path.mode');
    }
    _exact(object, const <String>{
      'mode',
      'alcohol_item_id',
      'alcohol_name_snapshot',
      'category',
    }, path);
    if (_string(object['mode'], '$path.mode') != 'catalog_match') {
      _fail('unknown_identification_mode', '$path.mode');
    }
    _nonEmpty(object['alcohol_item_id'], '$path.alcohol_item_id');
    _nonEmpty(object['alcohol_name_snapshot'], '$path.alcohol_name_snapshot');
    final category = object['category'];
    if (category != null &&
        !_alcoholCategories.contains(_string(category, '$path.category'))) {
      _fail('unknown_alcohol_category', '$path.category');
    }
  }

  static TasteCardPendingConversion _parseConversion(
    Object? value,
    String path, {
    required String resultId,
    required String snapshotRef,
  }) {
    final object = _record(value, path);
    _exact(object, const <String>{
      'anonymous_session_id',
      'conversion_token',
    }, path);
    return TasteCardPendingConversion(
      anonymousSessionId: _nonEmpty(
        object['anonymous_session_id'],
        '$path.anonymous_session_id',
      ),
      resultId: resultId,
      snapshotRef: snapshotRef,
      conversionToken: _nonEmpty(
        object['conversion_token'],
        '$path.conversion_token',
      ),
    );
  }

  static TasteCardImageReference _parseImageReference(
    Object? value,
    String path,
  ) {
    final object = _record(value, path);
    _exact(object, const <String>{'source', 'reference'}, path);
    final source = switch (_string(object['source'], '$path.source')) {
      'user_photo' => TasteCardImageSource.userPhoto,
      'catalog' => TasteCardImageSource.catalog,
      'category_fallback' => TasteCardImageSource.categoryFallback,
      _ => _fail('unknown_image_source', '$path.source'),
    };
    return TasteCardImageReference(
      source: source,
      reference: _nonEmpty(object['reference'], '$path.reference'),
    );
  }

  static TasteCardRetryError _retryError(Object? value, String path) {
    return switch (_string(value, path)) {
      'catalog_unavailable' => TasteCardRetryError.catalogUnavailable,
      'engine_temporarily_unavailable' =>
        TasteCardRetryError.engineTemporarilyUnavailable,
      _ => _fail('unknown_retryable_error', path),
    };
  }
}
