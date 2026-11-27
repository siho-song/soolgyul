import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soolgyul/src/core/async_shown.dart';
import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// One function says whether a failure is the connection's; what is shown
// for it and whether it is reported both follow it.

void main() {
  final connection = <Object>[
    ConnectionFailure(http.ClientException('no route to host')),
    TimeoutException('no answer'),
    http.ClientException('connection closed'),
    AuthRetryableFetchException(),
  ];
  final other = <Object>[
    StateError('a field is missing'),
    const FormatException('bad row'),
    const PostgrestException(message: 'permission denied', code: '42501'),
    const ServerFailure(503, 'GET', '/rest/v1/taste_letters'),
  ];

  test('no route, a broken socket and a time limit run out are connection '
      'failures; a refusal, a bad answer and a server fault are not', () {
    for (final error in connection) {
      expect(isConnectionFailure(error), isTrue, reason: '$error');
    }
    for (final error in other) {
      expect(isConnectionFailure(error), isFalse, reason: '$error');
    }
    expect(isConnectionFailure(null), isFalse);
  });

  test('a failure a gateway reworded is read by what it was told', () {
    TasteCardGatewayException reworded(Object? cause) =>
        TasteCardGatewayException(
          TasteCardGatewayOperation.create,
          cause: cause,
        );
    expect(isConnectionFailure(reworded(connection.first)), isTrue);
    expect(isConnectionFailure(reworded(other.first)), isFalse);
    // A refusal with the server's code has no cause.
    expect(
      isConnectionFailure(
        const TasteCardGatewayException(
          TasteCardGatewayOperation.create,
          code: 'catalog_item_not_found',
        ),
      ),
      isFalse,
    );
    expect(
      isConnectionFailure(FailedSinceSignOut(TimeoutException('slow'))),
      isTrue,
    );
    expect(
      isConnectionFailure(FailedSinceSignOut(StateError('bad row'))),
      isFalse,
    );
  });

  test('the report drops exactly the connection failures, reworded or not, '
      'and keeps a server fault', () {
    for (final error in connection) {
      expect(worthReporting(error), isFalse, reason: '$error');
      expect(
        worthReporting(
          TasteCardGatewayException(
            TasteCardGatewayOperation.create,
            cause: error,
          ),
        ),
        isFalse,
        reason: 'reworded $error',
      );
    }
    for (final error in other) {
      expect(worthReporting(error), isTrue, reason: '$error');
    }
  });
}
