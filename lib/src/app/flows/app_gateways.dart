import 'dart:async';

import '../../features/auth/data/social_auth_service.dart';
import '../../features/catalog/data/catalog_search_gateway.dart';
import '../../features/catalog/data/discovery_events.dart';
import '../../features/editorial/data/editorial_article_gateway.dart';
import '../../features/onboarding/data/sensory_questionnaire_data.dart';
import '../../features/profile/data/account_completion_gateway.dart';
import '../../features/profile/data/account_deletion_gateway.dart';
import '../../features/profile/data/liked_cards_gateway.dart';
import '../../features/taste_fit/data/saved_drinks_gateway.dart';
import '../../features/notifications/data/notification_access.dart';
import '../../features/notifications/data/notification_prompt_memory.dart';
import '../../features/home_tour/data/home_tour_memory.dart';
import '../../features/profile/data/marketing_consent_gateway.dart';
import '../../features/profile/data/profile_preferences_gateway.dart';
import '../../features/profile/data/support_inquiry_gateway.dart';
import '../../features/records/data/record_note_gateway.dart';
import '../../features/records/data/record_price.dart';
import '../../features/taste_card/data/taste_card_gateway.dart';
import '../../features/taste_fit/data/label_photo_picker.dart';
import '../../features/taste_fit/data/taste_fit_gateway.dart';
import '../../core/analytics.dart';
import '../../core/saved_views.dart';

/// Every injectable backend boundary the app flow depends on.
///
/// A `null` gateway means the matching feature runs on local placeholders,
/// which tests and design review rely on.
class AppGateways {
  const AppGateways({
    required this.sensoryQuestionnaireLoader,
    this.isWeb = false,
    this.incomingLinks,
    this.installReferrer,
    this.socialAuth,
    this.profilePreferences,
    this.likedCards,
    this.savedDrinks,
    this.recordNote,
    this.recordPrice,
    this.supportInquiry,
    this.marketingConsent,
    this.notifications,
    this.notificationPromptMemory,
    this.homeTourMemory,
    this.accountCompletion,
    this.accountDeletion,
    this.editorialArticle,
    this.catalogSearch,
    this.discoveryEvents,
    this.tasteCard,
    this.tasteFit,
    this.labelPhotoPicker,
    this.savedViews,
    this.analytics = const NoAnalytics(),
  });

  final SensoryQuestionnaireLoader sensoryQuestionnaireLoader;

  /// The web starts with onboarding; the app starts with loading and login.
  final bool isWeb;

  /// Links opened in the app, such as a web card's claim link.
  final Stream<Uri>? incomingLinks;

  /// The Play install referrer of a fresh Android install, read once.
  final Future<String?> Function()? installReferrer;
  final SocialAuthGateway? socialAuth;
  final ProfilePreferencesGateway? profilePreferences;
  final LikedCardsGateway? likedCards;
  final SavedDrinksGateway? savedDrinks;
  final RecordNoteGateway? recordNote;
  final RecordPriceGateway? recordPrice;
  final SupportInquiryGateway? supportInquiry;
  final MarketingConsentGateway? marketingConsent;

  /// `null` until a phone is connected: nobody is asked to turn
  /// notifications on and the settings show no row for them.
  final NotificationAccess? notifications;
  final NotificationPromptMemory? notificationPromptMemory;
  final HomeTourMemory? homeTourMemory;
  final AccountCompletionGateway? accountCompletion;
  final AccountDeletionGateway? accountDeletion;
  final EditorialArticleGateway? editorialArticle;
  final CatalogSearchGateway? catalogSearch;
  final DiscoveryEventGateway? discoveryEvents;
  final TasteCardGateway? tasteCard;
  final TasteFitGateway? tasteFit;

  /// `null` uses the device camera and gallery.
  final LabelPhotoPicker? labelPhotoPicker;

  /// What the phone keeps of the signed-in account's screens between
  /// launches; `null` keeps nothing.
  final SavedViews? savedViews;

  /// Counts the steps visitors reach; counts nothing unless one is given.
  final Analytics analytics;
}
