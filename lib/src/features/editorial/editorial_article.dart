/// A post as readers see it: photos swiped through in order, the first one
/// being the cover, and a plain text with line breaks.
class EditorialArticle {
  const EditorialArticle({
    required this.id,
    required this.body,
    required this.publishedAt,
    required this.mediaAssets,
    required this.interestKeys,
    this.instagramUrl,
    this.savedAt,
  });

  final String id;
  final String body;
  final DateTime publishedAt;

  /// Photos in gallery order.
  final List<EditorialMediaAsset> mediaAssets;

  /// The same post on Instagram; the post page offers it when set.
  final String? instagramUrl;

  /// Interest keys (alcohol_categories.interest_key). Empty means the post is
  /// not about a particular kind and suits every reader.
  final List<String> interestKeys;
  final DateTime? savedAt;

  /// The first photo, which the feed shows for the post.
  EditorialMediaAsset? get coverMedia =>
      mediaAssets.isEmpty ? null : mediaAssets.first;

  List<EditorialMediaAsset> get gallery => mediaAssets;

  bool hasInterest(String key) => interestKeys.contains(key);

  EditorialArticle copyWithSavedAt(DateTime? value) => EditorialArticle(
    id: id,
    body: body,
    publishedAt: publishedAt,
    mediaAssets: mediaAssets,
    interestKeys: interestKeys,
    instagramUrl: instagramUrl,
    savedAt: value,
  );
}

class EditorialMediaAsset {
  const EditorialMediaAsset({
    required this.id,
    required this.storageBucket,
    required this.storageObjectPath,
    required this.sortOrder,
    this.publicUrl,
  });

  final String id;
  final String storageBucket;
  final String storageObjectPath;
  final int sortOrder;
  final String? publicUrl;

  bool get isBundledAsset => storageBucket == 'flutter-assets';
}
