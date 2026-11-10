import 'package:supabase_flutter/supabase_flutter.dart';

/// The public bucket that holds one representative photo per product.
const catalogImageBucket = 'alcohol-product-images';

/// The public URL of a product photo from the `media_path` a catalog read
/// returned; `null` for a product without a published photo.
String? catalogPhotoUrl(SupabaseClient client, Object? mediaPath) =>
    mediaPath is String && mediaPath.isNotEmpty
    ? client.storage.from(catalogImageBucket).getPublicUrl(mediaPath)
    : null;
