import 'dart:async';

import '../../features/auth/data/social_auth_service.dart';
import '../../features/catalog/data/catalog_search_gateway.dart';
import '../../features/editorial/data/editorial_article_gateway.dart';
import '../../features/home/data/next_drink_guides.dart';
import '../../features/preferences/data/preference_history_content.dart';
import '../../features/home/data/taste_letters.dart';
import '../../features/onboarding/data/sensory_questionnaire_data.dart';
import '../../features/profile/data/account_completion_gateway.dart';
import '../../features/profile/data/account_deletion_gateway.dart';
import '../../features/profile/data/liked_cards_gateway.dart';
import '../../features/profile/data/marketing_consent_gateway.dart';
import '../../features/profile/data/profile_preferences_gateway.dart';
import '../../features/profile/data/profile_summary.dart';
import '../../features/profile/data/support_inquiry_gateway.dart';
import '../../features/records/data/record_note_gateway.dart';
import '../../features/taste_card/data/taste_card_gateway.dart';
import '../../features/taste_fit/data/label_photo_picker.dart';
import '../../features/taste_fit/data/taste_fit_gateway.dart';

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
    this.profileSummaryLoader,
    this.likedCards,
    this.recordNote,
    this.supportInquiry,
    this.marketingConsent,
    this.accountCompletion,
    this.accountDeletion,
    this.editorialArticle,
    this.catalogSearch,
    this.tasteCard,
    this.tasteFit,
    this.tasteLetters,
    this.labelPhotoPicker,
    this.nextDrinkGuides,
    this.preferenceHistory,
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
  final ProfileSummaryLoader? profileSummaryLoader;
  final LikedCardsGateway? likedCards;
  final RecordNoteGateway? recordNote;
  final SupportInquiryGateway? supportInquiry;
  final MarketingConsentGateway? marketingConsent;
  final AccountCompletionGateway? accountCompletion;
  final AccountDeletionGateway? accountDeletion;
  final EditorialArticleGateway? editorialArticle;
  final CatalogSearchGateway? catalogSearch;
  final TasteCardGateway? tasteCard;
  final TasteFitGateway? tasteFit;
  final TasteLettersGateway? tasteLetters;

  /// `null` uses the device camera and gallery.
  final LabelPhotoPicker? labelPhotoPicker;
  final NextDrinkGuidesGateway? nextDrinkGuides;
  final PreferenceHistoryGateway? preferenceHistory;
}
