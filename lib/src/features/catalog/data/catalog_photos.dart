import 'package:supabase_flutter/supabase_flutter.dart';

/// The public bucket that holds one representative photo per product.
const catalogImageBucket = 'alcohol-product-images';

/// The public URL of each product's representative photo, by catalog item
/// id; products without one are left out. Reads only the public media rows,
/// not the search view.
Future<Map<String, String>> catalogPhotoUrls(
  SupabaseClient client,
  Set<String> itemIds,
) async {
  if (itemIds.isEmpty) return const <String, String>{};
  final rows = await client
      .rpc('soolgyul_catalog_primary_media_rows_v1')
      .inFilter('alcohol_item_id', itemIds.toList())
      .select('alcohol_item_id,media_path');
  return <String, String>{
    for (final row in rows)
      if (row['media_path'] case final String path when path.isNotEmpty)
        row['alcohol_item_id'] as String: client.storage
            .from(catalogImageBucket)
            .getPublicUrl(path),
  };
}
