import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'analytics.dart';

/// The web app registered in the Firebase project. A phone reads its own
/// from the file its build carries (`google-services.json`,
/// `GoogleService-Info.plist`). These identify the project and are served
/// to every browser; they open nothing by themselves.
const _web = FirebaseOptions(
  apiKey: 'AIzaSyB5c47_lyQlZ9CHRxFWHGzAR_XJ2r65JxU',
  appId: '1:462431636006:web:1270c557ba8654682574e7',
  messagingSenderId: '462431636006',
  projectId: 'soolgyul-4dfc1',
  authDomain: 'soolgyul-4dfc1.firebaseapp.com',
  storageBucket: 'soolgyul-4dfc1.firebasestorage.app',
  measurementId: 'G-Z1MYHDWXHJ',
);

/// Google Analytics, reached through Firebase. It starts behind the first
/// screen, and when it cannot start (no network, a blocked script) the
/// counts are dropped.
class GoogleAnalytics implements Analytics {
  GoogleAnalytics._(this._ready);

  final Future<FirebaseAnalytics?> _ready;

  /// A phone build collects nothing until told to, and remembers what it
  /// was last told, so a phone is always told. A browser that is not
  /// counted never loads the script.
  static Analytics start({required bool counted}) {
    if (kIsWeb && !counted) return const NoAnalytics();
    final ready = _start(counted);
    return counted ? GoogleAnalytics._(ready) : const NoAnalytics();
  }

  static Future<FirebaseAnalytics?> _start(bool counted) async {
    try {
      await Firebase.initializeApp(options: kIsWeb ? _web : null);
      final analytics = FirebaseAnalytics.instance;
      await analytics.setAnalyticsCollectionEnabled(counted);
      return analytics;
    } catch (_) {
      return null;
    }
  }

  @override
  void screen(String name) =>
      _send((analytics) => analytics.logScreenView(screenName: name));

  @override
  void event(String name, [Map<String, Object> details = const {}]) => _send(
    (analytics) => analytics.logEvent(
      name: name,
      parameters: details.isEmpty ? null : details,
    ),
  );

  void _send(Future<void> Function(FirebaseAnalytics analytics) send) {
    unawaited(() async {
      try {
        final analytics = await _ready;
        if (analytics != null) await send(analytics);
      } catch (_) {
        // A count nobody waits for.
      }
    }());
  }
}
