import 'package:supabase_flutter/supabase_flutter.dart';

import 'editorial_article.dart';

/// One photo of a post, from its `editorial_article_media_assets` row. A
/// photo shipped with the app has no address on the server.
EditorialMediaAsset editorialMediaFromRow(
  SupabaseClient client,
  Map<String, dynamic> row,
) {
  final bucket = row['storage_bucket'] as String;
  final path = row['storage_object_path'] as String;
  return EditorialMediaAsset(
    id: row['id'] as String,
    storageBucket: bucket,
    storageObjectPath: path,
    sortOrder: row['sort_order'] as int,
    publicUrl: bucket == 'flutter-assets'
        ? null
        : client.storage.from(bucket).getPublicUrl(path),
  );
}

/// A post's photos in the order they are shown, from the rows embedded in
/// its article row.
List<EditorialMediaAsset> editorialMediaFromRows(
  SupabaseClient client,
  Object? rows,
) => List<EditorialMediaAsset>.unmodifiable(
  <EditorialMediaAsset>[
    for (final row in rows as List? ?? const <dynamic>[])
      editorialMediaFromRow(client, Map<String, dynamic>.from(row as Map)),
  ]..sort((left, right) => left.sortOrder.compareTo(right.sortOrder)),
);
