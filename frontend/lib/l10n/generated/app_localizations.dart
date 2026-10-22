import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('hi'),
    Locale('id'),
    Locale('ur'),
  ];

  /// Login screen headline.
  ///
  /// In en, this message translates to:
  /// **'Ready to rule the board?'**
  String get authWelcomeTitle;

  /// Login screen subtitle.
  ///
  /// In en, this message translates to:
  /// **'Play Ludo and Snakes & Ladders with friends and players everywhere.'**
  String get authWelcomeSubtitle;

  /// Google sign-in button.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueWithGoogle;

  /// Facebook sign-in button.
  ///
  /// In en, this message translates to:
  /// **'Continue with Facebook'**
  String get authContinueWithFacebook;

  /// Apple sign-in button (Apple requires this wording).
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple'**
  String get authContinueWithApple;

  /// Guest play button.
  ///
  /// In en, this message translates to:
  /// **'Play as guest'**
  String get authPlayAsGuest;

  /// Hint under the guest button.
  ///
  /// In en, this message translates to:
  /// **'Start instantly — you can save your progress any time.'**
  String get authGuestHint;

  /// Divider between provider buttons and guest play.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOrDivider;

  /// Footer note about virtual currency.
  ///
  /// In en, this message translates to:
  /// **'Coins and diamonds are virtual and can\'t be exchanged for real money.'**
  String get authFairPlayNote;

  /// Banner after the server ended the session.
  ///
  /// In en, this message translates to:
  /// **'You were signed out. Please sign in again.'**
  String get authSessionExpiredBanner;

  /// Popup title when the account signed in on another device and this device was signed out.
  ///
  /// In en, this message translates to:
  /// **'Signed in on another device'**
  String get authSignedInElsewhereTitle;

  /// Popup body: this device was signed out because the account signed in elsewhere (one device at a time).
  ///
  /// In en, this message translates to:
  /// **'Someone signed in to your account on another device, so you\'ve been signed out here. Only one device can be signed in at a time. Sign in again to play here — the other device will be signed out.'**
  String get authSignedInElsewhereMessage;

  /// Login-screen banner after being signed out by a sign-in on another device.
  ///
  /// In en, this message translates to:
  /// **'Your account was signed in on another device.'**
  String get authSignedInElsewhereBanner;

  /// Login banner and toast after the account was deleted (Settings → Delete account).
  ///
  /// In en, this message translates to:
  /// **'Your account was deleted.'**
  String get authAccountDeleted;

  /// Delete-account confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get authDeleteAccountTitle;

  /// Delete-account dialog: introduces the list of what is deleted.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account and everything in it:'**
  String get authDeleteAccountIntro;

  /// Delete-account dialog list item.
  ///
  /// In en, this message translates to:
  /// **'Coins and diamonds'**
  String get authDeleteAccountItemWallet;

  /// Delete-account dialog list item.
  ///
  /// In en, this message translates to:
  /// **'Level, XP and missions'**
  String get authDeleteAccountItemProgress;

  /// Delete-account dialog list item.
  ///
  /// In en, this message translates to:
  /// **'Collection Room items'**
  String get authDeleteAccountItemCollection;

  /// Delete-account dialog list item.
  ///
  /// In en, this message translates to:
  /// **'Friends and friend requests'**
  String get authDeleteAccountItemFriends;

  /// Delete-account dialog: irreversible warning.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone. If you play again later, you\'ll start with a new account.'**
  String get authDeleteAccountWarning;

  /// Delete-account dialog: checkbox the user must tick before deleting.
  ///
  /// In en, this message translates to:
  /// **'I understand that my account and progress will be deleted forever.'**
  String get authDeleteAccountConfirmCheck;

  /// Delete-account dialog: destructive confirm button.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get authDeleteAccountConfirm;

  /// Delete-account dialog: inline error when the request failed (nothing was deleted).
  ///
  /// In en, this message translates to:
  /// **'Your account was not deleted. Check your connection and try again.'**
  String get authDeleteAccountFailed;

  /// Button/tooltip to change the language on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Change language'**
  String get authChangeLanguage;

  /// Provider brand name.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get authProviderGoogle;

  /// Provider brand name.
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get authProviderFacebook;

  /// Provider brand name.
  ///
  /// In en, this message translates to:
  /// **'Apple'**
  String get authProviderApple;

  /// Guest sign-in method name.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get authProviderGuest;

  /// Save Progress screen title.
  ///
  /// In en, this message translates to:
  /// **'Save your progress'**
  String get authSaveProgressTitle;

  /// Save Progress explanation.
  ///
  /// In en, this message translates to:
  /// **'Link a sign-in method so your coins, level and collection are never lost — even on a new phone.'**
  String get authSaveProgressSubtitle;

  /// Save Progress benefit bullet.
  ///
  /// In en, this message translates to:
  /// **'Keep all your coins, XP and cosmetics'**
  String get authSaveBenefitKeep;

  /// Save Progress benefit bullet.
  ///
  /// In en, this message translates to:
  /// **'Sign in on any device'**
  String get authSaveBenefitDevices;

  /// Save Progress benefit bullet: linking keeps the same account.
  ///
  /// In en, this message translates to:
  /// **'Same account — nothing is reset or moved'**
  String get authSaveBenefitSame;

  /// Link Google button.
  ///
  /// In en, this message translates to:
  /// **'Save with Google'**
  String get authSaveWithGoogle;

  /// Link Facebook button.
  ///
  /// In en, this message translates to:
  /// **'Save with Facebook'**
  String get authSaveWithFacebook;

  /// Link Apple button.
  ///
  /// In en, this message translates to:
  /// **'Save with Apple'**
  String get authSaveWithApple;

  /// No sign-in provider is configured in this build.
  ///
  /// In en, this message translates to:
  /// **'No sign-in methods are available in this build.'**
  String get authSaveNoProviders;

  /// Shown after linking succeeded.
  ///
  /// In en, this message translates to:
  /// **'Progress saved!'**
  String get authLinkSuccessTitle;

  /// Shown after linking succeeded. {provider} is a brand name like Google.
  ///
  /// In en, this message translates to:
  /// **'Your account is now linked to {provider}. Sign in with {provider} on any device to continue.'**
  String authLinkSuccessMessage(String provider);

  /// Save Progress screen when the account is already linked.
  ///
  /// In en, this message translates to:
  /// **'Your progress is saved'**
  String get authAlreadySavedTitle;

  /// Save Progress screen when the account is already linked.
  ///
  /// In en, this message translates to:
  /// **'This account is linked to a sign-in method, so your progress is safe.'**
  String get authAlreadySavedMessage;

  /// 409 identity_conflict dialog title.
  ///
  /// In en, this message translates to:
  /// **'This {provider} account is already in use'**
  String authConflictTitle(String provider);

  /// 409 identity_conflict explanation: nothing is merged.
  ///
  /// In en, this message translates to:
  /// **'That {provider} account already has its own Ludo Arena account. Nothing will be merged or moved between the two accounts.'**
  String authConflictMessage(String provider);

  /// Conflict option: sign in to the existing provider account.
  ///
  /// In en, this message translates to:
  /// **'Sign in to that account'**
  String get authConflictSignIn;

  /// Conflict note: the guest account stays on the device.
  ///
  /// In en, this message translates to:
  /// **'Your guest account stays on this device — you can switch back to it from Settings.'**
  String get authConflictGuestNote;

  /// 409 provider_already_linked dialog title.
  ///
  /// In en, this message translates to:
  /// **'Already linked'**
  String get authAlreadyLinkedTitle;

  /// 409 provider_already_linked explanation.
  ///
  /// In en, this message translates to:
  /// **'This account is already linked to a different {provider} account.'**
  String authAlreadyLinkedMessage(String provider);

  /// Sign-out confirmation title (saved account).
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get authLogoutTitle;

  /// Sign-out confirmation message (saved account).
  ///
  /// In en, this message translates to:
  /// **'You can sign back in any time with the same method.'**
  String get authLogoutMessage;

  /// Sign-out confirm button.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authLogoutConfirm;

  /// Sign-out confirmation title for an unsaved guest.
  ///
  /// In en, this message translates to:
  /// **'Sign out of your guest account?'**
  String get authGuestLogoutTitle;

  /// Button leading to Save Progress from the guest sign-out dialog.
  ///
  /// In en, this message translates to:
  /// **'Save progress first'**
  String get authSaveProgressFirst;

  /// Confirm switching back to the stored guest account.
  ///
  /// In en, this message translates to:
  /// **'Switch back to guest?'**
  String get authSwitchToGuestTitle;

  /// Explains switching back to the guest account.
  ///
  /// In en, this message translates to:
  /// **'You\'ll leave this account and continue with the guest account saved on this device.'**
  String get authSwitchToGuestMessage;

  /// Confirm button to switch to the guest account.
  ///
  /// In en, this message translates to:
  /// **'Switch to guest'**
  String get authSwitchToGuestConfirm;

  /// The stored guest account no longer exists.
  ///
  /// In en, this message translates to:
  /// **'That guest account is no longer available.'**
  String get authGuestUnavailable;

  /// Toast after signing in.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}!'**
  String authWelcomeBack(String name);

  /// Guest sign-out confirmation: nothing is lost; “Play as guest” on this device brings the same guest account back. Quote the Play as guest button label (authPlayAsGuest).
  ///
  /// In en, this message translates to:
  /// **'Your coins, level and collection stay on this device. Tap “Play as guest” to carry on where you left off. Save your progress to keep them on a new phone too.'**
  String get authGuestLogoutKeptMessage;

  /// Seat color name used in game-board accessibility labels.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get boardsColorRed;

  /// Seat color name used in game-board accessibility labels.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get boardsColorGreen;

  /// Seat color name used in game-board accessibility labels.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get boardsColorYellow;

  /// Seat color name used in game-board accessibility labels.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get boardsColorBlue;

  /// Accessibility label of the whole Ludo board.
  ///
  /// In en, this message translates to:
  /// **'Ludo board'**
  String get boardsLudoBoardLabel;

  /// Accessibility label of the whole Snakes and Ladders board.
  ///
  /// In en, this message translates to:
  /// **'Snakes and Ladders board'**
  String get boardsSnakesBoardLabel;

  /// Accessibility label of a Ludo token that has not left its base yet.
  ///
  /// In en, this message translates to:
  /// **'{color} token {number}, in base'**
  String boardsTokenInBase(String color, int number);

  /// Accessibility label of a Ludo token on the board; steps is how many squares it still has to move to finish.
  ///
  /// In en, this message translates to:
  /// **'{color} token {number}, {steps, plural, =1{1 square from home} other{{steps} squares from home}}'**
  String boardsTokenStepsFromHome(String color, int number, int steps);

  /// Accessibility label of a Ludo token that reached home.
  ///
  /// In en, this message translates to:
  /// **'{color} token {number}, finished'**
  String boardsTokenHome(String color, int number);

  /// Appended to a token's accessibility label when the player may move it now.
  ///
  /// In en, this message translates to:
  /// **'can move'**
  String get boardsTokenCanMove;

  /// Accessibility tap hint for a movable token (read as 'Double tap to move this token').
  ///
  /// In en, this message translates to:
  /// **'move this token'**
  String get boardsTokenMoveHint;

  /// Appended to a token's accessibility label when it belongs to the player whose turn it is.
  ///
  /// In en, this message translates to:
  /// **'current turn'**
  String get boardsCurrentTurn;

  /// Accessibility label of a Snakes and Ladders token.
  ///
  /// In en, this message translates to:
  /// **'{color} token on square {square}'**
  String boardsSnakesTokenOnSquare(String color, int square);

  /// Accessibility label of a Snakes and Ladders token that is not on the board yet.
  ///
  /// In en, this message translates to:
  /// **'{color} token at the start'**
  String boardsSnakesTokenAtStart(String color);

  /// Accessibility label of the dice with its current face value.
  ///
  /// In en, this message translates to:
  /// **'Dice showing {value}'**
  String boardsDiceShowing(int value);

  /// Accessibility label of the dice while it is tumbling.
  ///
  /// In en, this message translates to:
  /// **'Dice rolling'**
  String get boardsDiceRolling;

  /// Accessibility tap hint for the dice when the player may roll (read as 'Double tap to roll the dice').
  ///
  /// In en, this message translates to:
  /// **'roll the dice'**
  String get boardsDiceRollHint;

  /// Accessibility label of the victory celebration animation.
  ///
  /// In en, this message translates to:
  /// **'Victory celebration'**
  String get boardsVictoryCelebration;

  /// Accessibility label of the level-up burst animation.
  ///
  /// In en, this message translates to:
  /// **'Level up'**
  String get boardsLevelUp;

  /// Shop category pill: coin packs bought with real money (Google Play / App Store).
  ///
  /// In en, this message translates to:
  /// **'Coins'**
  String get coinsCategory;

  /// Header card title of the Shop's Coins category.
  ///
  /// In en, this message translates to:
  /// **'Coin packs'**
  String get coinsHeroTitle;

  /// Header card text of the Shop's Coins category.
  ///
  /// In en, this message translates to:
  /// **'More coins for more matches. Every pack comes with bonus diamonds.'**
  String get coinsHeroSubtitle;

  /// Name/label of the smallest coin pack.
  ///
  /// In en, this message translates to:
  /// **'Starter'**
  String get coinsPackStarter;

  /// Name/label of the coin pack most players buy (highlighted).
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get coinsPackPopular;

  /// Name/label of the third coin pack.
  ///
  /// In en, this message translates to:
  /// **'Great Value'**
  String get coinsPackGreatValue;

  /// Name/label of the largest coin pack, the best price per coin (highlighted).
  ///
  /// In en, this message translates to:
  /// **'Best Value'**
  String get coinsPackBestValue;

  /// Coins in a pack, e.g. '50 Lakh coins' (amount already formatted).
  ///
  /// In en, this message translates to:
  /// **'{amount} coins'**
  String coinsPackCoins(String amount);

  /// Bonus diamonds in a coin pack, e.g. '+5 diamonds' (amount already formatted).
  ///
  /// In en, this message translates to:
  /// **'+{amount} diamonds'**
  String coinsPackDiamonds(String amount);

  /// Screen reader label of a coin pack card.
  ///
  /// In en, this message translates to:
  /// **'{pack}: {coins} coins and {diamonds} diamonds for {price}'**
  String coinsPackSemantics(
    String pack,
    String coins,
    String diamonds,
    String price,
  );

  /// Screen reader label of a coin pack's buy button (the button shows the price).
  ///
  /// In en, this message translates to:
  /// **'Buy for {price}'**
  String coinsBuyFor(String price);

  /// Dialog title after the server verified a coin pack purchase and added it to the wallet.
  ///
  /// In en, this message translates to:
  /// **'Coins added!'**
  String get coinsGrantedTitle;

  /// Dialog text after a coin pack purchase (amounts already formatted).
  ///
  /// In en, this message translates to:
  /// **'{coins} coins and {diamonds} diamonds are now in your wallet.'**
  String coinsGrantedMessage(String coins, String diamonds);

  /// Toast when Google Play / the App Store reports a failed purchase.
  ///
  /// In en, this message translates to:
  /// **'The purchase didn\'t go through. Please try again.'**
  String get coinsBuyFailed;

  /// Toast when a paid coin pack could not be delivered yet (server unreachable); it is retried automatically, at the latest on the next app start.
  ///
  /// In en, this message translates to:
  /// **'Your purchase is safe. We\'ll add the coins as soon as we can reach the game server.'**
  String get coinsDelayed;

  /// Note under the coin packs: virtual currency, no cash value, payments processed by the platform store.
  ///
  /// In en, this message translates to:
  /// **'Coins and diamonds are virtual items with no cash value. Payments are handled by Google Play or the App Store.'**
  String get coinsNote;

  /// Error iap_unavailable, or the store / product is not available on this device yet.
  ///
  /// In en, this message translates to:
  /// **'This pack isn\'t available yet.'**
  String get coinsErrorUnavailable;

  /// Error purchase_invalid: the store did not confirm the purchase (not paid, cancelled, another account's purchase, unknown pack).
  ///
  /// In en, this message translates to:
  /// **'This purchase couldn\'t be verified, so nothing was added.'**
  String get coinsErrorInvalid;

  /// Error purchase_pending / pending store purchase: the payment has not completed yet.
  ///
  /// In en, this message translates to:
  /// **'Your payment is pending. The coins arrive as soon as it completes.'**
  String get coinsErrorPending;

  /// Error store_unreachable: Google Play / the App Store did not answer while the server verified a paid purchase; it stays pending and is delivered automatically later.
  ///
  /// In en, this message translates to:
  /// **'The store couldn\'t be reached. Your purchase is safe and will be added automatically.'**
  String get coinsErrorStoreUnreachable;

  /// Generic confirmation button.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Generic cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Retry a failed action.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Close a sheet/dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Proceed to the next step.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// Navigate back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Finish an action.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// Save changes.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Postpone (e.g. an update prompt).
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get commonLater;

  /// Shown while content loads.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// Copy to clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// Toast after copying to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get commonCopied;

  /// Open the system share sheet.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// Affirmative answer.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// Negative answer.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// Generic error state title.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get commonSomethingWentWrong;

  /// Generic empty state title.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get commonNothingHereYet;

  /// Label for the current user in player lists.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get commonYou;

  /// Account type: guest (not saved to a sign-in provider).
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get commonGuest;

  /// Virtual soft currency name.
  ///
  /// In en, this message translates to:
  /// **'Coins'**
  String get commonCoins;

  /// Virtual premium currency name.
  ///
  /// In en, this message translates to:
  /// **'Diamonds'**
  String get commonDiamonds;

  /// Player level, long form.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String commonLevel(int level);

  /// Player level in compact badges.
  ///
  /// In en, this message translates to:
  /// **'Lv {level}'**
  String commonLevelShort(int level);

  /// XP progress within the current level.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total} XP'**
  String commonXpProgress(String current, String total);

  /// Realtime connection status: connected.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get commonConnectionConnected;

  /// Realtime connection status: first connection attempt.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get commonConnectionConnecting;

  /// Realtime connection status: connection lost, retrying.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get commonConnectionReconnecting;

  /// Realtime connection status: offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get commonConnectionOffline;

  /// Close code 4409: a newer connection of the same signed-in session took over (e.g. the app opened twice). A sign-in on another device is shown separately (authSignedInElsewhere*).
  ///
  /// In en, this message translates to:
  /// **'This game is open somewhere else'**
  String get commonConnectionReplaced;

  /// Button to reconnect (play here) after the connection was taken over or lost.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get commonReconnect;

  /// Compact seconds countdown.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String commonSecondsShort(int seconds);

  /// Game name: Ludo.
  ///
  /// In en, this message translates to:
  /// **'Ludo'**
  String get commonGameLudo;

  /// Game name: Snakes and Ladders.
  ///
  /// In en, this message translates to:
  /// **'Snakes & Ladders'**
  String get commonGameSnakesLadders;

  /// Ludo rules variant: classic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get commonVariantClassic;

  /// Ludo rules variant: quick.
  ///
  /// In en, this message translates to:
  /// **'Quick'**
  String get commonVariantQuick;

  /// Number of players / seats.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 player} other{{count} players}}'**
  String commonPlayerCount(int count);

  /// Shown when an action failed because the device is offline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Check your connection and try again.'**
  String get commonOfflineHint;

  /// Coin entry fee for a match.
  ///
  /// In en, this message translates to:
  /// **'Entry {amount}'**
  String commonEntryFee(String amount);

  /// No entry fee (e.g. practice).
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get commonFree;

  /// Title of the full-screen overlay that blocks the app while the internet / game-server connection is down (after sign-in, on any screen, including a match).
  ///
  /// In en, this message translates to:
  /// **'Connection lost'**
  String get connectionLostTitle;

  /// Body of the connection-lost overlay: the app reconnects by itself and unblocks when the connection is back.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting… You can continue as soon as you\'re back online.'**
  String get connectionLostMessage;

  /// Extra line on the connection-lost overlay during a match: the server keeps the match going and plays timed-out turns for the player.
  ///
  /// In en, this message translates to:
  /// **'Your match keeps running. Missed turns are played for you automatically.'**
  String get connectionLostMatchHint;

  /// Button on the connection-lost overlay: retry the connection immediately instead of waiting for the next automatic attempt.
  ///
  /// In en, this message translates to:
  /// **'Try now'**
  String get connectionLostRetryNow;

  /// Screen-reader announcement when the connection is restored and the connection-lost overlay disappears.
  ///
  /// In en, this message translates to:
  /// **'Back online'**
  String get connectionBackOnline;

  /// Application name shown in the OS task switcher and splash.
  ///
  /// In en, this message translates to:
  /// **'Ludo Arena'**
  String get appTitle;

  /// The language's own name, in its own script.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageNameNative;

  /// Display name of the cosmetic item `dice_classic` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Classic Ivory'**
  String get cosmeticDiceClassic;

  /// Display name of the cosmetic item `dice_neon` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Neon Pulse'**
  String get cosmeticDiceNeon;

  /// Display name of the cosmetic item `dice_golden` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Royal Gold'**
  String get cosmeticDiceGolden;

  /// Display name of the cosmetic item `dice_autumn` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Autumn Leaf'**
  String get cosmeticDiceAutumn;

  /// Display name of the cosmetic item `token_classic` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Classic Pawn'**
  String get cosmeticTokenClassic;

  /// Display name of the cosmetic item `token_gem` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Gemstone'**
  String get cosmeticTokenGem;

  /// Display name of the cosmetic item `token_royal` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Royal Pawn'**
  String get cosmeticTokenRoyal;

  /// Display name of the cosmetic item `token_crown` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Crown Piece'**
  String get cosmeticTokenCrown;

  /// Display name of the cosmetic item `ludo_board_classic` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get cosmeticLudoBoardClassic;

  /// Display name of the cosmetic item `ludo_board_midnight` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Midnight Marble'**
  String get cosmeticLudoBoardMidnight;

  /// Display name of the cosmetic item `ludo_board_royal` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Royal Court'**
  String get cosmeticLudoBoardRoyal;

  /// Display name of the cosmetic item `snakes_board_classic` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Classic Meadow'**
  String get cosmeticSnakesBoardClassic;

  /// Display name of the cosmetic item `snakes_board_jungle` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Jungle Temple'**
  String get cosmeticSnakesBoardJungle;

  /// Display name of the cosmetic item `snakes_board_candy` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Candy Land'**
  String get cosmeticSnakesBoardCandy;

  /// Display name of the cosmetic item `trail_none` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'No Trail'**
  String get cosmeticTrailNone;

  /// Display name of the cosmetic item `trail_sparkle` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Sparkle'**
  String get cosmeticTrailSparkle;

  /// Display name of the cosmetic item `trail_comet` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Comet'**
  String get cosmeticTrailComet;

  /// Display name of the cosmetic item `victory_confetti` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Confetti'**
  String get cosmeticVictoryConfetti;

  /// Display name of the cosmetic item `victory_fireworks` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Fireworks'**
  String get cosmeticVictoryFireworks;

  /// Display name of the cosmetic item `victory_crown` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Golden Crown'**
  String get cosmeticVictoryCrown;

  /// Display name of the cosmetic item `frame_none` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'No Frame'**
  String get cosmeticFrameNone;

  /// Display name of the cosmetic item `frame_bronze` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Bronze Ring'**
  String get cosmeticFrameBronze;

  /// Display name of the cosmetic item `frame_silver` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Silver Laurel'**
  String get cosmeticFrameSilver;

  /// Display name of the cosmetic item `frame_gold` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Gold Laurel'**
  String get cosmeticFrameGold;

  /// Display name of the cosmetic item `frame_royal` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Royal Crest'**
  String get cosmeticFrameRoyal;

  /// Display name of the cosmetic item `title_rookie` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Rookie'**
  String get cosmeticTitleRookie;

  /// Display name of the cosmetic item `title_strategist` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Strategist'**
  String get cosmeticTitleStrategist;

  /// Display name of the cosmetic item `title_dice_master` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Dice Master'**
  String get cosmeticTitleDiceMaster;

  /// Display name of the cosmetic item `title_royal` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Royal Highness'**
  String get cosmeticTitleRoyal;

  /// Display name of the cosmetic item `title_weekly_champion` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Weekly Champion'**
  String get cosmeticTitleWeeklyChampion;

  /// Display name of the cosmetic item `badge_first_win` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'First Victory'**
  String get cosmeticBadgeFirstWin;

  /// Display name of the cosmetic item `badge_friendly` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Good Company'**
  String get cosmeticBadgeFriendly;

  /// Display name of the cosmetic item `emote_wave` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Wave'**
  String get cosmeticEmoteWave;

  /// Display name of the cosmetic item `emote_thumbs` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Thumbs Up'**
  String get cosmeticEmoteThumbs;

  /// Display name of the cosmetic item `emote_laugh` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Laugh'**
  String get cosmeticEmoteLaugh;

  /// Display name of the cosmetic item `emote_wow` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Wow'**
  String get cosmeticEmoteWow;

  /// Display name of the cosmetic item `emote_crown` (Collection Room, chips, rewards).
  ///
  /// In en, this message translates to:
  /// **'Crown'**
  String get cosmeticEmoteCrown;

  /// Cosmetic rarity tier `common`.
  ///
  /// In en, this message translates to:
  /// **'Common'**
  String get cosmeticRarityCommon;

  /// Cosmetic rarity tier `rare`.
  ///
  /// In en, this message translates to:
  /// **'Rare'**
  String get cosmeticRarityRare;

  /// Cosmetic rarity tier `epic`.
  ///
  /// In en, this message translates to:
  /// **'Epic'**
  String get cosmeticRarityEpic;

  /// Cosmetic rarity tier `legendary`.
  ///
  /// In en, this message translates to:
  /// **'Legendary'**
  String get cosmeticRarityLegendary;

  /// Cosmetic category / equip slot `dice`.
  ///
  /// In en, this message translates to:
  /// **'Dice'**
  String get cosmeticKindDice;

  /// Cosmetic category / equip slot `token`.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get cosmeticKindToken;

  /// Cosmetic category / equip slot `ludo_board`.
  ///
  /// In en, this message translates to:
  /// **'Ludo board'**
  String get cosmeticKindLudoBoard;

  /// Cosmetic category / equip slot `snakes_board`.
  ///
  /// In en, this message translates to:
  /// **'Snakes & Ladders board'**
  String get cosmeticKindSnakesBoard;

  /// Cosmetic category / equip slot `frame`.
  ///
  /// In en, this message translates to:
  /// **'Avatar frame'**
  String get cosmeticKindFrame;

  /// Cosmetic category / equip slot `title`.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get cosmeticKindTitle;

  /// Cosmetic category / equip slot `badge`.
  ///
  /// In en, this message translates to:
  /// **'Badge'**
  String get cosmeticKindBadge;

  /// Cosmetic category / equip slot `emote`.
  ///
  /// In en, this message translates to:
  /// **'Emote'**
  String get cosmeticKindEmote;

  /// Cosmetic category / equip slot `victory`.
  ///
  /// In en, this message translates to:
  /// **'Victory celebration'**
  String get cosmeticKindVictory;

  /// Cosmetic category / equip slot `trail`.
  ///
  /// In en, this message translates to:
  /// **'Token trail'**
  String get cosmeticKindTrail;

  /// Fallback for unknown error codes.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// Error code bad_request (malformed request).
  ///
  /// In en, this message translates to:
  /// **'That request couldn\'t be processed.'**
  String get errorBadRequest;

  /// Error code unknown_type (server does not know the message type).
  ///
  /// In en, this message translates to:
  /// **'This action isn\'t supported. Please update the app.'**
  String get errorUnknownType;

  /// Error code rate_limited.
  ///
  /// In en, this message translates to:
  /// **'You\'re going a bit fast! Wait a moment and try again.'**
  String get errorRateLimited;

  /// Error code unauthorized.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get errorUnauthorized;

  /// Error code update_required.
  ///
  /// In en, this message translates to:
  /// **'A newer version of the app is required.'**
  String get errorUpdateRequired;

  /// Error code maintenance.
  ///
  /// In en, this message translates to:
  /// **'The game servers are under maintenance. Please try again soon.'**
  String get errorMaintenance;

  /// Error code not_in_room.
  ///
  /// In en, this message translates to:
  /// **'You\'re not in this room anymore.'**
  String get errorNotInRoom;

  /// Error code room_not_found.
  ///
  /// In en, this message translates to:
  /// **'This room doesn\'t exist anymore.'**
  String get errorRoomNotFound;

  /// Error code room_full.
  ///
  /// In en, this message translates to:
  /// **'This room is already full.'**
  String get errorRoomFull;

  /// Error code room_in_progress.
  ///
  /// In en, this message translates to:
  /// **'This game has already started.'**
  String get errorRoomInProgress;

  /// Error code room_closed.
  ///
  /// In en, this message translates to:
  /// **'This room has been closed.'**
  String get errorRoomClosed;

  /// Error code already_in_room.
  ///
  /// In en, this message translates to:
  /// **'You\'re already in a room. Leave it first to join another.'**
  String get errorAlreadyInRoom;

  /// Error code not_host.
  ///
  /// In en, this message translates to:
  /// **'Only the host can do that.'**
  String get errorNotHost;

  /// Error code not_enough_players.
  ///
  /// In en, this message translates to:
  /// **'At least 2 players are needed to start.'**
  String get errorNotEnoughPlayers;

  /// Error code players_not_ready.
  ///
  /// In en, this message translates to:
  /// **'Waiting for all players to be ready.'**
  String get errorPlayersNotReady;

  /// Error code not_your_turn.
  ///
  /// In en, this message translates to:
  /// **'It\'s not your turn yet.'**
  String get errorNotYourTurn;

  /// Error code invalid_phase.
  ///
  /// In en, this message translates to:
  /// **'You can\'t do that right now.'**
  String get errorInvalidPhase;

  /// Error code illegal_move.
  ///
  /// In en, this message translates to:
  /// **'That move isn\'t allowed.'**
  String get errorIllegalMove;

  /// Error code stale_state (the action used an outdated turn).
  ///
  /// In en, this message translates to:
  /// **'The board just changed. Try again.'**
  String get errorStaleState;

  /// Error code insufficient_funds.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have enough coins for this.'**
  String get errorInsufficientFunds;

  /// Error code invalid_code.
  ///
  /// In en, this message translates to:
  /// **'That room code isn\'t valid. Check it and try again.'**
  String get errorInvalidCode;

  /// Error code rematch_closed.
  ///
  /// In en, this message translates to:
  /// **'The rematch window has closed.'**
  String get errorRematchClosed;

  /// Error code not_friends.
  ///
  /// In en, this message translates to:
  /// **'You can only invite friends.'**
  String get errorNotFriends;

  /// Error code item_not_owned.
  ///
  /// In en, this message translates to:
  /// **'You don\'t own this item yet.'**
  String get errorItemNotOwned;

  /// Error code bots_unavailable.
  ///
  /// In en, this message translates to:
  /// **'No computer players are available right now. Try again in a moment.'**
  String get errorBotsUnavailable;

  /// Error code bots_not_allowed.
  ///
  /// In en, this message translates to:
  /// **'Computer players aren\'t allowed in this room.'**
  String get errorBotsNotAllowed;

  /// Error code internal (server error).
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on our side. Please try again.'**
  String get errorInternal;

  /// Error code client_version_required.
  ///
  /// In en, this message translates to:
  /// **'The app couldn\'t identify its version. Please update or reinstall it.'**
  String get errorClientVersionRequired;

  /// Error code environment_mismatch.
  ///
  /// In en, this message translates to:
  /// **'This app build is connected to the wrong server.'**
  String get errorEnvironmentMismatch;

  /// Error code invalid_credential (provider token rejected).
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Please try again.'**
  String get errorInvalidCredential;

  /// Error code refresh_reused (session revoked).
  ///
  /// In en, this message translates to:
  /// **'For your security, you\'ve been signed out. Please sign in again.'**
  String get errorRefreshReused;

  /// Error code session_replaced (the account signed in on another device).
  ///
  /// In en, this message translates to:
  /// **'Your account was signed in on another device. Please sign in again.'**
  String get errorSessionReplaced;

  /// Error code forbidden.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to do that.'**
  String get errorForbidden;

  /// Error code not_found.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find what you were looking for.'**
  String get errorNotFound;

  /// Error code identity_conflict (provider identity already has its own account).
  ///
  /// In en, this message translates to:
  /// **'This sign-in account already belongs to a different player profile.'**
  String get errorIdentityConflict;

  /// Error code provider_already_linked.
  ///
  /// In en, this message translates to:
  /// **'Your profile already has a different account of this type linked.'**
  String get errorProviderAlreadyLinked;

  /// Error code already_owned.
  ///
  /// In en, this message translates to:
  /// **'You already own this item.'**
  String get errorAlreadyOwned;

  /// Error code already_claimed.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already claimed this reward.'**
  String get errorAlreadyClaimed;

  /// Error code already_friends.
  ///
  /// In en, this message translates to:
  /// **'You\'re already friends.'**
  String get errorAlreadyFriends;

  /// Error code not_completed.
  ///
  /// In en, this message translates to:
  /// **'Finish this mission first to claim the reward.'**
  String get errorNotCompleted;

  /// Error code item_locked.
  ///
  /// In en, this message translates to:
  /// **'This item is still locked.'**
  String get errorItemLocked;

  /// Error code assets_unavailable (picture storage unavailable).
  ///
  /// In en, this message translates to:
  /// **'Pictures can\'t be downloaded right now. Please try again later.'**
  String get errorAssetsUnavailable;

  /// Error code provider_unavailable.
  ///
  /// In en, this message translates to:
  /// **'The sign-in service is unavailable right now. Please try again later.'**
  String get errorProviderUnavailable;

  /// Client code network_error (no connectivity).
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the game service. Check your internet connection.'**
  String get errorNetwork;

  /// Client code timeout.
  ///
  /// In en, this message translates to:
  /// **'The connection timed out. Please try again.'**
  String get errorTimeout;

  /// Client code bad_response.
  ///
  /// In en, this message translates to:
  /// **'We got an unexpected response. Please try again.'**
  String get errorBadResponse;

  /// Client code cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled.'**
  String get errorCancelled;

  /// Client code not_connected (realtime connection not open).
  ///
  /// In en, this message translates to:
  /// **'You\'re not connected right now. Reconnecting…'**
  String get errorNotConnected;

  /// Rate limited with a known wait (Retry-After).
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Too many tries. Try again in 1 second.} other{Too many tries. Try again in {seconds} seconds.}}'**
  String errorRateLimitedRetry(int seconds);

  /// Error code invalid_name (display name rejected, unknown reason).
  ///
  /// In en, this message translates to:
  /// **'That name can\'t be used. Please choose another one.'**
  String get errorInvalidName;

  /// invalid_name reason too_short (fewer than 3 characters).
  ///
  /// In en, this message translates to:
  /// **'Your name needs at least 3 characters.'**
  String get errorInvalidNameTooShort;

  /// invalid_name reason too_long (more than 16 characters).
  ///
  /// In en, this message translates to:
  /// **'Your name can have at most 16 characters.'**
  String get errorInvalidNameTooLong;

  /// invalid_name reason invalid_characters (emoji, symbols, or no letter).
  ///
  /// In en, this message translates to:
  /// **'Use only letters, numbers, spaces, _ . or - (with at least one letter). No emoji or symbols.'**
  String get errorInvalidNameCharacters;

  /// invalid_name reason reserved (e.g. starts with "bot" or contains "admin").
  ///
  /// In en, this message translates to:
  /// **'That name is reserved. Please choose another one.'**
  String get errorInvalidNameReserved;

  /// invalid_name reason inappropriate (blocked word).
  ///
  /// In en, this message translates to:
  /// **'That name isn\'t allowed. Please choose a friendly one.'**
  String get errorInvalidNameInappropriate;

  /// Splash screen tagline under the logo.
  ///
  /// In en, this message translates to:
  /// **'Roll. Race. Rule.'**
  String get gateSplashTagline;

  /// Splash status while fetching the app policy.
  ///
  /// In en, this message translates to:
  /// **'Checking the game servers…'**
  String get gateStatusChecking;

  /// Splash status while restoring the session.
  ///
  /// In en, this message translates to:
  /// **'Signing you in…'**
  String get gateStatusSigningIn;

  /// Splash status while loading profile and wallet.
  ///
  /// In en, this message translates to:
  /// **'Loading your profile…'**
  String get gateStatusLoadingProfile;

  /// Button that opens the app store to update.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get gateUpdateNow;

  /// Force-update screen title.
  ///
  /// In en, this message translates to:
  /// **'Update required'**
  String get gateForceUpdateTitle;

  /// Force-update screen explanation (used when the server sends no localized message).
  ///
  /// In en, this message translates to:
  /// **'This version of Ludo Arena is no longer supported. Update to keep playing online — your coins and progress are safe.'**
  String get gateForceUpdateMessage;

  /// Label for the installed app version.
  ///
  /// In en, this message translates to:
  /// **'Installed version'**
  String get gateInstalledVersion;

  /// Label for the minimum required app version.
  ///
  /// In en, this message translates to:
  /// **'Required version'**
  String get gateRequiredVersion;

  /// Shown when an update is required but the store has no link yet.
  ///
  /// In en, this message translates to:
  /// **'Update not yet available in the store'**
  String get gateStoreNotReadyTitle;

  /// Explanation when the store update is not yet published.
  ///
  /// In en, this message translates to:
  /// **'The new version is on its way to your app store. Please check again in a little while.'**
  String get gateStoreNotReadyMessage;

  /// Button to re-check the app policy.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get gateCheckAgain;

  /// Optional update dialog title.
  ///
  /// In en, this message translates to:
  /// **'A new version is available'**
  String get gateOptionalUpdateTitle;

  /// Optional update dialog message. {version} is the latest version number.
  ///
  /// In en, this message translates to:
  /// **'Version {version} brings fixes and improvements. Update now for the smoothest games.'**
  String gateOptionalUpdateMessage(String version);

  /// Maintenance screen title.
  ///
  /// In en, this message translates to:
  /// **'We\'re polishing the boards'**
  String get gateMaintenanceTitle;

  /// Maintenance explanation (used when the server sends no localized message).
  ///
  /// In en, this message translates to:
  /// **'Ludo Arena is down for maintenance. Your coins, progress and running matches are safe — matches resume when we\'re back.'**
  String get gateMaintenanceMessage;

  /// Estimated maintenance end in local time.
  ///
  /// In en, this message translates to:
  /// **'Estimated end: {time}'**
  String gateMaintenanceEstimatedEnd(String time);

  /// Clarifies that the end time is only an estimate.
  ///
  /// In en, this message translates to:
  /// **'This is only an estimate and may change.'**
  String get gateMaintenanceEstimateNote;

  /// Tells the user the app re-checks automatically.
  ///
  /// In en, this message translates to:
  /// **'We\'ll check again automatically every 30 seconds.'**
  String get gateMaintenanceAutoCheck;

  /// Time of the last policy check.
  ///
  /// In en, this message translates to:
  /// **'Last checked at {time}'**
  String gateLastChecked(String time);

  /// Shown while a re-check runs.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get gateCheckingNow;

  /// Connection status: the game service answered.
  ///
  /// In en, this message translates to:
  /// **'Game service reachable'**
  String get gateServiceReachable;

  /// Connection status: the game service did not answer.
  ///
  /// In en, this message translates to:
  /// **'No connection to the game service'**
  String get gateServiceUnreachableShort;

  /// Title when the backend cannot be reached at startup.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the game service'**
  String get gateUnreachableTitle;

  /// Explains that online play needs a connection.
  ///
  /// In en, this message translates to:
  /// **'Ludo Arena needs an internet connection for online play. Check your Wi-Fi or mobile data and try again.'**
  String get gateUnreachableMessage;

  /// Context from the cached policy: maintenance.
  ///
  /// In en, this message translates to:
  /// **'The last status we received said the servers were under maintenance.'**
  String get gateUnreachableLastKnownMaintenance;

  /// Context from the cached policy: an update is required.
  ///
  /// In en, this message translates to:
  /// **'The last status we received said this version needs an update.'**
  String get gateUnreachableLastKnownUpdate;

  /// Title for a route that is not available in this build.
  ///
  /// In en, this message translates to:
  /// **'Not available yet'**
  String get gateNotFoundTitle;

  /// Message for a route that is not available in this build.
  ///
  /// In en, this message translates to:
  /// **'This part of Ludo Arena isn\'t available in this version yet.'**
  String get gateNotFoundMessage;

  /// Button back to the home screen.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get gateGoHome;

  /// Screen-reader label of the studio logo animation shown when the app launches (the studio's name; keep it as is in every language).
  ///
  /// In en, this message translates to:
  /// **'Sun Game Studio'**
  String get gateStudioIntroLabel;

  /// Header greeting with the display name.
  ///
  /// In en, this message translates to:
  /// **'Hi, {name}'**
  String homeGreeting(String name);

  /// Quick Play action title.
  ///
  /// In en, this message translates to:
  /// **'Quick Play'**
  String get homeQuickPlay;

  /// Quick Play configuration summary, e.g. "Ludo · Classic · 4 players".
  ///
  /// In en, this message translates to:
  /// **'{game} · {variant} · {players}'**
  String homeQuickPlayDetails(String game, String variant, String players);

  /// Private room action title.
  ///
  /// In en, this message translates to:
  /// **'Private Room'**
  String get homePrivateRoom;

  /// Private room action subtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a room for friends'**
  String get homePrivateRoomSubtitle;

  /// Join-with-code action title.
  ///
  /// In en, this message translates to:
  /// **'Join with Code'**
  String get homeJoinWithCode;

  /// Join-with-code action subtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter a room code'**
  String get homeJoinWithCodeSubtitle;

  /// Game card action: public matchmaking.
  ///
  /// In en, this message translates to:
  /// **'Play Online'**
  String get homePlayOnline;

  /// Game card action: private room.
  ///
  /// In en, this message translates to:
  /// **'Play with Friends'**
  String get homePlayWithFriends;

  /// Game card action: practice room with bots.
  ///
  /// In en, this message translates to:
  /// **'Practice vs Bots'**
  String get homePracticeVsBots;

  /// Ludo card tagline.
  ///
  /// In en, this message translates to:
  /// **'Race all four tokens home'**
  String get homeLudoTagline;

  /// Snakes & Ladders card tagline.
  ///
  /// In en, this message translates to:
  /// **'Climb ladders, dodge snakes'**
  String get homeSnakesTagline;

  /// Entry tile: missions.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get homeMissions;

  /// Entry tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily & weekly goals'**
  String get homeMissionsSubtitle;

  /// Entry tile: the Collection Room (short name).
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get homeCollection;

  /// Entry tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Dice, tokens & frames'**
  String get homeCollectionSubtitle;

  /// Entry tile: friends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get homeFriends;

  /// Entry tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Play with your crew'**
  String get homeFriendsSubtitle;

  /// Entry tile: events.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get homeEvents;

  /// Entry tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Limited-time cups'**
  String get homeEventsSubtitle;

  /// Lobby: the Shop button pinned at the top of Home (stays visible while the lobby scrolls).
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get homeShop;

  /// Section header above the entry tiles (missions, collection, friends, events).
  ///
  /// In en, this message translates to:
  /// **'More to Explore'**
  String get homeExploreHeader;

  /// Section header above the game cards.
  ///
  /// In en, this message translates to:
  /// **'Choose a Game'**
  String get homeGamesHeader;

  /// Tooltip of the cloud-save button for guests.
  ///
  /// In en, this message translates to:
  /// **'Save progress'**
  String get homeSaveProgressTooltip;

  /// Tooltip of the profile button.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get homeProfileTooltip;

  /// Tooltip of the settings button.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get homeSettingsTooltip;

  /// Tooltip of the theme shortcut.
  ///
  /// In en, this message translates to:
  /// **'Switch light/dark theme'**
  String get homeThemeTooltip;

  /// Accessibility label for opening the wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get homeWalletTooltip;

  /// Options sheet title for public play. {game} is the game name.
  ///
  /// In en, this message translates to:
  /// **'{game} online'**
  String homeOptionsOnlineTitle(String game);

  /// Options sheet title for a private room.
  ///
  /// In en, this message translates to:
  /// **'{game} with friends'**
  String homeOptionsFriendsTitle(String game);

  /// Options sheet title for practice.
  ///
  /// In en, this message translates to:
  /// **'Practice {game}'**
  String homeOptionsPracticeTitle(String game);

  /// Options sheet title for creating a private room (game not chosen yet).
  ///
  /// In en, this message translates to:
  /// **'Create a private room'**
  String get homeOptionsPrivateRoomTitle;

  /// Picker label: game.
  ///
  /// In en, this message translates to:
  /// **'Game'**
  String get homeGameLabel;

  /// Picker label: number of players.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get homePlayersLabel;

  /// Picker label: Ludo rules variant.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get homeModeLabel;

  /// Picker label: number of bots.
  ///
  /// In en, this message translates to:
  /// **'Bots'**
  String get homeBotsLabel;

  /// Caption for the classic variant.
  ///
  /// In en, this message translates to:
  /// **'Full rules'**
  String get homeModeClassicCaption;

  /// Caption for the quick variant.
  ///
  /// In en, this message translates to:
  /// **'Shorter games'**
  String get homeModeQuickCaption;

  /// Number of bot opponents.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 bot} other{{count} bots}}'**
  String homeBotCount(int count);

  /// Start public matchmaking.
  ///
  /// In en, this message translates to:
  /// **'Find match'**
  String get homeFindMatch;

  /// Create a private room.
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get homeCreateRoom;

  /// Start a practice game with bots.
  ///
  /// In en, this message translates to:
  /// **'Start practice'**
  String get homeStartPractice;

  /// Link from the friends sheet to the join-by-code sheet.
  ///
  /// In en, this message translates to:
  /// **'Have a code? Join a room'**
  String get homeHaveACode;

  /// Entry fee note in options sheets. {fee} is a formatted coin amount.
  ///
  /// In en, this message translates to:
  /// **'Entry fee {fee} coins · Winner takes the pot'**
  String homeEntryFeeNote(String fee);

  /// Practice explanation: free, XP still earned.
  ///
  /// In en, this message translates to:
  /// **'Practice is free: no coins, but you still earn XP and mission progress.'**
  String get homePracticeNote;

  /// Shown when the balance is below the entry fee. {fee} is formatted.
  ///
  /// In en, this message translates to:
  /// **'You need at least {fee} coins for this match.'**
  String homeNotEnoughCoins(String fee);

  /// Join-by-code sheet title.
  ///
  /// In en, this message translates to:
  /// **'Join a private room'**
  String get homeJoinCodeTitle;

  /// Room code input label.
  ///
  /// In en, this message translates to:
  /// **'Room code'**
  String get homeJoinCodeLabel;

  /// Room code input helper.
  ///
  /// In en, this message translates to:
  /// **'Ask the host for the 6-character code.'**
  String get homeJoinCodeHelper;

  /// Room code validation error.
  ///
  /// In en, this message translates to:
  /// **'Room codes have 6 letters or numbers.'**
  String get homeJoinCodeInvalid;

  /// Join-by-code submit button.
  ///
  /// In en, this message translates to:
  /// **'Join room'**
  String get homeJoinCodeAction;

  /// Toast when the server reports a level up.
  ///
  /// In en, this message translates to:
  /// **'Level up! You reached level {level}.'**
  String homeLevelUpToast(int level);

  /// Toast for a server-confirmed coin gain. {amount} is formatted.
  ///
  /// In en, this message translates to:
  /// **'+{amount} coins'**
  String homeCoinsGainedToast(String amount);

  /// Quick Play card subtitle.
  ///
  /// In en, this message translates to:
  /// **'Find random players and start now'**
  String get homeQuickPlaySubtitle;

  /// Quick Play main button: start public matchmaking with the selected game and player count.
  ///
  /// In en, this message translates to:
  /// **'Play Now'**
  String get homePlayNow;

  /// Game option: Ludo with the quick (shorter) rules variant.
  ///
  /// In en, this message translates to:
  /// **'Quick Ludo'**
  String get homeQuickLudo;

  /// Accessibility hint of the Quick Play game selector.
  ///
  /// In en, this message translates to:
  /// **'Change game'**
  String get homeChangeGameHint;

  /// Accessibility hint of the Quick Play player-count selector.
  ///
  /// In en, this message translates to:
  /// **'Change number of players'**
  String get homeChangePlayersHint;

  /// Subtitle of the Games tab.
  ///
  /// In en, this message translates to:
  /// **'Pick a game, then play online, with friends or against bots.'**
  String get homeGamesSubtitle;

  /// Bottom navigation label: home lobby.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeNavHome;

  /// Bottom navigation label and Games tab title.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get homeNavGames;

  /// Bottom navigation label: missions.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get homeNavMissions;

  /// Bottom navigation label: friends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get homeNavFriends;

  /// Bottom navigation label: the player's profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get homeNavProfile;

  /// Text on the decorative diagonal ribbon in the lobby header's top corner: the app shows no ads. Keep it very short; screen readers also read it.
  ///
  /// In en, this message translates to:
  /// **'No Ads'**
  String get homeNoAdsRibbon;

  /// Missions screen title.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get metaMissionsTitle;

  /// Events screen title.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get metaEventsTitle;

  /// Collection Room screen title.
  ///
  /// In en, this message translates to:
  /// **'Collection Room'**
  String get metaCollectionTitle;

  /// Friends screen title.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get metaFriendsTitle;

  /// Weekly friends leaderboard title.
  ///
  /// In en, this message translates to:
  /// **'Weekly ranking'**
  String get metaLeaderboardTitle;

  /// Level road (milestones) screen title.
  ///
  /// In en, this message translates to:
  /// **'Level road'**
  String get metaLevelRoadTitle;

  /// Section header: daily missions.
  ///
  /// In en, this message translates to:
  /// **'Daily missions'**
  String get metaDailyTitle;

  /// Section header: weekly challenge.
  ///
  /// In en, this message translates to:
  /// **'Weekly challenge'**
  String get metaWeeklyTitle;

  /// Button: claim a completed mission reward.
  ///
  /// In en, this message translates to:
  /// **'Claim'**
  String get metaClaim;

  /// Mission state.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get metaStatusInProgress;

  /// Mission state: completed, reward can be claimed.
  ///
  /// In en, this message translates to:
  /// **'Ready to claim'**
  String get metaStatusReady;

  /// Mission state: reward already claimed.
  ///
  /// In en, this message translates to:
  /// **'Claimed'**
  String get metaStatusClaimed;

  /// Shown right after a successful claim.
  ///
  /// In en, this message translates to:
  /// **'Reward collected — added to your account'**
  String get metaCollected;

  /// Mission progress, e.g. "1 / 2".
  ///
  /// In en, this message translates to:
  /// **'{progress} / {target}'**
  String metaProgressCount(String progress, String target);

  /// Screen reader label of a mission card.
  ///
  /// In en, this message translates to:
  /// **'{title}. Progress {progress}. {state}'**
  String metaMissionSemantics(String title, String progress, String state);

  /// Reward chip amount, e.g. "+500".
  ///
  /// In en, this message translates to:
  /// **'+{amount}'**
  String metaRewardAmount(String amount);

  /// XP reward chip, e.g. "+30 XP".
  ///
  /// In en, this message translates to:
  /// **'+{amount} XP'**
  String metaRewardXp(String amount);

  /// Screen reader: coin reward.
  ///
  /// In en, this message translates to:
  /// **'{amount} coins'**
  String metaRewardCoinsLabel(String amount);

  /// Screen reader: diamond reward.
  ///
  /// In en, this message translates to:
  /// **'{amount} diamonds'**
  String metaRewardDiamondsLabel(String amount);

  /// Screen reader: XP reward.
  ///
  /// In en, this message translates to:
  /// **'{amount} experience points'**
  String metaRewardXpLabel(String amount);

  /// Screen reader: cosmetic reward with its kind.
  ///
  /// In en, this message translates to:
  /// **'{name} ({kind})'**
  String metaRewardItemLabel(String name, String kind);

  /// Mission game filter: any game.
  ///
  /// In en, this message translates to:
  /// **'Any game'**
  String get metaGameAny;

  /// When daily missions refresh, local time.
  ///
  /// In en, this message translates to:
  /// **'New missions at {time}'**
  String metaResetsDailyAt(String time);

  /// When the weekly challenge resets, local weekday and time.
  ///
  /// In en, this message translates to:
  /// **'Resets {day} at {time}'**
  String metaResetsWeeklyAt(String day, String time);

  /// When an event ends, local date and time.
  ///
  /// In en, this message translates to:
  /// **'Ends {date}'**
  String metaEventEndsAt(String date);

  /// Reset line with a calm relative time, e.g. "New missions at 5:30 AM · in 4 h 12 min".
  ///
  /// In en, this message translates to:
  /// **'{when} · in {duration}'**
  String metaWhenWithCountdown(String when, String duration);

  /// Compact duration.
  ///
  /// In en, this message translates to:
  /// **'{days} d {hours} h'**
  String metaDurationDaysHours(int days, int hours);

  /// Compact duration.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String metaDurationHoursMinutes(int hours, int minutes);

  /// Compact duration.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String metaDurationMinutes(int minutes);

  /// Calm footnote under missions.
  ///
  /// In en, this message translates to:
  /// **'Missed a day? No problem — your XP, level and collection are always kept.'**
  String get metaNoPenaltyNote;

  /// Empty state title.
  ///
  /// In en, this message translates to:
  /// **'No missions right now'**
  String get metaMissionsEmptyTitle;

  /// Empty state message.
  ///
  /// In en, this message translates to:
  /// **'New daily missions arrive every day. Pull down to refresh.'**
  String get metaMissionsEmptyMessage;

  /// Toast after a transient claim/purchase failure.
  ///
  /// In en, this message translates to:
  /// **'{message} Tap again to retry.'**
  String metaRetryHint(String message);

  /// Dialog title after new items were granted.
  ///
  /// In en, this message translates to:
  /// **'New in your collection!'**
  String get metaNewItemsTitle;

  /// Dialog message listing granted items.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This item is now yours to equip and enjoy.} other{These {count} items are now yours to equip and enjoy.}}'**
  String metaNewItemsMessage(int count);

  /// Dismiss button of a reward dialog.
  ///
  /// In en, this message translates to:
  /// **'Nice!'**
  String get metaNice;

  /// Button: open the Collection Room.
  ///
  /// In en, this message translates to:
  /// **'View collection'**
  String get metaViewCollection;

  /// Section action: open event details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get metaEventDetails;

  /// Mission title (daily_ludo_match).
  ///
  /// In en, this message translates to:
  /// **'Ludo Time'**
  String get metaMissionLudoTimeTitle;

  /// Mission title (daily_snakes_match).
  ///
  /// In en, this message translates to:
  /// **'Climb the Ladder'**
  String get metaMissionClimbTitle;

  /// Mission title (daily_play_two).
  ///
  /// In en, this message translates to:
  /// **'Warm-Up'**
  String get metaMissionWarmUpTitle;

  /// Mission title (daily_friends_private).
  ///
  /// In en, this message translates to:
  /// **'Friendly Table'**
  String get metaMissionFriendlyTableTitle;

  /// Mission title (daily_finish_strong).
  ///
  /// In en, this message translates to:
  /// **'Stay to the End'**
  String get metaMissionStayToEndTitle;

  /// Mission title (daily_win_one).
  ///
  /// In en, this message translates to:
  /// **'Taste of Victory'**
  String get metaMissionTasteOfVictoryTitle;

  /// Mission title (daily_quick_ludo).
  ///
  /// In en, this message translates to:
  /// **'Quick Draw'**
  String get metaMissionQuickDrawTitle;

  /// Mission title (weekly_ten_matches).
  ///
  /// In en, this message translates to:
  /// **'Weekly Challenge'**
  String get metaMissionWeeklyChallengeTitle;

  /// Event mission title (autumn_quick_ludo).
  ///
  /// In en, this message translates to:
  /// **'Autumn Sprint'**
  String get metaMissionAutumnSprintTitle;

  /// Title for an unknown mission.
  ///
  /// In en, this message translates to:
  /// **'Mission'**
  String get metaMissionFallbackTitle;

  /// Mission description.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Complete 1 Ludo match.} other{Complete {count} Ludo matches.}}'**
  String metaMissionLudoMatchesDesc(int count);

  /// Mission description.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Complete 1 Snakes & Ladders match.} other{Complete {count} Snakes & Ladders matches.}}'**
  String metaMissionSnakesMatchesDesc(int count);

  /// Mission description.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Complete 1 match in any game.} other{Complete {count} matches in any game.}}'**
  String metaMissionAnyMatchesDesc(int count);

  /// Mission description.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Complete a private match with a friend.} other{Complete {count} private matches with friends.}}'**
  String metaMissionFriendPrivateDesc(int count);

  /// Mission description.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Complete a match without leaving early.} other{Complete {count} matches without leaving early.}}'**
  String metaMissionNoLeavingDesc(int count);

  /// Mission description.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Win 1 match.} other{Win {count} matches.}}'**
  String metaMissionWinDesc(int count);

  /// Mission description.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Complete 1 Quick Ludo match.} other{Complete {count} Quick Ludo matches.}}'**
  String metaMissionQuickLudoDesc(int count);

  /// Weekly challenge description.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Complete 1 match in Ludo or Snakes & Ladders.} other{Complete {count} matches across Ludo and Snakes & Ladders.}}'**
  String metaMissionWeeklyDesc(int count);

  /// Event title (autumn_cup).
  ///
  /// In en, this message translates to:
  /// **'Autumn Cup'**
  String get metaEventAutumnCupTitle;

  /// Event description (autumn_cup).
  ///
  /// In en, this message translates to:
  /// **'Celebrate the season with Quick Ludo and win the Autumn Leaf dice.'**
  String get metaEventAutumnCupDesc;

  /// Event start and end, local time.
  ///
  /// In en, this message translates to:
  /// **'{start} – {end}'**
  String metaEventWindow(String start, String end);

  /// Badge on a running event.
  ///
  /// In en, this message translates to:
  /// **'Event running'**
  String get metaEventLiveBadge;

  /// Section header: missions of an event.
  ///
  /// In en, this message translates to:
  /// **'Event missions'**
  String get metaEventMissionsTitle;

  /// Event rules card title.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get metaEventRulesTitle;

  /// Event rule.
  ///
  /// In en, this message translates to:
  /// **'Complete the event missions while the event is running.'**
  String get metaEventRuleComplete;

  /// Event rule: which matches count.
  ///
  /// In en, this message translates to:
  /// **'A match counts when you play it to the end, make at least 3 moves and it lasts at least 30 seconds.'**
  String get metaEventRuleEligible;

  /// Event rule: claiming.
  ///
  /// In en, this message translates to:
  /// **'Claim each reward here — it is added to your account right away.'**
  String get metaEventRuleClaim;

  /// Event rule: what happens at the end.
  ///
  /// In en, this message translates to:
  /// **'Rewards not claimed before the event ends are no longer available. Your XP, level and collection are never affected.'**
  String get metaEventRuleEnd;

  /// Empty state: no running events.
  ///
  /// In en, this message translates to:
  /// **'No events right now'**
  String get metaNoEventsTitle;

  /// Empty state message.
  ///
  /// In en, this message translates to:
  /// **'New events will appear here. Your daily missions are always available.'**
  String get metaNoEventsMessage;

  /// Button: open missions.
  ///
  /// In en, this message translates to:
  /// **'Go to missions'**
  String get metaGoToMissions;

  /// XP needed for the next level.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP to level {level}'**
  String metaXpToNextLevel(String xp, int level);

  /// At the level cap.
  ///
  /// In en, this message translates to:
  /// **'Max level reached — XP still counts for the weekly ranking'**
  String get metaMaxLevelReached;

  /// Small badge at max level.
  ///
  /// In en, this message translates to:
  /// **'MAX'**
  String get metaMaxBadge;

  /// Total XP line.
  ///
  /// In en, this message translates to:
  /// **'Total XP: {xp}'**
  String metaTotalXp(String xp);

  /// Card title.
  ///
  /// In en, this message translates to:
  /// **'How to earn XP'**
  String get metaHowToEarnXp;

  /// XP rule.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP for every completed match'**
  String metaXpForMatch(int xp);

  /// XP rule.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP bonus for a win'**
  String metaXpForWin(int xp);

  /// XP rule.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP when a friend plays with you'**
  String metaXpForFriend(int xp);

  /// XP rule.
  ///
  /// In en, this message translates to:
  /// **'Mission rewards include XP too'**
  String get metaXpForMissions;

  /// Fair-play note.
  ///
  /// In en, this message translates to:
  /// **'Matches count when played to the end (at least 3 moves and 30 seconds). Bots never earn XP.'**
  String get metaXpFairPlayNote;

  /// Section header: level milestones.
  ///
  /// In en, this message translates to:
  /// **'Milestones'**
  String get metaMilestonesTitle;

  /// Milestone reached.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get metaMilestoneUnlocked;

  /// Next milestone with XP to go.
  ///
  /// In en, this message translates to:
  /// **'Next milestone · {xp} XP to go'**
  String metaMilestoneNext(String xp);

  /// Locked milestone with the XP still needed.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP to go'**
  String metaMilestoneLocked(String xp);

  /// No milestones configured.
  ///
  /// In en, this message translates to:
  /// **'Milestones will appear here.'**
  String get metaNoMilestones;

  /// Level-up celebration title.
  ///
  /// In en, this message translates to:
  /// **'Level up!'**
  String get metaLevelUpTitle;

  /// Level-up celebration message.
  ///
  /// In en, this message translates to:
  /// **'You reached level {level}.'**
  String metaLevelUpMessage(int level);

  /// Header above unlocked items.
  ///
  /// In en, this message translates to:
  /// **'Unlocked for you'**
  String get metaUnlockedHeader;

  /// Dismiss level-up celebration.
  ///
  /// In en, this message translates to:
  /// **'Awesome!'**
  String get metaLevelUpContinue;

  /// Equipped loadout summary.
  ///
  /// In en, this message translates to:
  /// **'Your look'**
  String get metaYourLook;

  /// Collection progress.
  ///
  /// In en, this message translates to:
  /// **'{owned} of {total} collected'**
  String metaCollectedCount(String owned, String total);

  /// Collection tab.
  ///
  /// In en, this message translates to:
  /// **'Dice'**
  String get metaTabDice;

  /// Collection tab.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get metaTabTokens;

  /// Collection tab.
  ///
  /// In en, this message translates to:
  /// **'Ludo boards'**
  String get metaTabLudoBoards;

  /// Collection tab.
  ///
  /// In en, this message translates to:
  /// **'Snakes boards'**
  String get metaTabSnakesBoards;

  /// Collection tab.
  ///
  /// In en, this message translates to:
  /// **'Trails'**
  String get metaTabTrails;

  /// Collection tab.
  ///
  /// In en, this message translates to:
  /// **'Victory'**
  String get metaTabVictory;

  /// Collection tab.
  ///
  /// In en, this message translates to:
  /// **'Frames'**
  String get metaTabFrames;

  /// Collection tab.
  ///
  /// In en, this message translates to:
  /// **'Titles'**
  String get metaTabTitles;

  /// Collection tab.
  ///
  /// In en, this message translates to:
  /// **'Badges'**
  String get metaTabBadges;

  /// Collection tab.
  ///
  /// In en, this message translates to:
  /// **'Emotes'**
  String get metaTabEmotes;

  /// Category of profile pictures (Shop category pill and Collection Room tab).
  ///
  /// In en, this message translates to:
  /// **'Pictures'**
  String get metaTabPictures;

  /// Collection filter.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get metaFilterAll;

  /// Collection filter.
  ///
  /// In en, this message translates to:
  /// **'Owned'**
  String get metaFilterOwned;

  /// Collection filter: not owned yet.
  ///
  /// In en, this message translates to:
  /// **'To unlock'**
  String get metaFilterLocked;

  /// Item state.
  ///
  /// In en, this message translates to:
  /// **'Equipped'**
  String get metaEquipped;

  /// Item state.
  ///
  /// In en, this message translates to:
  /// **'Owned'**
  String get metaOwned;

  /// Item state.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get metaLocked;

  /// Badge on newly owned items.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get metaNewBadge;

  /// Screen reader label of an item card.
  ///
  /// In en, this message translates to:
  /// **'{name}, {rarity}, {state}. {how}'**
  String metaItemSemantics(
    String name,
    String rarity,
    String state,
    String how,
  );

  /// Acquisition label.
  ///
  /// In en, this message translates to:
  /// **'Starter item'**
  String get metaAcqStarter;

  /// Acquisition label.
  ///
  /// In en, this message translates to:
  /// **'Reach level {level}'**
  String metaAcqLevel(int level);

  /// Acquisition label.
  ///
  /// In en, this message translates to:
  /// **'Mission reward'**
  String get metaAcqMission;

  /// Acquisition label.
  ///
  /// In en, this message translates to:
  /// **'Weekly challenge reward'**
  String get metaAcqWeeklyChallenge;

  /// Acquisition label.
  ///
  /// In en, this message translates to:
  /// **'Win your first match'**
  String get metaAcqFirstWin;

  /// Acquisition label.
  ///
  /// In en, this message translates to:
  /// **'Event reward'**
  String get metaAcqEvent;

  /// Acquisition label.
  ///
  /// In en, this message translates to:
  /// **'Autumn Cup reward'**
  String get metaAcqAutumnCup;

  /// Price in coins.
  ///
  /// In en, this message translates to:
  /// **'{amount} coins'**
  String metaPriceCoins(String amount);

  /// Price in diamonds.
  ///
  /// In en, this message translates to:
  /// **'{amount} diamonds'**
  String metaPriceDiamonds(String amount);

  /// Button: equip an item.
  ///
  /// In en, this message translates to:
  /// **'Equip'**
  String get metaEquip;

  /// Button: reset the slot to its starter item.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get metaEquipDefault;

  /// Toast after equipping.
  ///
  /// In en, this message translates to:
  /// **'Equipped!'**
  String get metaEquippedToast;

  /// Toast after resetting to default.
  ///
  /// In en, this message translates to:
  /// **'Back to the default look'**
  String get metaDefaultEquippedToast;

  /// Owned emote info.
  ///
  /// In en, this message translates to:
  /// **'Use your emotes during matches from the emote button.'**
  String get metaEmoteHint;

  /// Owned badge info.
  ///
  /// In en, this message translates to:
  /// **'Badges celebrate what you have achieved. They are yours to keep.'**
  String get metaBadgeHint;

  /// Purchase button.
  ///
  /// In en, this message translates to:
  /// **'Buy for {price}'**
  String metaBuyFor(String price);

  /// Confirm purchase.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get metaBuy;

  /// Purchase confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Buy {item}?'**
  String metaPurchaseTitle(String item);

  /// Purchase dialog row.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get metaPrice;

  /// Purchase dialog row.
  ///
  /// In en, this message translates to:
  /// **'Your balance'**
  String get metaYourBalance;

  /// Purchase dialog row.
  ///
  /// In en, this message translates to:
  /// **'After purchase'**
  String get metaBalanceAfter;

  /// Not enough balance.
  ///
  /// In en, this message translates to:
  /// **'Not enough yet — you need another {amount}. Win matches and complete missions to earn more.'**
  String metaNeedMore(String amount);

  /// Honest purchase note.
  ///
  /// In en, this message translates to:
  /// **'Cosmetic only — it never changes dice, rules or matchmaking.'**
  String get metaCosmeticOnlyNote;

  /// Toast after purchase.
  ///
  /// In en, this message translates to:
  /// **'{item} is now in your collection!'**
  String metaPurchaseSuccess(String item);

  /// Purchase failed: not enough coins.
  ///
  /// In en, this message translates to:
  /// **'Not enough coins for this item.'**
  String get metaNotEnoughCoins;

  /// Purchase failed: not enough diamonds.
  ///
  /// In en, this message translates to:
  /// **'Not enough diamonds for this item.'**
  String get metaNotEnoughDiamonds;

  /// Purchase failed: already owned.
  ///
  /// In en, this message translates to:
  /// **'You already own this item.'**
  String get metaAlreadyOwned;

  /// Purchase failed: not a purchasable item.
  ///
  /// In en, this message translates to:
  /// **'This item is unlocked by playing, not bought.'**
  String get metaItemNotForSale;

  /// Locked level item info.
  ///
  /// In en, this message translates to:
  /// **'Unlocks automatically when you reach level {level}.'**
  String metaUnlocksAtLevel(int level);

  /// Locked mission/event item info.
  ///
  /// In en, this message translates to:
  /// **'Earn it by completing the matching mission or event — no purchase needed.'**
  String get metaEarnFromMissionsHint;

  /// Locked filter is empty.
  ///
  /// In en, this message translates to:
  /// **'You have unlocked everything here. Nicely done!'**
  String get metaAllOwnedInKind;

  /// Owned filter is empty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet — keep playing to unlock more.'**
  String get metaNothingOwnedInKind;

  /// Collection Room tab with nothing owned or to earn (its items are only sold in the Shop).
  ///
  /// In en, this message translates to:
  /// **'Nothing to collect here yet. Take a look in the Shop!'**
  String get metaKindEmptyMessage;

  /// Collection Room empty state: button that opens the Shop.
  ///
  /// In en, this message translates to:
  /// **'Go to Shop'**
  String get metaGoToShop;

  /// Collection Room, below a tab: more items of it are for sale in the Shop.
  ///
  /// In en, this message translates to:
  /// **'Find more in the Shop'**
  String get metaFindMoreInShop;

  /// Fairness note in the Collection Room.
  ///
  /// In en, this message translates to:
  /// **'Every item is cosmetic and has a fixed way to get it — no random boxes, no gameplay advantage.'**
  String get metaCollectionFairNote;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Timeless ivory dice with crisp black pips.'**
  String get metaDescDiceClassic;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Glowing dice that pulse with every roll.'**
  String get metaDescDiceNeon;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Polished gold dice fit for royalty.'**
  String get metaDescDiceGolden;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Warm amber dice from the Autumn Cup.'**
  String get metaDescDiceAutumn;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'The pawn everyone knows.'**
  String get metaDescTokenClassic;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Faceted gem tokens that catch the light.'**
  String get metaDescTokenGem;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Pawns wearing tiny crowns.'**
  String get metaDescTokenRoyal;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'A legendary crown-shaped piece.'**
  String get metaDescTokenCrown;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'The traditional four-colour Ludo board.'**
  String get metaDescLudoBoardClassic;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Dark marble with silver inlays.'**
  String get metaDescLudoBoardMidnight;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'A palace courtyard in gold and crimson.'**
  String get metaDescLudoBoardRoyal;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Green meadows, friendly snakes, sturdy ladders.'**
  String get metaDescSnakesBoardClassic;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Vines, ruins and temple stairs.'**
  String get metaDescSnakesBoardJungle;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Licorice snakes and candy-cane ladders.'**
  String get metaDescSnakesBoardCandy;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Clean moves, no trail.'**
  String get metaDescTrailNone;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'A shower of sparkles follows every move.'**
  String get metaDescTrailSparkle;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'A blazing comet tail.'**
  String get metaDescTrailComet;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'A classic confetti celebration.'**
  String get metaDescVictoryConfetti;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Light up the sky when you win.'**
  String get metaDescVictoryFireworks;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'A golden crown descends on the winner.'**
  String get metaDescVictoryCrown;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Your avatar, unframed.'**
  String get metaDescFrameNone;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'A simple bronze ring around your avatar.'**
  String get metaDescFrameBronze;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'A silver laurel wreath.'**
  String get metaDescFrameSilver;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'A gold laurel wreath for seasoned players.'**
  String get metaDescFrameGold;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'An ornate royal crest.'**
  String get metaDescFrameRoyal;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Everyone starts somewhere.'**
  String get metaDescTitleRookie;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'For players who think three moves ahead.'**
  String get metaDescTitleStrategist;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'The dice seem to listen to you.'**
  String get metaDescTitleDiceMaster;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Reserved for true royalty.'**
  String get metaDescTitleRoyal;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Completed a weekly challenge.'**
  String get metaDescTitleWeeklyChampion;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Won your first match.'**
  String get metaDescBadgeFirstWin;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Completed a weekly challenge.'**
  String get metaDescBadgeFriendly;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Say hello.'**
  String get metaDescEmoteWave;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Nice one!'**
  String get metaDescEmoteThumbs;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Share a laugh.'**
  String get metaDescEmoteLaugh;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Did that just happen?'**
  String get metaDescEmoteWow;

  /// Cosmetic item description.
  ///
  /// In en, this message translates to:
  /// **'Show who rules the board.'**
  String get metaDescEmoteCrown;

  /// Friend code card title.
  ///
  /// In en, this message translates to:
  /// **'Your friend code'**
  String get metaYourFriendCode;

  /// Friend code card hint.
  ///
  /// In en, this message translates to:
  /// **'Share it so friends can add you.'**
  String get metaFriendCodeHint;

  /// Screen reader: friend code spelled out.
  ///
  /// In en, this message translates to:
  /// **'Friend code: {code}'**
  String metaFriendCodeSemantics(String code);

  /// Share sheet text.
  ///
  /// In en, this message translates to:
  /// **'Let\'s play Ludo Arena together! Add me as a friend with my code: {code}'**
  String metaShareFriendCodeMessage(String code);

  /// Button: add a friend.
  ///
  /// In en, this message translates to:
  /// **'Add friend'**
  String get metaAddFriend;

  /// Compact add-friend button in lists.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get metaAdd;

  /// Add-friend sheet title.
  ///
  /// In en, this message translates to:
  /// **'Add a friend'**
  String get metaAddFriendTitle;

  /// Add-friend sheet help.
  ///
  /// In en, this message translates to:
  /// **'Enter your friend\'s code. They can find it on their Friends screen.'**
  String get metaAddFriendHelp;

  /// Input label.
  ///
  /// In en, this message translates to:
  /// **'Friend code'**
  String get metaFriendCodeLabel;

  /// Input placeholder (Latin code format).
  ///
  /// In en, this message translates to:
  /// **'u_abcd 2345 wxyz'**
  String get metaFriendCodeHintExample;

  /// Paste button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get metaPaste;

  /// Send friend request.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get metaSendRequest;

  /// Validation: empty code.
  ///
  /// In en, this message translates to:
  /// **'Enter a friend code.'**
  String get metaFriendCodeRequired;

  /// Validation: malformed code.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a friend code. It starts with u_ followed by letters and numbers.'**
  String get metaInvalidFriendCode;

  /// Toast after sending a request.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent to {name}'**
  String metaRequestSent(String name);

  /// Toast: friendship accepted.
  ///
  /// In en, this message translates to:
  /// **'You and {name} are now friends!'**
  String metaNowFriends(String name);

  /// Add friend: already friends.
  ///
  /// In en, this message translates to:
  /// **'You\'re already friends.'**
  String get metaAlreadyFriends;

  /// Friends tab.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get metaTabFriends;

  /// Requests tab.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get metaTabRequests;

  /// Recent opponents tab.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get metaTabRecent;

  /// Friend presence.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get metaOnline;

  /// Friend presence.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get metaOffline;

  /// Overflow menu tooltip.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get metaMoreActions;

  /// Menu: remove friend.
  ///
  /// In en, this message translates to:
  /// **'Remove friend'**
  String get metaRemoveFriend;

  /// Confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String metaRemoveFriendTitle(String name);

  /// Confirm dialog message.
  ///
  /// In en, this message translates to:
  /// **'You can add each other again any time with a friend code.'**
  String get metaRemoveFriendMessage;

  /// Confirm removal.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get metaRemove;

  /// Toast after removal.
  ///
  /// In en, this message translates to:
  /// **'{name} was removed from your friends'**
  String metaFriendRemoved(String name);

  /// Section header.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get metaIncomingRequests;

  /// Section header.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get metaOutgoingRequests;

  /// Incoming request subtitle.
  ///
  /// In en, this message translates to:
  /// **'Wants to be your friend'**
  String get metaWantsToBeFriends;

  /// Outgoing request subtitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for an answer'**
  String get metaRequestPending;

  /// Accept a request.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get metaAccept;

  /// Decline a request.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get metaDecline;

  /// Toast.
  ///
  /// In en, this message translates to:
  /// **'Request declined'**
  String get metaRequestDeclined;

  /// Toast.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get metaRequestCancelled;

  /// Recent list: request already sent.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get metaRequested;

  /// Recent list: already friends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get metaFriendsLabel;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No friends yet'**
  String get metaNoFriendsTitle;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Share your code or add a friend to play together.'**
  String get metaNoFriendsMessage;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get metaNoRequestsTitle;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Friend requests you send or receive appear here.'**
  String get metaNoRequestsMessage;

  /// Recent tab hint.
  ///
  /// In en, this message translates to:
  /// **'Players you met in online matches during the last 14 days.'**
  String get metaRecentHint;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No recent opponents'**
  String get metaNoRecentTitle;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Play an online match — the players you meet will show up here.'**
  String get metaNoRecentMessage;

  /// In-app banner for a new friend request.
  ///
  /// In en, this message translates to:
  /// **'{name} wants to be your friend'**
  String metaFriendRequestBanner(String name);

  /// Banner action.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get metaView;

  /// Error: own code.
  ///
  /// In en, this message translates to:
  /// **'That\'s your own friend code.'**
  String get metaErrorCannotFriendSelf;

  /// Error friend_limit: the accepted-friends cap is reached.
  ///
  /// In en, this message translates to:
  /// **'You can have up to {max} friends. Remove a friend to add someone new.'**
  String metaErrorFriendLimit(int max);

  /// Error: no player with this code.
  ///
  /// In en, this message translates to:
  /// **'No player has this friend code. Check it and try again.'**
  String get metaErrorUnknownFriendCode;

  /// Error: same request still processing.
  ///
  /// In en, this message translates to:
  /// **'Still working on it — please try again in a moment.'**
  String get metaErrorRequestInProgress;

  /// Error: mission no longer in a current period.
  ///
  /// In en, this message translates to:
  /// **'This mission has ended. Pull down to see the current missions.'**
  String get metaErrorMissionEnded;

  /// Leaderboard explanation.
  ///
  /// In en, this message translates to:
  /// **'You and your friends, ranked by XP earned this week.'**
  String get metaLeaderboardSubtitle;

  /// Teaser card on Friends.
  ///
  /// In en, this message translates to:
  /// **'See how you and your friends are doing this week.'**
  String get metaLeaderboardTeaser;

  /// Weekly XP of a player.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP'**
  String metaWeeklyXp(String xp);

  /// Leaderboard: my own row.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String metaYouName(String name);

  /// Screen reader: leaderboard row.
  ///
  /// In en, this message translates to:
  /// **'Rank {rank}: {name}, {xp}'**
  String metaLeaderboardRowSemantics(int rank, String name, String xp);

  /// Leaderboard with no friends.
  ///
  /// In en, this message translates to:
  /// **'Add friends to see how you compare. Friendly competition, no pressure.'**
  String get metaLeaderboardAlone;

  /// Indian numbering unit 100,000 (lakh), used for large coin amounts in the Indian number format. {value} is already formatted (e.g. 10 or 12.5).
  ///
  /// In en, this message translates to:
  /// **'{value} Lakh'**
  String numberLakh(String value);

  /// Indian numbering unit 10,000,000 (crore). {value} is already formatted.
  ///
  /// In en, this message translates to:
  /// **'{value} Crore'**
  String numberCrore(String value);

  /// Short international unit 1,000 (thousand) for compact coin amounts in the International number format, e.g. 54.32K. Keep it as short as the locale's compact form; use a non-breaking space if the unit is separated. {value} is already formatted.
  ///
  /// In en, this message translates to:
  /// **'{value}K'**
  String numberThousand(String value);

  /// Short international unit 1,000,000 (million), e.g. 1M or 1.5M. {value} is already formatted.
  ///
  /// In en, this message translates to:
  /// **'{value}M'**
  String numberMillion(String value);

  /// Short international unit 1,000,000,000 (billion), e.g. 1B. {value} is already formatted.
  ///
  /// In en, this message translates to:
  /// **'{value}B'**
  String numberBillion(String value);

  /// First-run language picker title.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get onboardingLanguageTitle;

  /// First-run language picker subtitle.
  ///
  /// In en, this message translates to:
  /// **'You can change it any time in Settings.'**
  String get onboardingLanguageSubtitle;

  /// Label of the live language preview card.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get onboardingPreviewLabel;

  /// Preview card headline.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Ludo Arena!'**
  String get onboardingPreviewTitle;

  /// Preview card body text.
  ///
  /// In en, this message translates to:
  /// **'Roll the dice, race your tokens home and claim the crown.'**
  String get onboardingPreviewBody;

  /// Game title with its rules variant, e.g. 'Ludo · Classic'.
  ///
  /// In en, this message translates to:
  /// **'{game} · {variant}'**
  String playGameVariantTitle(String game, String variant);

  /// Match type label: public online match.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get playModeOnline;

  /// Match type label: private room with friends.
  ///
  /// In en, this message translates to:
  /// **'Private room'**
  String get playModePrivate;

  /// Match type label: practice against bots.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get playModePractice;

  /// Fallback name for a player without a display name.
  ///
  /// In en, this message translates to:
  /// **'Player {seat}'**
  String playSeatPlayer(int seat);

  /// A player's name marked as the local user.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String playNameYou(String name);

  /// Button: go to the home screen.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get playHome;

  /// Button: return to the home screen.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get playBackHome;

  /// Button: retry the failed action.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get playTryAgain;

  /// Compact entry fee chip; fee is a formatted coin amount.
  ///
  /// In en, this message translates to:
  /// **'Entry {fee}'**
  String playEntryFee(String fee);

  /// Entry fee explanation on the private room setup.
  ///
  /// In en, this message translates to:
  /// **'Entry fee: {fee} coins per player, charged when the game starts. The winner takes the pot.'**
  String playEntryFeeNote(String fee);

  /// Title when the user cannot afford the entry fee.
  ///
  /// In en, this message translates to:
  /// **'Not enough coins'**
  String get playNotEnoughCoinsTitle;

  /// Warning: the wallet is below the entry fee.
  ///
  /// In en, this message translates to:
  /// **'You need {fee} coins to play. Earn coins from missions and come back!'**
  String playNotEnoughCoinsHint(String fee);

  /// An empty seat waiting for a player.
  ///
  /// In en, this message translates to:
  /// **'Open seat'**
  String get playSeatOpen;

  /// Loading message while the match is opened.
  ///
  /// In en, this message translates to:
  /// **'Joining the match…'**
  String get playLoadingMatch;

  /// The match can no longer be opened.
  ///
  /// In en, this message translates to:
  /// **'This match is no longer available.'**
  String get playMatchUnavailable;

  /// Toast: the server closed the room.
  ///
  /// In en, this message translates to:
  /// **'The room was closed.'**
  String get playRoomClosed;

  /// Toast: the user is no longer seated in the room.
  ///
  /// In en, this message translates to:
  /// **'You\'re no longer in this room.'**
  String get playRemovedFromRoom;

  /// The private room can no longer be opened.
  ///
  /// In en, this message translates to:
  /// **'This room is no longer available.'**
  String get playRoomUnavailable;

  /// Loading message while the lobby is opened.
  ///
  /// In en, this message translates to:
  /// **'Opening the room…'**
  String get playLoadingRoom;

  /// Form label: which game to play.
  ///
  /// In en, this message translates to:
  /// **'Game'**
  String get playGameLabel;

  /// Form label: Ludo rules variant (classic / quick).
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get playModeLabel;

  /// Form label: number of seats.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get playPlayersLabel;

  /// Caption of classic Ludo rules.
  ///
  /// In en, this message translates to:
  /// **'4 tokens · leave base on a 6'**
  String get playVariantClassicCaption;

  /// Caption of quick Ludo rules.
  ///
  /// In en, this message translates to:
  /// **'2 tokens · leave base on a 1 or 6'**
  String get playVariantQuickCaption;

  /// Matchmaking screen title.
  ///
  /// In en, this message translates to:
  /// **'Finding players'**
  String get playMatchmakingTitle;

  /// Matchmaking status: connecting to the server.
  ///
  /// In en, this message translates to:
  /// **'Connecting to the game server…'**
  String get playMatchmakingConnecting;

  /// Matchmaking status: joining the queue.
  ///
  /// In en, this message translates to:
  /// **'Joining the queue…'**
  String get playMatchmakingJoining;

  /// Matchmaking status: waiting for opponents.
  ///
  /// In en, this message translates to:
  /// **'Looking for opponents…'**
  String get playMatchmakingSearching;

  /// Matchmaking status: all seats filled.
  ///
  /// In en, this message translates to:
  /// **'Table full! Starting…'**
  String get playMatchmakingStarting;

  /// Explains the public lobby start rule when a fill timer runs.
  ///
  /// In en, this message translates to:
  /// **'The match starts when all seats are filled or when the timer runs out.'**
  String get playMatchmakingStartsSoon;

  /// Explains the public lobby start rule without a timer.
  ///
  /// In en, this message translates to:
  /// **'The match starts as soon as all seats are filled.'**
  String get playMatchmakingStartsWhenFull;

  /// Accessibility: how many players joined the lobby.
  ///
  /// In en, this message translates to:
  /// **'{count} of {capacity} players joined'**
  String playMatchmakingPlayers(int count, int capacity);

  /// Button: stop searching for a match.
  ///
  /// In en, this message translates to:
  /// **'Cancel search'**
  String get playMatchmakingCancel;

  /// Footnote about when the entry fee is charged.
  ///
  /// In en, this message translates to:
  /// **'The entry fee is charged when the match starts. The winner takes the pot.'**
  String get playMatchmakingFeeNote;

  /// Matchmaking ended without enough players.
  ///
  /// In en, this message translates to:
  /// **'No opponents right now'**
  String get playMatchmakingTimeoutTitle;

  /// Explanation after a matchmaking timeout.
  ///
  /// In en, this message translates to:
  /// **'Nobody joined in time. Try again, or invite friends to a private room.'**
  String get playMatchmakingTimeoutMessage;

  /// Matchmaking failed with an error.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find a match'**
  String get playMatchmakingErrorTitle;

  /// Create private room screen title.
  ///
  /// In en, this message translates to:
  /// **'Create private room'**
  String get playCreateRoomTitle;

  /// Button: create the private room.
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get playCreateRoomAction;

  /// Loading message while the room is created.
  ///
  /// In en, this message translates to:
  /// **'Creating your room…'**
  String get playCreatingRoom;

  /// Private room lobby title.
  ///
  /// In en, this message translates to:
  /// **'Private room'**
  String get playLobbyTitle;

  /// Label above the private room code.
  ///
  /// In en, this message translates to:
  /// **'Room code'**
  String get playRoomCodeLabel;

  /// Screen reader text of the room code; letters are spelled out separated by spaces.
  ///
  /// In en, this message translates to:
  /// **'Room code {letters}'**
  String playRoomCodeA11y(String letters);

  /// Button: copy the room code.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get playCopyCode;

  /// Toast after copying the room code.
  ///
  /// In en, this message translates to:
  /// **'Room code copied'**
  String get playCodeCopied;

  /// Button: share an invite with the room code.
  ///
  /// In en, this message translates to:
  /// **'Share invite'**
  String get playShareInvite;

  /// Text shared to other apps. Must contain only the game name and the room code.
  ///
  /// In en, this message translates to:
  /// **'Join me for {game} on Ludo Arena! Open the app, tap Join with Code and enter: {code}'**
  String playInviteShareText(String game, String code);

  /// Subject line of the shared invite.
  ///
  /// In en, this message translates to:
  /// **'Ludo Arena invite'**
  String get playInviteShareSubject;

  /// Lobby section header with seated / total seats.
  ///
  /// In en, this message translates to:
  /// **'Players {count}/{capacity}'**
  String playLobbyPlayers(int count, int capacity);

  /// Host button: start the game.
  ///
  /// In en, this message translates to:
  /// **'Start game'**
  String get playLobbyStart;

  /// Guest status in the lobby.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the host to start…'**
  String get playLobbyWaitingForHost;

  /// Guest status naming the host.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name} (host) to start…'**
  String playLobbyWaitingForNamedHost(String name);

  /// Why Start is disabled: fewer than 2 players.
  ///
  /// In en, this message translates to:
  /// **'At least 2 players are needed to start.'**
  String get playStartBlockedNeedPlayers;

  /// Why Start is disabled: someone is disconnected.
  ///
  /// In en, this message translates to:
  /// **'Waiting for everyone to reconnect.'**
  String get playStartBlockedConnections;

  /// Why Start is disabled: requested bots are not seated yet.
  ///
  /// In en, this message translates to:
  /// **'Bots are taking their seats…'**
  String get playStartBlockedBots;

  /// Host switch: allow bot seats.
  ///
  /// In en, this message translates to:
  /// **'Allow bots'**
  String get playAllowBots;

  /// Explains bot seats in private rooms.
  ///
  /// In en, this message translates to:
  /// **'Fill empty seats with computer players. Everyone pays the entry fee, computer players too.'**
  String get playAllowBotsHint;

  /// Host button: seat a bot.
  ///
  /// In en, this message translates to:
  /// **'Add bot'**
  String get playAddBot;

  /// A requested bot is sitting down.
  ///
  /// In en, this message translates to:
  /// **'Bot joining…'**
  String get playBotJoining;

  /// Tooltip of the button that removes a bot from its seat.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String playRemoveBotA11y(String name);

  /// Button: invite friends to the room.
  ///
  /// In en, this message translates to:
  /// **'Invite friends'**
  String get playInviteFriends;

  /// Invite friends sheet title.
  ///
  /// In en, this message translates to:
  /// **'Invite friends'**
  String get playInviteSheetTitle;

  /// Button: invite this friend.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get playInviteSend;

  /// State after a friend was invited.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get playInviteSent;

  /// Friend presence: online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get playFriendOnline;

  /// Friend presence: offline (cannot be invited).
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get playFriendOffline;

  /// Invite sheet: no friends.
  ///
  /// In en, this message translates to:
  /// **'No friends yet'**
  String get playInviteEmptyTitle;

  /// Invite sheet: what to do without friends.
  ///
  /// In en, this message translates to:
  /// **'Share the room code instead, or add friends from the Friends screen.'**
  String get playInviteEmptyMessage;

  /// Invite sheet: the friends list failed to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your friends.'**
  String get playInviteError;

  /// Button: leave the private room.
  ///
  /// In en, this message translates to:
  /// **'Leave room'**
  String get playLeaveRoom;

  /// Confirm dialog title for leaving a lobby.
  ///
  /// In en, this message translates to:
  /// **'Leave this room?'**
  String get playLeaveRoomTitle;

  /// Leave dialog text for the host.
  ///
  /// In en, this message translates to:
  /// **'You\'re the host. The next player becomes host when you leave.'**
  String get playLeaveRoomHostMessage;

  /// Leave dialog text for guests.
  ///
  /// In en, this message translates to:
  /// **'You can come back with the room code while the room is open.'**
  String get playLeaveRoomMessage;

  /// Dialog button: stay in the room.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get playStay;

  /// Label of the host crown.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get playHostBadge;

  /// Join with code screen title.
  ///
  /// In en, this message translates to:
  /// **'Join with code'**
  String get playJoinTitle;

  /// Instructions above the room code field.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-character room code your friend shared.'**
  String get playJoinHint;

  /// How many characters of the room code are still missing.
  ///
  /// In en, this message translates to:
  /// **'{remaining, plural, =1{1 more character} other{{remaining} more characters}}'**
  String playJoinCodeIncomplete(int remaining);

  /// The code contains characters that room codes never use.
  ///
  /// In en, this message translates to:
  /// **'Room codes use the letters A–Z and the numbers 2–9 (no I, O, 0 or 1).'**
  String get playJoinInvalidChars;

  /// Loading the room preview.
  ///
  /// In en, this message translates to:
  /// **'Looking up the room…'**
  String get playJoinLookingUp;

  /// Button: join the previewed room.
  ///
  /// In en, this message translates to:
  /// **'Join room'**
  String get playJoinAction;

  /// Button label while joining.
  ///
  /// In en, this message translates to:
  /// **'Joining…'**
  String get playJoining;

  /// Room preview: host name.
  ///
  /// In en, this message translates to:
  /// **'Hosted by {name}'**
  String playJoinPreviewHost(String name);

  /// Room preview: seated / total seats.
  ///
  /// In en, this message translates to:
  /// **'{count}/{capacity} players'**
  String playJoinPreviewPlayers(int count, int capacity);

  /// Room preview status: can be joined.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get playJoinStatusOpen;

  /// Room preview status: all seats taken.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get playJoinStatusFull;

  /// Room preview status: the game already started.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get playJoinStatusInProgress;

  /// Room preview status: closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get playJoinStatusClosed;

  /// Tooltip: paste the room code from the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get playPaste;

  /// Practice screen title.
  ///
  /// In en, this message translates to:
  /// **'Practice vs bots'**
  String get playPracticeTitle;

  /// Form label: number of bots.
  ///
  /// In en, this message translates to:
  /// **'Bots'**
  String get playPracticeBotsLabel;

  /// Number of practice bots.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 bot} other{{count} bots}}'**
  String playPracticeBotCount(int count);

  /// Button: start a practice game.
  ///
  /// In en, this message translates to:
  /// **'Start practice'**
  String get playPracticeStart;

  /// Practice explanation.
  ///
  /// In en, this message translates to:
  /// **'Practice is free and pays no coins. You play against computer players.'**
  String get playPracticeNote;

  /// Practice status: creating the table.
  ///
  /// In en, this message translates to:
  /// **'Setting up your practice table…'**
  String get playPracticeSettingUp;

  /// Practice status: seated bots out of requested bots.
  ///
  /// In en, this message translates to:
  /// **'Bots joining… {seated}/{total}'**
  String playPracticeBotsJoining(int seated, int total);

  /// Practice could not start because no bot arrived.
  ///
  /// In en, this message translates to:
  /// **'Bots are busy'**
  String get playPracticeBotsUnavailableTitle;

  /// Practice failed to start.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start practice'**
  String get playPracticeErrorTitle;

  /// Tooltip: leave (forfeit) the running match.
  ///
  /// In en, this message translates to:
  /// **'Leave match'**
  String get playLeave;

  /// Status: the local player must roll.
  ///
  /// In en, this message translates to:
  /// **'Your turn — tap the dice!'**
  String get playTurnYourRoll;

  /// Status: the local player must pick one of several movable tokens.
  ///
  /// In en, this message translates to:
  /// **'Pick a glowing token to move'**
  String get playTurnPickToken;

  /// Status: the local player's turn while the server acts.
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get playTurnYours;

  /// Status: another human player's turn.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s turn'**
  String playTurnOther(String name);

  /// Ludo: the third six in a row is void.
  ///
  /// In en, this message translates to:
  /// **'Three sixes in a row! The turn passes.'**
  String get playVoidedThreeSixes;

  /// The server played a timed-out turn for a player.
  ///
  /// In en, this message translates to:
  /// **'Time\'s up — played automatically for {name}'**
  String playAutoPlayed(String name);

  /// A player left the running match.
  ///
  /// In en, this message translates to:
  /// **'{name} left the match'**
  String playForfeitLeft(String name);

  /// Caption: another player was removed for missing turns in a row (count = consecutive missed turns, 5 by default).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{name} was removed after missing a turn} other{{name} was removed after {count} missed turns in a row}}'**
  String playForfeitTimeouts(String name, int count);

  /// Toast shown to the local player, who is then taken Home, after the server removed them for missing turns in a row (count = consecutive missed turns, 5 by default).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You were removed from the match because you missed your turn.} other{You were removed from the match because you missed {count} turns in a row.}}'**
  String playRemovedForInactivity(int count);

  /// Player panel chip: disconnected.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get playPlayerDisconnected;

  /// Player panel chip: forfeited / left.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get playPlayerForfeited;

  /// Accessibility: the player is connected (green dot on the pod).
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get playPlayerOnline;

  /// Accessibility: the user muted this player (icon by the name on the pod).
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get playPlayerMuted;

  /// Accessibility: this player has the current turn.
  ///
  /// In en, this message translates to:
  /// **'current turn'**
  String get playPanelTurnA11y;

  /// Accessibility: consecutive missed turns (5 by default means removal).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 missed turn} other{{count} missed turns}}'**
  String playStrikesA11y(int count);

  /// Accessibility: Ludo tokens that reached home.
  ///
  /// In en, this message translates to:
  /// **'{home} of {total} tokens home'**
  String playTokensHome(int home, int total);

  /// Snakes & Ladders: the square a player is on.
  ///
  /// In en, this message translates to:
  /// **'Square {square}'**
  String playSquare(int square);

  /// Snakes & Ladders: the token has not entered the board yet.
  ///
  /// In en, this message translates to:
  /// **'At the start'**
  String get playAtStart;

  /// Banner while the connection is restored.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting… your match continues'**
  String get playReconnecting;

  /// Banner while the board is resynchronised.
  ///
  /// In en, this message translates to:
  /// **'Syncing the board…'**
  String get playSyncing;

  /// Confirm dialog title for leaving a running match.
  ///
  /// In en, this message translates to:
  /// **'Leave the match?'**
  String get playLeaveMatchTitle;

  /// Leaving a running match forfeits it.
  ///
  /// In en, this message translates to:
  /// **'Leaving counts as a forfeit and your entry fee isn\'t returned.'**
  String get playLeaveMatchMessage;

  /// Leaving a practice game.
  ///
  /// In en, this message translates to:
  /// **'Your practice game will end.'**
  String get playLeavePracticeMessage;

  /// Dialog button: confirm leaving the match.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get playLeaveMatchConfirm;

  /// Dialog button: stay in the match.
  ///
  /// In en, this message translates to:
  /// **'Keep playing'**
  String get playKeepPlaying;

  /// Round number after rematches.
  ///
  /// In en, this message translates to:
  /// **'Round {round}'**
  String playRoundLabel(int round);

  /// Overlay while the next round starts.
  ///
  /// In en, this message translates to:
  /// **'Starting the next round…'**
  String get playStartingNextRound;

  /// Tooltip: open the quick chat panel.
  ///
  /// In en, this message translates to:
  /// **'Quick chat'**
  String get playChatOpen;

  /// Quick chat panel title.
  ///
  /// In en, this message translates to:
  /// **'Quick chat'**
  String get playChatTitle;

  /// Quick chat: emotes section.
  ///
  /// In en, this message translates to:
  /// **'Emotes'**
  String get playChatEmotes;

  /// Quick chat: hide other players' messages in this match.
  ///
  /// In en, this message translates to:
  /// **'Mute other players'**
  String get playChatMuteOthers;

  /// Quick chat is muted in Settings.
  ///
  /// In en, this message translates to:
  /// **'Quick chat is muted in Settings.'**
  String get playChatMutedBySettings;

  /// Quick chat is cooling down (client-side limit).
  ///
  /// In en, this message translates to:
  /// **'Next message in {seconds}s'**
  String playChatCooldown(int seconds);

  /// Quick chat message 'gg'.
  ///
  /// In en, this message translates to:
  /// **'Good game!'**
  String get playChatGg;

  /// Quick chat message 'nice_move'.
  ///
  /// In en, this message translates to:
  /// **'Nice move!'**
  String get playChatNiceMove;

  /// Quick chat message 'well_played'.
  ///
  /// In en, this message translates to:
  /// **'Well played!'**
  String get playChatWellPlayed;

  /// Quick chat message 'rematch'.
  ///
  /// In en, this message translates to:
  /// **'Rematch?'**
  String get playChatRematch;

  /// Quick chat message 'again'.
  ///
  /// In en, this message translates to:
  /// **'Let\'s play again.'**
  String get playChatAgain;

  /// Quick chat message 'good_luck'.
  ///
  /// In en, this message translates to:
  /// **'Good luck!'**
  String get playChatGoodLuck;

  /// Quick chat message 'oops'.
  ///
  /// In en, this message translates to:
  /// **'Oops!'**
  String get playChatOops;

  /// Quick chat message 'thanks'.
  ///
  /// In en, this message translates to:
  /// **'Thanks!'**
  String get playChatThanks;

  /// Results title: the local player won.
  ///
  /// In en, this message translates to:
  /// **'You won!'**
  String get playResultYouWon;

  /// Results title: another player won.
  ///
  /// In en, this message translates to:
  /// **'{name} wins!'**
  String playResultWinnerIs(String name);

  /// Results title without a winner.
  ///
  /// In en, this message translates to:
  /// **'Game over'**
  String get playResultGameOver;

  /// Results title: the local player forfeited.
  ///
  /// In en, this message translates to:
  /// **'You left the match'**
  String get playResultYouForfeited;

  /// Results subtitle: won because everyone else forfeited.
  ///
  /// In en, this message translates to:
  /// **'The others forfeited — the win is yours.'**
  String get playResultByForfeit;

  /// Results subtitle after a win.
  ///
  /// In en, this message translates to:
  /// **'Well played!'**
  String get playResultWellPlayed;

  /// Results subtitle: the local player's finishing position.
  ///
  /// In en, this message translates to:
  /// **'You finished #{place}'**
  String playResultYouFinished(int place);

  /// Results: section with the finishing order.
  ///
  /// In en, this message translates to:
  /// **'Finishing order'**
  String get playResultFinishingOrder;

  /// Compact finishing position inside a medal.
  ///
  /// In en, this message translates to:
  /// **'{place}'**
  String playResultPlaceShort(int place);

  /// Accessibility: finishing position.
  ///
  /// In en, this message translates to:
  /// **'Place {place}'**
  String playResultPlaceA11y(int place);

  /// Results: rewards section.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get playRewardsTitle;

  /// Coins won, confirmed by the server; amount is formatted.
  ///
  /// In en, this message translates to:
  /// **'+{amount} coins'**
  String playRewardCoins(String amount);

  /// Wallet balance after the payout; amount is formatted.
  ///
  /// In en, this message translates to:
  /// **'Wallet: {amount} coins'**
  String playRewardCoinsBalance(String amount);

  /// No coins from this match (the server reported no pot, e.g. practice).
  ///
  /// In en, this message translates to:
  /// **'This match doesn\'t pay coins.'**
  String get playRewardNoCoinsMatch;

  /// No coins for a player who did not win.
  ///
  /// In en, this message translates to:
  /// **'No coins this time — the winner takes the pot.'**
  String get playRewardNoCoins;

  /// XP gained in the match (server-confirmed).
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP'**
  String playRewardXp(int xp);

  /// XP not received from the server yet.
  ///
  /// In en, this message translates to:
  /// **'Calculating XP…'**
  String get playRewardXpPending;

  /// XP did not arrive in time.
  ///
  /// In en, this message translates to:
  /// **'Your XP will show on your profile shortly.'**
  String get playRewardXpLater;

  /// Level up after the match.
  ///
  /// In en, this message translates to:
  /// **'Level up! You reached level {level}'**
  String playRewardLevelUp(int level);

  /// Cosmetics unlocked by this match.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get playRewardUnlocked;

  /// Results: rematch section.
  ///
  /// In en, this message translates to:
  /// **'Rematch'**
  String get playRematchTitle;

  /// Button: ask the others for a rematch (accepts it).
  ///
  /// In en, this message translates to:
  /// **'Ask for a rematch'**
  String get playRematchRequest;

  /// Button: accept another player's rematch request.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get playRematchAccept;

  /// Button: decline the rematch.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get playRematchDecline;

  /// Another player asked for a rematch.
  ///
  /// In en, this message translates to:
  /// **'{name} wants a rematch!'**
  String playRematchIncoming(String name);

  /// The local player accepted; waiting for the others.
  ///
  /// In en, this message translates to:
  /// **'You\'re in! Waiting for the others…'**
  String get playRematchWaiting;

  /// The local player declined.
  ///
  /// In en, this message translates to:
  /// **'You declined the rematch.'**
  String get playRematchYouDeclined;

  /// The rematch offer expired or closed.
  ///
  /// In en, this message translates to:
  /// **'Rematch is no longer available.'**
  String get playRematchClosed;

  /// Public matches: a rematch creates a new private room.
  ///
  /// In en, this message translates to:
  /// **'Players who accept move to a new private room together.'**
  String get playRematchPublicNote;

  /// Rematch consent: accepted.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get playRematchStatusAccepted;

  /// Rematch consent: declined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get playRematchStatusDeclined;

  /// Rematch consent: not answered yet.
  ///
  /// In en, this message translates to:
  /// **'Deciding…'**
  String get playRematchStatusPending;

  /// Rematch consent: cannot take part (left / offline).
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get playRematchStatusOut;

  /// Accessibility: a player's rematch answer.
  ///
  /// In en, this message translates to:
  /// **'{name}: {status}'**
  String playRematchSeatA11y(String name, String status);

  /// Results button: find a new match with the same settings.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get playPlayAgain;

  /// In-app banner: a friend invited the user.
  ///
  /// In en, this message translates to:
  /// **'{name} invited you to play {game}'**
  String playInviteIncoming(String name, String game);

  /// Invite banner button: join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get playInviteJoin;

  /// Invite banner button: dismiss.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get playInviteDismiss;

  /// Invite banner fallback sender name.
  ///
  /// In en, this message translates to:
  /// **'A friend'**
  String get playInviteSomeone;

  /// Profile screen title.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// Label of the public friend code (uid).
  ///
  /// In en, this message translates to:
  /// **'Friend code'**
  String get profileFriendCode;

  /// Hint under the friend code.
  ///
  /// In en, this message translates to:
  /// **'Share it so friends can add you.'**
  String get profileFriendCodeHint;

  /// Share-sheet text with the friend code.
  ///
  /// In en, this message translates to:
  /// **'Add me on Ludo Arena! My friend code is {code}'**
  String profileShareFriendCode(String code);

  /// XP still needed for the next level. {xp} is formatted.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP to level {level}'**
  String profileLevelProgress(String xp, int level);

  /// Shown at the maximum level.
  ///
  /// In en, this message translates to:
  /// **'Max level reached'**
  String get profileMaxLevel;

  /// Label of the equipped title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get profileTitleLabel;

  /// Account section header.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get profileAccountSection;

  /// Account type label.
  ///
  /// In en, this message translates to:
  /// **'Account type'**
  String get profileAccountType;

  /// Account type value: unsaved guest.
  ///
  /// In en, this message translates to:
  /// **'Guest (not saved)'**
  String get profileAccountGuest;

  /// Account type value: linked to a provider.
  ///
  /// In en, this message translates to:
  /// **'Saved account'**
  String get profileAccountLinked;

  /// Section listing sign-in providers.
  ///
  /// In en, this message translates to:
  /// **'Sign-in methods'**
  String get profileLinkedAccounts;

  /// Provider status: linked.
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get profileLinked;

  /// Provider status: not linked.
  ///
  /// In en, this message translates to:
  /// **'Not linked'**
  String get profileNotLinked;

  /// Save Progress button on the profile.
  ///
  /// In en, this message translates to:
  /// **'Save progress'**
  String get profileSaveProgressCta;

  /// Total XP label.
  ///
  /// In en, this message translates to:
  /// **'Total XP'**
  String get profileTotalXp;

  /// Progress section header.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get profileStatsSection;

  /// Tooltip and screen-reader label of the pencil button next to the player name.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get profileEditNameTooltip;

  /// Profile: label / tooltip of the tappable avatar that opens the picture picker (owned pictures or the classic avatar).
  ///
  /// In en, this message translates to:
  /// **'Change picture'**
  String get profileChangePicture;

  /// Title of the Profile sheet to pick one of the owned profile pictures (or the classic avatar).
  ///
  /// In en, this message translates to:
  /// **'Choose your picture'**
  String get profilePictureTitle;

  /// Picker choice: the built-in avatar (no Shop picture).
  ///
  /// In en, this message translates to:
  /// **'Classic avatar'**
  String get profilePictureClassic;

  /// Picker empty state: the player owns no profile pictures yet (they are bought in the Shop).
  ///
  /// In en, this message translates to:
  /// **'Pictures you buy in the Shop show up here.'**
  String get profilePictureEmptyMessage;

  /// Picker empty-state button: opens the Shop.
  ///
  /// In en, this message translates to:
  /// **'Visit the Shop'**
  String get profilePictureOpenShop;

  /// Picker link: opens the Shop to buy more pictures.
  ///
  /// In en, this message translates to:
  /// **'Get more in the Shop'**
  String get profilePictureGetMore;

  /// Picker button: loads the next page of owned pictures.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get profilePictureShowMore;

  /// Title of the change-display-name sheet.
  ///
  /// In en, this message translates to:
  /// **'Change your name'**
  String get profileEditNameTitle;

  /// Label of the display-name text field.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get profileNameLabel;

  /// Helper text under the display-name field: the naming rules.
  ///
  /// In en, this message translates to:
  /// **'3–16 characters. Letters, numbers, spaces, _ . and - are allowed.'**
  String get profileNameRules;

  /// Note in the name sheet: where the new name appears; a running game keeps the old name.
  ///
  /// In en, this message translates to:
  /// **'Friends, leaderboards and new games will show your new name. A game in progress keeps the old one.'**
  String get profileNameNote;

  /// Screen-reader text of the name character counter.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} characters'**
  String profileNameCounterSemantics(int count, int max);

  /// Toast after the name was changed. {name} is the new name.
  ///
  /// In en, this message translates to:
  /// **'Your name is now {name}'**
  String profileNameSaved(String name);

  /// Too many name changes (429) without a known wait.
  ///
  /// In en, this message translates to:
  /// **'You\'ve changed your name too often. Please try again later.'**
  String get profileNameChangeLimit;

  /// Too many name changes (429). {wait} is a compact duration like "5 h 12 min".
  ///
  /// In en, this message translates to:
  /// **'You\'ve changed your name too often. Try again in {wait}.'**
  String profileNameChangeLimitRetry(String wait);

  /// Settings screen title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Section header.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// Theme setting label.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// Theme option.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme option.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Theme option: follow the device.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// Language setting label.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Setting label and sheet title: how large amounts are grouped and abbreviated (Indian lakh/crore vs international million/billion).
  ///
  /// In en, this message translates to:
  /// **'Number format'**
  String get settingsNumberSystem;

  /// Short explanation at the top of the number format picker.
  ///
  /// In en, this message translates to:
  /// **'Choose how coin amounts are shown.'**
  String get settingsNumberSystemHint;

  /// Number format option: Indian grouping and lakh/crore (1,00,000 · 10 Lakh).
  ///
  /// In en, this message translates to:
  /// **'Indian'**
  String get settingsNumberSystemIndian;

  /// Number format option: international grouping and million/billion (100,000 · 1M).
  ///
  /// In en, this message translates to:
  /// **'International'**
  String get settingsNumberSystemInternational;

  /// Live example of a number format: one lakh in full and ten lakh compact, e.g. '1,00,000 · 10 Lakh' or '100,000 · 1M'. Both values are already formatted.
  ///
  /// In en, this message translates to:
  /// **'{full} · {compact}'**
  String settingsNumberSystemExample(String full, String compact);

  /// Subtitle of the Number format row: the chosen format's name and its example, e.g. 'Indian (1,00,000 · 10 Lakh)'.
  ///
  /// In en, this message translates to:
  /// **'{system} ({example})'**
  String settingsNumberSystemSummary(String system, String example);

  /// Section header.
  ///
  /// In en, this message translates to:
  /// **'Sound & haptics'**
  String get settingsSoundAndHaptics;

  /// Master sound switch (music and sound effects).
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get settingsSound;

  /// Explains that the Sound switch covers music and sound effects.
  ///
  /// In en, this message translates to:
  /// **'Music and sound effects'**
  String get settingsSoundSubtitle;

  /// Slider label: volume of the sound effects.
  ///
  /// In en, this message translates to:
  /// **'Sound effects volume'**
  String get settingsSfxVolume;

  /// Slider label: volume of the lobby music.
  ///
  /// In en, this message translates to:
  /// **'Music volume'**
  String get settingsMusicVolume;

  /// Toggle for haptic feedback.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get settingsHaptics;

  /// Toggle to reduce animations.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get settingsReducedMotion;

  /// Reduce motion explanation.
  ///
  /// In en, this message translates to:
  /// **'Fewer animations and effects'**
  String get settingsReducedMotionSubtitle;

  /// Shown when the OS already disables animations.
  ///
  /// In en, this message translates to:
  /// **'Also on in your device settings'**
  String get settingsReducedMotionSystemOn;

  /// Section header.
  ///
  /// In en, this message translates to:
  /// **'Gameplay'**
  String get settingsGameplay;

  /// Toggle to hide incoming quick chat.
  ///
  /// In en, this message translates to:
  /// **'Mute quick chat'**
  String get settingsQuickChatMute;

  /// Quick chat mute explanation.
  ///
  /// In en, this message translates to:
  /// **'Hide other players\' chat messages and emotes'**
  String get settingsQuickChatMuteSubtitle;

  /// Section header.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// Analytics consent toggle.
  ///
  /// In en, this message translates to:
  /// **'Share anonymous usage stats'**
  String get settingsAnalytics;

  /// Analytics consent explanation.
  ///
  /// In en, this message translates to:
  /// **'Helps us improve the game. Never includes your name, chats or room codes.'**
  String get settingsAnalyticsSubtitle;

  /// Analytics is not configured in this build.
  ///
  /// In en, this message translates to:
  /// **'Not available in this build'**
  String get settingsAnalyticsNotConfigured;

  /// Section header.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// Current account. {name} is the display name.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String settingsSignedInAs(String name);

  /// Save Progress entry.
  ///
  /// In en, this message translates to:
  /// **'Save progress'**
  String get settingsSaveProgress;

  /// Save Progress entry subtitle.
  ///
  /// In en, this message translates to:
  /// **'Link a sign-in method to keep your progress safe'**
  String get settingsSaveProgressSubtitle;

  /// Switch back to the stored guest account.
  ///
  /// In en, this message translates to:
  /// **'Switch back to guest'**
  String get settingsSwitchToGuest;

  /// Switch to guest subtitle.
  ///
  /// In en, this message translates to:
  /// **'Return to the guest account saved on this device'**
  String get settingsSwitchToGuestSubtitle;

  /// Sign out entry.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// Settings → Account: opens the delete-account confirmation (destructive).
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// Subtitle of the Delete account row.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and its data'**
  String get settingsDeleteAccountSubtitle;

  /// Section header.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// Version label.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// About entry that opens the open-source/legal notices web page in the external browser.
  ///
  /// In en, this message translates to:
  /// **'Legal notices'**
  String get settingsLegalNotices;

  /// Legal notices entry subtitle (the page opens outside the app).
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses · opens in your browser'**
  String get settingsLegalNoticesSubtitle;

  /// Toast when the legal notices page could not be opened in the browser.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the page. Please try again later.'**
  String get settingsLegalNoticesOpenFailed;

  /// First-run analytics consent sheet title.
  ///
  /// In en, this message translates to:
  /// **'Help us make Ludo Arena better'**
  String get settingsConsentTitle;

  /// First-run analytics consent explanation (opt-in).
  ///
  /// In en, this message translates to:
  /// **'Can we collect anonymous usage stats, like which game modes are popular? We never collect your name, chats, room codes or contact details. You can change this any time in Settings.'**
  String get settingsConsentMessage;

  /// Opt in to analytics.
  ///
  /// In en, this message translates to:
  /// **'Share anonymous stats'**
  String get settingsConsentAllow;

  /// Decline analytics.
  ///
  /// In en, this message translates to:
  /// **'No thanks'**
  String get settingsConsentDeny;

  /// Screen-reader action hint on an opponent pod.
  ///
  /// In en, this message translates to:
  /// **'Show player options'**
  String get socialPodOptionsHint;

  /// Player sheet: friend request already sent.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get socialRequestSent;

  /// Player sheet: accept their friend request.
  ///
  /// In en, this message translates to:
  /// **'Accept request'**
  String get socialAcceptRequest;

  /// Player sheet: open the report flow.
  ///
  /// In en, this message translates to:
  /// **'Report player'**
  String get socialReportPlayer;

  /// Player sheet: this player was already reported (disabled).
  ///
  /// In en, this message translates to:
  /// **'Reported'**
  String get socialReported;

  /// Player sheet: hide this player's quick chat and emotes on this device.
  ///
  /// In en, this message translates to:
  /// **'Mute player'**
  String get socialMutePlayer;

  /// Player sheet: show this muted player's quick chat and emotes again.
  ///
  /// In en, this message translates to:
  /// **'Unmute player'**
  String get socialUnmutePlayer;

  /// Player sheet: shown under Unmute while the player is muted.
  ///
  /// In en, this message translates to:
  /// **'You won\'t see this player\'s chat or emotes.'**
  String get socialMutedNote;

  /// Player was reported in the last 24 hours (also 409 already_reported).
  ///
  /// In en, this message translates to:
  /// **'You reported this player in the last 24 hours.'**
  String get socialAlreadyReported;

  /// Remaining reports in the rolling 24 hours.
  ///
  /// In en, this message translates to:
  /// **'Reports left today: {remaining} of {total}'**
  String socialReportsLeft(int remaining, int total);

  /// Daily report limit reached (429 report_limit), with the local reset time.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used today\'s {total} reports. You can report again at {time}.'**
  String socialReportLimitAt(int total, String time);

  /// Daily report limit reached, reset time unknown.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used today\'s {total} reports. Try again later.'**
  String socialReportLimitLater(int total);

  /// Report step header.
  ///
  /// In en, this message translates to:
  /// **'Report {name}'**
  String socialReportTitle(String name);

  /// Report step: reason picker label.
  ///
  /// In en, this message translates to:
  /// **'What happened?'**
  String get socialReportWhy;

  /// Report reason.
  ///
  /// In en, this message translates to:
  /// **'Cheating'**
  String get socialReasonCheating;

  /// Report reason.
  ///
  /// In en, this message translates to:
  /// **'Offensive name'**
  String get socialReasonOffensiveName;

  /// Report reason (wire value abusive_behavior): harassment, insults or abusive quick chat.
  ///
  /// In en, this message translates to:
  /// **'Harassment or abusive chat'**
  String get socialReasonAbusiveBehavior;

  /// Report reason.
  ///
  /// In en, this message translates to:
  /// **'Leaving or stalling'**
  String get socialReasonLeavingOrStalling;

  /// Report reason.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get socialReasonOther;

  /// Report step: what happens next.
  ///
  /// In en, this message translates to:
  /// **'Our team reviews every report. Follow its status in the Reported tab on the Friends screen.'**
  String get socialReportReviewNote;

  /// Report step: confirm button.
  ///
  /// In en, this message translates to:
  /// **'Send report'**
  String get socialSendReport;

  /// Toast after a report was stored.
  ///
  /// In en, this message translates to:
  /// **'Report sent. {remaining} of {total} reports left today.'**
  String socialReportSent(int remaining, int total);

  /// Friend limit reached: adding/accepting is disabled.
  ///
  /// In en, this message translates to:
  /// **'You can have up to {max} friends — remove one to add more.'**
  String socialFriendLimitNote(int max);

  /// Error cannot_report_self.
  ///
  /// In en, this message translates to:
  /// **'You can\'t report yourself.'**
  String get socialErrorCannotReportSelf;

  /// Error cannot_report_bot. Never mention bots (players are not labelled).
  ///
  /// In en, this message translates to:
  /// **'This player can\'t be reported.'**
  String get socialErrorCannotReportBot;

  /// Error not_in_room while reporting.
  ///
  /// In en, this message translates to:
  /// **'You can only report players from a match you\'re in.'**
  String get socialErrorNotInRoom;

  /// Error room_not_found while reporting.
  ///
  /// In en, this message translates to:
  /// **'This match can\'t be found anymore, so the report wasn\'t sent.'**
  String get socialErrorRoomNotFound;

  /// Error not_found while reporting.
  ///
  /// In en, this message translates to:
  /// **'This player couldn\'t be found.'**
  String get socialErrorPlayerNotFound;

  /// Friends screen tab: my reports.
  ///
  /// In en, this message translates to:
  /// **'Reported'**
  String get socialTabReported;

  /// Friends tab section header: friends online now.
  ///
  /// In en, this message translates to:
  /// **'Online now ({count})'**
  String socialOnlineNow(int count);

  /// Friends tab section header: offline friends.
  ///
  /// In en, this message translates to:
  /// **'Offline ({count})'**
  String socialOfflineCount(int count);

  /// Friends tab header: accepted friends of the maximum.
  ///
  /// In en, this message translates to:
  /// **'Friends {count}/{max}'**
  String socialFriendsCount(int count, int max);

  /// Reported tab: when reports are available again.
  ///
  /// In en, this message translates to:
  /// **'You can report again at {time}.'**
  String socialReportsResetAt(String time);

  /// Reported tab: explanation of the daily limit.
  ///
  /// In en, this message translates to:
  /// **'You can report up to {total} players a day. Our team reviews every report.'**
  String socialReportsInfo(int total);

  /// Reported tab empty state title.
  ///
  /// In en, this message translates to:
  /// **'No reports'**
  String get socialNoReportsTitle;

  /// Reported tab empty state message.
  ///
  /// In en, this message translates to:
  /// **'Players you report from a match show up here with the status of each report.'**
  String get socialNoReportsMessage;

  /// Report status chip.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get socialStatusSubmitted;

  /// Report status chip.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get socialStatusReviewing;

  /// Report status chip.
  ///
  /// In en, this message translates to:
  /// **'Action taken'**
  String get socialStatusActionTaken;

  /// Report status chip.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get socialStatusDismissed;

  /// Relative time: under a minute ago.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get socialJustNow;

  /// Relative time in minutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String socialMinutesAgo(int minutes);

  /// Relative time in hours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h ago'**
  String socialHoursAgo(int hours);

  /// Relative time: the previous day.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get socialYesterday;

  /// Screen-reader text for a report status chip.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String socialReportStatusA11y(String status);

  /// Title of the Shop screen (profile pictures and cosmetics for sale that the player does not own yet).
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get storeTitle;

  /// Shop header card title.
  ///
  /// In en, this message translates to:
  /// **'Profile pictures'**
  String get storeHeroTitle;

  /// Shop header card text: pictures are bought once and owned forever.
  ///
  /// In en, this message translates to:
  /// **'Buy once with diamonds and keep it forever.'**
  String get storeHeroSubtitle;

  /// Shop header card of a cosmetic category (dice, tokens, boards, ...): fixed prices, no randomness, cosmetic only, owned forever.
  ///
  /// In en, this message translates to:
  /// **'Fixed prices, nothing random. Cosmetic only, and yours forever.'**
  String get storeCosmeticsHeroSubtitle;

  /// Shop filter pill: animated (Lottie) pictures.
  ///
  /// In en, this message translates to:
  /// **'Animated'**
  String get storeFilterAnimated;

  /// Shop filter pill: still images.
  ///
  /// In en, this message translates to:
  /// **'Static'**
  String get storeFilterStatic;

  /// Detail sheet subtitle for an animated profile picture.
  ///
  /// In en, this message translates to:
  /// **'Animated picture'**
  String get storeKindAnimated;

  /// Detail sheet subtitle for a still profile picture.
  ///
  /// In en, this message translates to:
  /// **'Picture'**
  String get storeKindStatic;

  /// Button: use this owned picture as your profile picture.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get storeApply;

  /// Picture sheet, right after buying in the Shop: use the new picture now.
  ///
  /// In en, this message translates to:
  /// **'Apply now'**
  String get storeApplyNow;

  /// Button: stop using the applied picture and go back to the built-in avatar.
  ///
  /// In en, this message translates to:
  /// **'Use classic avatar'**
  String get storeRemove;

  /// Toast after the server applied a profile picture.
  ///
  /// In en, this message translates to:
  /// **'Picture applied!'**
  String get storeAppliedToast;

  /// Toast after going back to the built-in avatar.
  ///
  /// In en, this message translates to:
  /// **'Back to your classic avatar.'**
  String get storeRemovedToast;

  /// Toast after buying a profile picture.
  ///
  /// In en, this message translates to:
  /// **'{name} is yours forever!'**
  String storePurchasedToast(String name);

  /// Note under Apply: rooms already joined keep the previous picture.
  ///
  /// In en, this message translates to:
  /// **'Shows on your profile now, and to other players from your next match.'**
  String get storeNextMatchNote;

  /// Empty state of the Owned filter.
  ///
  /// In en, this message translates to:
  /// **'No pictures yet'**
  String get storeEmptyOwnedTitle;

  /// Empty state of a Shop filter.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get storeEmptyTitle;

  /// Empty state of a Shop filter.
  ///
  /// In en, this message translates to:
  /// **'New pictures are on their way.'**
  String get storeEmptyMessage;

  /// Shop category where the player already owns every item for sale.
  ///
  /// In en, this message translates to:
  /// **'You own them all!'**
  String get storeAllOwnedTitle;

  /// Shop category where the player already owns every item for sale: they are in the Collection.
  ///
  /// In en, this message translates to:
  /// **'Everything here is already in your Collection.'**
  String get storeAllOwnedMessage;

  /// Button after buying in the Shop (or when a Shop category is all owned): open that category of the Collection Room.
  ///
  /// In en, this message translates to:
  /// **'View in Collection'**
  String get storeViewInCollection;

  /// Inline error at the end of the Shop grid (next page failed).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load more pictures.'**
  String get storeLoadMoreFailed;

  /// Screen-reader label of a Shop tile: picture name and its price or state.
  ///
  /// In en, this message translates to:
  /// **'{name}, {status}'**
  String storeTileSemantics(String name, String status);

  /// Shop Emotes category header card title, and the section title of the animated Store emotes (Shop and Collection).
  ///
  /// In en, this message translates to:
  /// **'Animated emotes'**
  String get storeEmotesHeroTitle;

  /// Shop Emotes category header card text: emotes are sent in matches, bought once with diamonds and owned forever.
  ///
  /// In en, this message translates to:
  /// **'Send them in any match. Buy once with diamonds, keep them forever.'**
  String get storeEmotesHeroSubtitle;

  /// Emote sheet subtitle: an animated emote from the Shop.
  ///
  /// In en, this message translates to:
  /// **'Animated emote'**
  String get storeEmoteKind;

  /// Note on an owned Store emote: how to send it during a match (the quick-chat button).
  ///
  /// In en, this message translates to:
  /// **'Send it from the chat button during a match.'**
  String get storeEmoteUseInMatchNote;

  /// Inline error at the end of an emote grid (next page failed).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load more emotes.'**
  String get storeEmotesLoadMoreFailed;

  /// Collection Emotes tab, animated section: none bought yet.
  ///
  /// In en, this message translates to:
  /// **'Animated emotes you buy in the Shop show up here.'**
  String get storeEmotesOwnedEmpty;

  /// Wallet sheet title.
  ///
  /// In en, this message translates to:
  /// **'Your wallet'**
  String get walletTitle;

  /// What coins are for.
  ///
  /// In en, this message translates to:
  /// **'For match entry fees — winners take the pot.'**
  String get walletCoinsCaption;

  /// What diamonds are for.
  ///
  /// In en, this message translates to:
  /// **'For premium cosmetics in the Collection Room.'**
  String get walletDiamondsCaption;

  /// Full-precision balance. {amount} is formatted.
  ///
  /// In en, this message translates to:
  /// **'Exact balance: {amount}'**
  String walletExactBalance(String amount);

  /// Heading of the virtual-currency notice.
  ///
  /// In en, this message translates to:
  /// **'Virtual currency'**
  String get walletVirtualTitle;

  /// Non-redeemable virtual currency notice.
  ///
  /// In en, this message translates to:
  /// **'Coins and diamonds are virtual items for fun only. They have no real-world value and can\'t be sold, transferred, withdrawn or exchanged for money.'**
  String get walletVirtualNotice;

  /// Heading of the earning tips.
  ///
  /// In en, this message translates to:
  /// **'How to earn more'**
  String get walletEarnTitle;

  /// Earning tip.
  ///
  /// In en, this message translates to:
  /// **'Win matches to take the pot'**
  String get walletEarnWins;

  /// Earning tip.
  ///
  /// In en, this message translates to:
  /// **'Complete daily and weekly missions'**
  String get walletEarnMissions;

  /// Earning tip.
  ///
  /// In en, this message translates to:
  /// **'Level up for milestone rewards'**
  String get walletEarnLevels;

  /// Button to re-fetch the balance from the server.
  ///
  /// In en, this message translates to:
  /// **'Refresh balance'**
  String get walletRefresh;

  /// Screen-reader label of the coin balance chip.
  ///
  /// In en, this message translates to:
  /// **'Coins: {amount}'**
  String widgetsCoinsBalance(String amount);

  /// Screen-reader label of the diamond balance chip.
  ///
  /// In en, this message translates to:
  /// **'Diamonds: {amount}'**
  String widgetsDiamondsBalance(String amount);

  /// Screen-reader label of the XP progress bar.
  ///
  /// In en, this message translates to:
  /// **'Experience: {current} of {total}'**
  String widgetsXpLabel(String current, String total);

  /// Screen-reader label of a player avatar when no name is given.
  ///
  /// In en, this message translates to:
  /// **'Player avatar'**
  String get widgetsAvatarLabel;

  /// Screen-reader label of a player title chip.
  ///
  /// In en, this message translates to:
  /// **'Title: {title}'**
  String widgetsTitleLabel(String title);

  /// Screen-reader label of an emote icon.
  ///
  /// In en, this message translates to:
  /// **'Emote: {name}'**
  String widgetsEmoteLabel(String name);

  /// Screen-reader label of a badge icon.
  ///
  /// In en, this message translates to:
  /// **'Badge: {name}'**
  String widgetsBadgeLabel(String name);

  /// Screen-reader label of a turn countdown ring.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{1 second left} other{{seconds} seconds left}}'**
  String widgetsSecondsLeft(int seconds);

  /// Screen-reader label of the connection indicator. {status} is a localized status such as Online.
  ///
  /// In en, this message translates to:
  /// **'Connection: {status}'**
  String widgetsConnectionLabel(String status);

  /// Screen-reader suffix for a notification count on a round header button.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new} other{{count} new}}'**
  String widgetsNewItems(int count);

  /// Screen-reader hint for the selected option in a choice selector.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get widgetsSelected;

  /// Screen-reader label of the painted app logo.
  ///
  /// In en, this message translates to:
  /// **'{appName} crest'**
  String widgetsLogoLabel(String appName);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'hi', 'id', 'ur'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'id':
      return AppLocalizationsId();
    case 'ur':
      return AppLocalizationsUr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
