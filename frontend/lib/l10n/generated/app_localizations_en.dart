// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get authWelcomeTitle => 'Ready to rule the board?';

  @override
  String get authWelcomeSubtitle =>
      'Play Ludo and Snakes & Ladders with friends and players everywhere.';

  @override
  String get authContinueWithGoogle => 'Continue with Google';

  @override
  String get authContinueWithFacebook => 'Continue with Facebook';

  @override
  String get authContinueWithApple => 'Sign in with Apple';

  @override
  String get authPlayAsGuest => 'Play as guest';

  @override
  String get authGuestHint =>
      'Start instantly — you can save your progress any time.';

  @override
  String get authOrDivider => 'or';

  @override
  String get authFairPlayNote =>
      'Coins and diamonds are virtual and can\'t be exchanged for real money.';

  @override
  String get authSessionExpiredBanner =>
      'You were signed out. Please sign in again.';

  @override
  String get authSignedInElsewhereTitle => 'Signed in on another device';

  @override
  String get authSignedInElsewhereMessage =>
      'Someone signed in to your account on another device, so you\'ve been signed out here. Only one device can be signed in at a time. Sign in again to play here — the other device will be signed out.';

  @override
  String get authSignedInElsewhereBanner =>
      'Your account was signed in on another device.';

  @override
  String get authAccountDeleted => 'Your account was deleted.';

  @override
  String get authDeleteAccountTitle => 'Delete your account?';

  @override
  String get authDeleteAccountIntro =>
      'This permanently deletes your account and everything in it:';

  @override
  String get authDeleteAccountItemWallet => 'Coins and diamonds';

  @override
  String get authDeleteAccountItemProgress => 'Level, XP and missions';

  @override
  String get authDeleteAccountItemCollection => 'Collection Room items';

  @override
  String get authDeleteAccountItemFriends => 'Friends and friend requests';

  @override
  String get authDeleteAccountWarning =>
      'This can\'t be undone. If you play again later, you\'ll start with a new account.';

  @override
  String get authDeleteAccountConfirmCheck =>
      'I understand that my account and progress will be deleted forever.';

  @override
  String get authDeleteAccountConfirm => 'Delete account';

  @override
  String get authDeleteAccountFailed =>
      'Your account was not deleted. Check your connection and try again.';

  @override
  String get authChangeLanguage => 'Change language';

  @override
  String get authProviderGoogle => 'Google';

  @override
  String get authProviderFacebook => 'Facebook';

  @override
  String get authProviderApple => 'Apple';

  @override
  String get authProviderGuest => 'Guest';

  @override
  String get authSaveProgressTitle => 'Save your progress';

  @override
  String get authSaveProgressSubtitle =>
      'Link a sign-in method so your coins, level and collection are never lost — even on a new phone.';

  @override
  String get authSaveBenefitKeep => 'Keep all your coins, XP and cosmetics';

  @override
  String get authSaveBenefitDevices => 'Sign in on any device';

  @override
  String get authSaveBenefitSame => 'Same account — nothing is reset or moved';

  @override
  String get authSaveWithGoogle => 'Save with Google';

  @override
  String get authSaveWithFacebook => 'Save with Facebook';

  @override
  String get authSaveWithApple => 'Save with Apple';

  @override
  String get authSaveNoProviders =>
      'No sign-in methods are available in this build.';

  @override
  String get authLinkSuccessTitle => 'Progress saved!';

  @override
  String authLinkSuccessMessage(String provider) {
    return 'Your account is now linked to $provider. Sign in with $provider on any device to continue.';
  }

  @override
  String get authAlreadySavedTitle => 'Your progress is saved';

  @override
  String get authAlreadySavedMessage =>
      'This account is linked to a sign-in method, so your progress is safe.';

  @override
  String authConflictTitle(String provider) {
    return 'This $provider account is already in use';
  }

  @override
  String authConflictMessage(String provider) {
    return 'That $provider account already has its own Ludo Arena account. Nothing will be merged or moved between the two accounts.';
  }

  @override
  String get authConflictSignIn => 'Sign in to that account';

  @override
  String get authConflictGuestNote =>
      'Your guest account stays on this device — you can switch back to it from Settings.';

  @override
  String get authAlreadyLinkedTitle => 'Already linked';

  @override
  String authAlreadyLinkedMessage(String provider) {
    return 'This account is already linked to a different $provider account.';
  }

  @override
  String get authLogoutTitle => 'Sign out?';

  @override
  String get authLogoutMessage =>
      'You can sign back in any time with the same method.';

  @override
  String get authLogoutConfirm => 'Sign out';

  @override
  String get authGuestLogoutTitle => 'Sign out of your guest account?';

  @override
  String get authSaveProgressFirst => 'Save progress first';

  @override
  String get authSwitchToGuestTitle => 'Switch back to guest?';

  @override
  String get authSwitchToGuestMessage =>
      'You\'ll leave this account and continue with the guest account saved on this device.';

  @override
  String get authSwitchToGuestConfirm => 'Switch to guest';

  @override
  String get authGuestUnavailable =>
      'That guest account is no longer available.';

  @override
  String authWelcomeBack(String name) {
    return 'Welcome, $name!';
  }

  @override
  String get authGuestLogoutKeptMessage =>
      'Your coins, level and collection stay on this device. Tap “Play as guest” to carry on where you left off. Save your progress to keep them on a new phone too.';

  @override
  String get boardsColorRed => 'Red';

  @override
  String get boardsColorGreen => 'Green';

  @override
  String get boardsColorYellow => 'Yellow';

  @override
  String get boardsColorBlue => 'Blue';

  @override
  String get boardsLudoBoardLabel => 'Ludo board';

  @override
  String get boardsSnakesBoardLabel => 'Snakes and Ladders board';

  @override
  String boardsTokenInBase(String color, int number) {
    return '$color token $number, in base';
  }

  @override
  String boardsTokenStepsFromHome(String color, int number, int steps) {
    String _temp0 = intl.Intl.pluralLogic(
      steps,
      locale: localeName,
      other: '$steps squares from home',
      one: '1 square from home',
    );
    return '$color token $number, $_temp0';
  }

  @override
  String boardsTokenHome(String color, int number) {
    return '$color token $number, finished';
  }

  @override
  String get boardsTokenCanMove => 'can move';

  @override
  String get boardsTokenMoveHint => 'move this token';

  @override
  String get boardsCurrentTurn => 'current turn';

  @override
  String boardsSnakesTokenOnSquare(String color, int square) {
    return '$color token on square $square';
  }

  @override
  String boardsSnakesTokenAtStart(String color) {
    return '$color token at the start';
  }

  @override
  String boardsDiceShowing(int value) {
    return 'Dice showing $value';
  }

  @override
  String get boardsDiceRolling => 'Dice rolling';

  @override
  String get boardsDiceRollHint => 'roll the dice';

  @override
  String get boardsVictoryCelebration => 'Victory celebration';

  @override
  String get boardsLevelUp => 'Level up';

  @override
  String get coinsCategory => 'Coins';

  @override
  String get coinsHeroTitle => 'Coin packs';

  @override
  String get coinsHeroSubtitle =>
      'More coins for more matches. Every pack comes with bonus diamonds.';

  @override
  String get coinsPackStarter => 'Starter';

  @override
  String get coinsPackPopular => 'Popular';

  @override
  String get coinsPackGreatValue => 'Great Value';

  @override
  String get coinsPackBestValue => 'Best Value';

  @override
  String coinsPackCoins(String amount) {
    return '$amount coins';
  }

  @override
  String coinsPackDiamonds(String amount) {
    return '+$amount diamonds';
  }

  @override
  String coinsPackSemantics(
    String pack,
    String coins,
    String diamonds,
    String price,
  ) {
    return '$pack: $coins coins and $diamonds diamonds for $price';
  }

  @override
  String coinsBuyFor(String price) {
    return 'Buy for $price';
  }

  @override
  String get coinsGrantedTitle => 'Coins added!';

  @override
  String coinsGrantedMessage(String coins, String diamonds) {
    return '$coins coins and $diamonds diamonds are now in your wallet.';
  }

  @override
  String get coinsBuyFailed =>
      'The purchase didn\'t go through. Please try again.';

  @override
  String get coinsDelayed =>
      'Your purchase is safe. We\'ll add the coins as soon as we can reach the game server.';

  @override
  String get coinsNote =>
      'Coins and diamonds are virtual items with no cash value. Payments are handled by Google Play or the App Store.';

  @override
  String get coinsErrorUnavailable => 'This pack isn\'t available yet.';

  @override
  String get coinsErrorInvalid =>
      'This purchase couldn\'t be verified, so nothing was added.';

  @override
  String get coinsErrorPending =>
      'Your payment is pending. The coins arrive as soon as it completes.';

  @override
  String get coinsErrorStoreUnreachable =>
      'The store couldn\'t be reached. Your purchase is safe and will be added automatically.';

  @override
  String get commonOk => 'OK';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonClose => 'Close';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonBack => 'Back';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSave => 'Save';

  @override
  String get commonLater => 'Later';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopied => 'Copied!';

  @override
  String get commonShare => 'Share';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonSomethingWentWrong => 'Something went wrong.';

  @override
  String get commonNothingHereYet => 'Nothing here yet';

  @override
  String get commonYou => 'You';

  @override
  String get commonGuest => 'Guest';

  @override
  String get commonCoins => 'Coins';

  @override
  String get commonDiamonds => 'Diamonds';

  @override
  String commonLevel(int level) {
    return 'Level $level';
  }

  @override
  String commonLevelShort(int level) {
    return 'Lv $level';
  }

  @override
  String commonXpProgress(String current, String total) {
    return '$current / $total XP';
  }

  @override
  String get commonConnectionConnected => 'Online';

  @override
  String get commonConnectionConnecting => 'Connecting…';

  @override
  String get commonConnectionReconnecting => 'Reconnecting…';

  @override
  String get commonConnectionOffline => 'Offline';

  @override
  String get commonConnectionReplaced => 'This game is open somewhere else';

  @override
  String get commonReconnect => 'Reconnect';

  @override
  String commonSecondsShort(int seconds) {
    return '${seconds}s';
  }

  @override
  String get commonGameLudo => 'Ludo';

  @override
  String get commonGameSnakesLadders => 'Snakes & Ladders';

  @override
  String get commonVariantClassic => 'Classic';

  @override
  String get commonVariantQuick => 'Quick';

  @override
  String commonPlayerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count players',
      one: '1 player',
    );
    return '$_temp0';
  }

  @override
  String get commonOfflineHint =>
      'You\'re offline. Check your connection and try again.';

  @override
  String commonEntryFee(String amount) {
    return 'Entry $amount';
  }

  @override
  String get commonFree => 'Free';

  @override
  String get connectionLostTitle => 'Connection lost';

  @override
  String get connectionLostMessage =>
      'Reconnecting… You can continue as soon as you\'re back online.';

  @override
  String get connectionLostMatchHint =>
      'Your match keeps running. Missed turns are played for you automatically.';

  @override
  String get connectionLostRetryNow => 'Try now';

  @override
  String get connectionBackOnline => 'Back online';

  @override
  String get appTitle => 'Ludo Arena';

  @override
  String get languageNameNative => 'English';

  @override
  String get cosmeticDiceClassic => 'Classic Ivory';

  @override
  String get cosmeticDiceNeon => 'Neon Pulse';

  @override
  String get cosmeticDiceGolden => 'Royal Gold';

  @override
  String get cosmeticDiceAutumn => 'Autumn Leaf';

  @override
  String get cosmeticTokenClassic => 'Classic Pawn';

  @override
  String get cosmeticTokenGem => 'Gemstone';

  @override
  String get cosmeticTokenRoyal => 'Royal Pawn';

  @override
  String get cosmeticTokenCrown => 'Crown Piece';

  @override
  String get cosmeticLudoBoardClassic => 'Classic';

  @override
  String get cosmeticLudoBoardMidnight => 'Midnight Marble';

  @override
  String get cosmeticLudoBoardRoyal => 'Royal Court';

  @override
  String get cosmeticSnakesBoardClassic => 'Classic Meadow';

  @override
  String get cosmeticSnakesBoardJungle => 'Jungle Temple';

  @override
  String get cosmeticSnakesBoardCandy => 'Candy Land';

  @override
  String get cosmeticTrailNone => 'No Trail';

  @override
  String get cosmeticTrailSparkle => 'Sparkle';

  @override
  String get cosmeticTrailComet => 'Comet';

  @override
  String get cosmeticVictoryConfetti => 'Confetti';

  @override
  String get cosmeticVictoryFireworks => 'Fireworks';

  @override
  String get cosmeticVictoryCrown => 'Golden Crown';

  @override
  String get cosmeticFrameNone => 'No Frame';

  @override
  String get cosmeticFrameBronze => 'Bronze Ring';

  @override
  String get cosmeticFrameSilver => 'Silver Laurel';

  @override
  String get cosmeticFrameGold => 'Gold Laurel';

  @override
  String get cosmeticFrameRoyal => 'Royal Crest';

  @override
  String get cosmeticTitleRookie => 'Rookie';

  @override
  String get cosmeticTitleStrategist => 'Strategist';

  @override
  String get cosmeticTitleDiceMaster => 'Dice Master';

  @override
  String get cosmeticTitleRoyal => 'Royal Highness';

  @override
  String get cosmeticTitleWeeklyChampion => 'Weekly Champion';

  @override
  String get cosmeticBadgeFirstWin => 'First Victory';

  @override
  String get cosmeticBadgeFriendly => 'Good Company';

  @override
  String get cosmeticEmoteWave => 'Wave';

  @override
  String get cosmeticEmoteThumbs => 'Thumbs Up';

  @override
  String get cosmeticEmoteLaugh => 'Laugh';

  @override
  String get cosmeticEmoteWow => 'Wow';

  @override
  String get cosmeticEmoteCrown => 'Crown';

  @override
  String get cosmeticRarityCommon => 'Common';

  @override
  String get cosmeticRarityRare => 'Rare';

  @override
  String get cosmeticRarityEpic => 'Epic';

  @override
  String get cosmeticRarityLegendary => 'Legendary';

  @override
  String get cosmeticKindDice => 'Dice';

  @override
  String get cosmeticKindToken => 'Tokens';

  @override
  String get cosmeticKindLudoBoard => 'Ludo board';

  @override
  String get cosmeticKindSnakesBoard => 'Snakes & Ladders board';

  @override
  String get cosmeticKindFrame => 'Avatar frame';

  @override
  String get cosmeticKindTitle => 'Title';

  @override
  String get cosmeticKindBadge => 'Badge';

  @override
  String get cosmeticKindEmote => 'Emote';

  @override
  String get cosmeticKindVictory => 'Victory celebration';

  @override
  String get cosmeticKindTrail => 'Token trail';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorBadRequest => 'That request couldn\'t be processed.';

  @override
  String get errorUnknownType =>
      'This action isn\'t supported. Please update the app.';

  @override
  String get errorRateLimited =>
      'You\'re going a bit fast! Wait a moment and try again.';

  @override
  String get errorUnauthorized =>
      'Your session has expired. Please sign in again.';

  @override
  String get errorUpdateRequired => 'A newer version of the app is required.';

  @override
  String get errorMaintenance =>
      'The game servers are under maintenance. Please try again soon.';

  @override
  String get errorNotInRoom => 'You\'re not in this room anymore.';

  @override
  String get errorRoomNotFound => 'This room doesn\'t exist anymore.';

  @override
  String get errorRoomFull => 'This room is already full.';

  @override
  String get errorRoomInProgress => 'This game has already started.';

  @override
  String get errorRoomClosed => 'This room has been closed.';

  @override
  String get errorAlreadyInRoom =>
      'You\'re already in a room. Leave it first to join another.';

  @override
  String get errorNotHost => 'Only the host can do that.';

  @override
  String get errorNotEnoughPlayers => 'At least 2 players are needed to start.';

  @override
  String get errorPlayersNotReady => 'Waiting for all players to be ready.';

  @override
  String get errorNotYourTurn => 'It\'s not your turn yet.';

  @override
  String get errorInvalidPhase => 'You can\'t do that right now.';

  @override
  String get errorIllegalMove => 'That move isn\'t allowed.';

  @override
  String get errorStaleState => 'The board just changed. Try again.';

  @override
  String get errorInsufficientFunds => 'You don\'t have enough coins for this.';

  @override
  String get errorInvalidCode =>
      'That room code isn\'t valid. Check it and try again.';

  @override
  String get errorRematchClosed => 'The rematch window has closed.';

  @override
  String get errorNotFriends => 'You can only invite friends.';

  @override
  String get errorItemNotOwned => 'You don\'t own this item yet.';

  @override
  String get errorBotsUnavailable =>
      'No computer players are available right now. Try again in a moment.';

  @override
  String get errorBotsNotAllowed =>
      'Computer players aren\'t allowed in this room.';

  @override
  String get errorInternal =>
      'Something went wrong on our side. Please try again.';

  @override
  String get errorClientVersionRequired =>
      'The app couldn\'t identify its version. Please update or reinstall it.';

  @override
  String get errorEnvironmentMismatch =>
      'This app build is connected to the wrong server.';

  @override
  String get errorInvalidCredential => 'Sign-in failed. Please try again.';

  @override
  String get errorRefreshReused =>
      'For your security, you\'ve been signed out. Please sign in again.';

  @override
  String get errorSessionReplaced =>
      'Your account was signed in on another device. Please sign in again.';

  @override
  String get errorForbidden => 'You don\'t have permission to do that.';

  @override
  String get errorNotFound => 'We couldn\'t find what you were looking for.';

  @override
  String get errorIdentityConflict =>
      'This sign-in account already belongs to a different player profile.';

  @override
  String get errorProviderAlreadyLinked =>
      'Your profile already has a different account of this type linked.';

  @override
  String get errorAlreadyOwned => 'You already own this item.';

  @override
  String get errorAlreadyClaimed => 'You\'ve already claimed this reward.';

  @override
  String get errorAlreadyFriends => 'You\'re already friends.';

  @override
  String get errorNotCompleted =>
      'Finish this mission first to claim the reward.';

  @override
  String get errorItemLocked => 'This item is still locked.';

  @override
  String get errorAssetsUnavailable =>
      'Pictures can\'t be downloaded right now. Please try again later.';

  @override
  String get errorProviderUnavailable =>
      'The sign-in service is unavailable right now. Please try again later.';

  @override
  String get errorNetwork =>
      'Can\'t reach the game service. Check your internet connection.';

  @override
  String get errorTimeout => 'The connection timed out. Please try again.';

  @override
  String get errorBadResponse =>
      'We got an unexpected response. Please try again.';

  @override
  String get errorCancelled => 'Cancelled.';

  @override
  String get errorNotConnected =>
      'You\'re not connected right now. Reconnecting…';

  @override
  String errorRateLimitedRetry(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Too many tries. Try again in $seconds seconds.',
      one: 'Too many tries. Try again in 1 second.',
    );
    return '$_temp0';
  }

  @override
  String get errorInvalidName =>
      'That name can\'t be used. Please choose another one.';

  @override
  String get errorInvalidNameTooShort =>
      'Your name needs at least 3 characters.';

  @override
  String get errorInvalidNameTooLong =>
      'Your name can have at most 16 characters.';

  @override
  String get errorInvalidNameCharacters =>
      'Use only letters, numbers, spaces, _ . or - (with at least one letter). No emoji or symbols.';

  @override
  String get errorInvalidNameReserved =>
      'That name is reserved. Please choose another one.';

  @override
  String get errorInvalidNameInappropriate =>
      'That name isn\'t allowed. Please choose a friendly one.';

  @override
  String get gateSplashTagline => 'Roll. Race. Rule.';

  @override
  String get gateStatusChecking => 'Checking the game servers…';

  @override
  String get gateStatusSigningIn => 'Signing you in…';

  @override
  String get gateStatusLoadingProfile => 'Loading your profile…';

  @override
  String get gateUpdateNow => 'Update now';

  @override
  String get gateForceUpdateTitle => 'Update required';

  @override
  String get gateForceUpdateMessage =>
      'This version of Ludo Arena is no longer supported. Update to keep playing online — your coins and progress are safe.';

  @override
  String get gateInstalledVersion => 'Installed version';

  @override
  String get gateRequiredVersion => 'Required version';

  @override
  String get gateStoreNotReadyTitle => 'Update not yet available in the store';

  @override
  String get gateStoreNotReadyMessage =>
      'The new version is on its way to your app store. Please check again in a little while.';

  @override
  String get gateCheckAgain => 'Check again';

  @override
  String get gateOptionalUpdateTitle => 'A new version is available';

  @override
  String gateOptionalUpdateMessage(String version) {
    return 'Version $version brings fixes and improvements. Update now for the smoothest games.';
  }

  @override
  String get gateMaintenanceTitle => 'We\'re polishing the boards';

  @override
  String get gateMaintenanceMessage =>
      'Ludo Arena is down for maintenance. Your coins, progress and running matches are safe — matches resume when we\'re back.';

  @override
  String gateMaintenanceEstimatedEnd(String time) {
    return 'Estimated end: $time';
  }

  @override
  String get gateMaintenanceEstimateNote =>
      'This is only an estimate and may change.';

  @override
  String get gateMaintenanceAutoCheck =>
      'We\'ll check again automatically every 30 seconds.';

  @override
  String gateLastChecked(String time) {
    return 'Last checked at $time';
  }

  @override
  String get gateCheckingNow => 'Checking…';

  @override
  String get gateServiceReachable => 'Game service reachable';

  @override
  String get gateServiceUnreachableShort => 'No connection to the game service';

  @override
  String get gateUnreachableTitle => 'Can\'t reach the game service';

  @override
  String get gateUnreachableMessage =>
      'Ludo Arena needs an internet connection for online play. Check your Wi-Fi or mobile data and try again.';

  @override
  String get gateUnreachableLastKnownMaintenance =>
      'The last status we received said the servers were under maintenance.';

  @override
  String get gateUnreachableLastKnownUpdate =>
      'The last status we received said this version needs an update.';

  @override
  String get gateNotFoundTitle => 'Not available yet';

  @override
  String get gateNotFoundMessage =>
      'This part of Ludo Arena isn\'t available in this version yet.';

  @override
  String get gateGoHome => 'Back to home';

  @override
  String get gateStudioIntroLabel => 'Sun Game Studio';

  @override
  String homeGreeting(String name) {
    return 'Hi, $name';
  }

  @override
  String get homeQuickPlay => 'Quick Play';

  @override
  String homeQuickPlayDetails(String game, String variant, String players) {
    return '$game · $variant · $players';
  }

  @override
  String get homePrivateRoom => 'Private Room';

  @override
  String get homePrivateRoomSubtitle => 'Create a room for friends';

  @override
  String get homeJoinWithCode => 'Join with Code';

  @override
  String get homeJoinWithCodeSubtitle => 'Enter a room code';

  @override
  String get homePlayOnline => 'Play Online';

  @override
  String get homePlayWithFriends => 'Play with Friends';

  @override
  String get homePracticeVsBots => 'Practice vs Bots';

  @override
  String get homeLudoTagline => 'Race all four tokens home';

  @override
  String get homeSnakesTagline => 'Climb ladders, dodge snakes';

  @override
  String get homeMissions => 'Missions';

  @override
  String get homeMissionsSubtitle => 'Daily & weekly goals';

  @override
  String get homeCollection => 'Collection';

  @override
  String get homeCollectionSubtitle => 'Dice, tokens & frames';

  @override
  String get homeFriends => 'Friends';

  @override
  String get homeFriendsSubtitle => 'Play with your crew';

  @override
  String get homeEvents => 'Events';

  @override
  String get homeEventsSubtitle => 'Limited-time cups';

  @override
  String get homeShop => 'Shop';

  @override
  String get homeExploreHeader => 'More to Explore';

  @override
  String get homeGamesHeader => 'Choose a Game';

  @override
  String get homeSaveProgressTooltip => 'Save progress';

  @override
  String get homeProfileTooltip => 'Profile';

  @override
  String get homeSettingsTooltip => 'Settings';

  @override
  String get homeThemeTooltip => 'Switch light/dark theme';

  @override
  String get homeWalletTooltip => 'Wallet';

  @override
  String homeOptionsOnlineTitle(String game) {
    return '$game online';
  }

  @override
  String homeOptionsFriendsTitle(String game) {
    return '$game with friends';
  }

  @override
  String homeOptionsPracticeTitle(String game) {
    return 'Practice $game';
  }

  @override
  String get homeOptionsPrivateRoomTitle => 'Create a private room';

  @override
  String get homeGameLabel => 'Game';

  @override
  String get homePlayersLabel => 'Players';

  @override
  String get homeModeLabel => 'Mode';

  @override
  String get homeBotsLabel => 'Bots';

  @override
  String get homeModeClassicCaption => 'Full rules';

  @override
  String get homeModeQuickCaption => 'Shorter games';

  @override
  String homeBotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bots',
      one: '1 bot',
    );
    return '$_temp0';
  }

  @override
  String get homeFindMatch => 'Find match';

  @override
  String get homeCreateRoom => 'Create room';

  @override
  String get homeStartPractice => 'Start practice';

  @override
  String get homeHaveACode => 'Have a code? Join a room';

  @override
  String homeEntryFeeNote(String fee) {
    return 'Entry fee $fee coins · Winner takes the pot';
  }

  @override
  String get homePracticeNote =>
      'Practice is free: no coins, but you still earn XP and mission progress.';

  @override
  String homeNotEnoughCoins(String fee) {
    return 'You need at least $fee coins for this match.';
  }

  @override
  String get homeJoinCodeTitle => 'Join a private room';

  @override
  String get homeJoinCodeLabel => 'Room code';

  @override
  String get homeJoinCodeHelper => 'Ask the host for the 6-character code.';

  @override
  String get homeJoinCodeInvalid => 'Room codes have 6 letters or numbers.';

  @override
  String get homeJoinCodeAction => 'Join room';

  @override
  String homeLevelUpToast(int level) {
    return 'Level up! You reached level $level.';
  }

  @override
  String homeCoinsGainedToast(String amount) {
    return '+$amount coins';
  }

  @override
  String get homeQuickPlaySubtitle => 'Find random players and start now';

  @override
  String get homePlayNow => 'Play Now';

  @override
  String get homeQuickLudo => 'Quick Ludo';

  @override
  String get homeChangeGameHint => 'Change game';

  @override
  String get homeChangePlayersHint => 'Change number of players';

  @override
  String get homeGamesSubtitle =>
      'Pick a game, then play online, with friends or against bots.';

  @override
  String get homeNavHome => 'Home';

  @override
  String get homeNavGames => 'Games';

  @override
  String get homeNavMissions => 'Missions';

  @override
  String get homeNavFriends => 'Friends';

  @override
  String get homeNavProfile => 'Profile';

  @override
  String get homeNoAdsRibbon => 'No Ads';

  @override
  String get metaMissionsTitle => 'Missions';

  @override
  String get metaEventsTitle => 'Events';

  @override
  String get metaCollectionTitle => 'Collection Room';

  @override
  String get metaFriendsTitle => 'Friends';

  @override
  String get metaLeaderboardTitle => 'Weekly ranking';

  @override
  String get metaLevelRoadTitle => 'Level road';

  @override
  String get metaDailyTitle => 'Daily missions';

  @override
  String get metaWeeklyTitle => 'Weekly challenge';

  @override
  String get metaClaim => 'Claim';

  @override
  String get metaStatusInProgress => 'In progress';

  @override
  String get metaStatusReady => 'Ready to claim';

  @override
  String get metaStatusClaimed => 'Claimed';

  @override
  String get metaCollected => 'Reward collected — added to your account';

  @override
  String metaProgressCount(String progress, String target) {
    return '$progress / $target';
  }

  @override
  String metaMissionSemantics(String title, String progress, String state) {
    return '$title. Progress $progress. $state';
  }

  @override
  String metaRewardAmount(String amount) {
    return '+$amount';
  }

  @override
  String metaRewardXp(String amount) {
    return '+$amount XP';
  }

  @override
  String metaRewardCoinsLabel(String amount) {
    return '$amount coins';
  }

  @override
  String metaRewardDiamondsLabel(String amount) {
    return '$amount diamonds';
  }

  @override
  String metaRewardXpLabel(String amount) {
    return '$amount experience points';
  }

  @override
  String metaRewardItemLabel(String name, String kind) {
    return '$name ($kind)';
  }

  @override
  String get metaGameAny => 'Any game';

  @override
  String metaResetsDailyAt(String time) {
    return 'New missions at $time';
  }

  @override
  String metaResetsWeeklyAt(String day, String time) {
    return 'Resets $day at $time';
  }

  @override
  String metaEventEndsAt(String date) {
    return 'Ends $date';
  }

  @override
  String metaWhenWithCountdown(String when, String duration) {
    return '$when · in $duration';
  }

  @override
  String metaDurationDaysHours(int days, int hours) {
    return '$days d $hours h';
  }

  @override
  String metaDurationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String metaDurationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get metaNoPenaltyNote =>
      'Missed a day? No problem — your XP, level and collection are always kept.';

  @override
  String get metaMissionsEmptyTitle => 'No missions right now';

  @override
  String get metaMissionsEmptyMessage =>
      'New daily missions arrive every day. Pull down to refresh.';

  @override
  String metaRetryHint(String message) {
    return '$message Tap again to retry.';
  }

  @override
  String get metaNewItemsTitle => 'New in your collection!';

  @override
  String metaNewItemsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'These $count items are now yours to equip and enjoy.',
      one: 'This item is now yours to equip and enjoy.',
    );
    return '$_temp0';
  }

  @override
  String get metaNice => 'Nice!';

  @override
  String get metaViewCollection => 'View collection';

  @override
  String get metaEventDetails => 'Details';

  @override
  String get metaMissionLudoTimeTitle => 'Ludo Time';

  @override
  String get metaMissionClimbTitle => 'Climb the Ladder';

  @override
  String get metaMissionWarmUpTitle => 'Warm-Up';

  @override
  String get metaMissionFriendlyTableTitle => 'Friendly Table';

  @override
  String get metaMissionStayToEndTitle => 'Stay to the End';

  @override
  String get metaMissionTasteOfVictoryTitle => 'Taste of Victory';

  @override
  String get metaMissionQuickDrawTitle => 'Quick Draw';

  @override
  String get metaMissionWeeklyChallengeTitle => 'Weekly Challenge';

  @override
  String get metaMissionAutumnSprintTitle => 'Autumn Sprint';

  @override
  String get metaMissionFallbackTitle => 'Mission';

  @override
  String metaMissionLudoMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Complete $count Ludo matches.',
      one: 'Complete 1 Ludo match.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionSnakesMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Complete $count Snakes & Ladders matches.',
      one: 'Complete 1 Snakes & Ladders match.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionAnyMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Complete $count matches in any game.',
      one: 'Complete 1 match in any game.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionFriendPrivateDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Complete $count private matches with friends.',
      one: 'Complete a private match with a friend.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionNoLeavingDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Complete $count matches without leaving early.',
      one: 'Complete a match without leaving early.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionWinDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Win $count matches.',
      one: 'Win 1 match.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionQuickLudoDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Complete $count Quick Ludo matches.',
      one: 'Complete 1 Quick Ludo match.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionWeeklyDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Complete $count matches across Ludo and Snakes & Ladders.',
      one: 'Complete 1 match in Ludo or Snakes & Ladders.',
    );
    return '$_temp0';
  }

  @override
  String get metaEventAutumnCupTitle => 'Autumn Cup';

  @override
  String get metaEventAutumnCupDesc =>
      'Celebrate the season with Quick Ludo and win the Autumn Leaf dice.';

  @override
  String metaEventWindow(String start, String end) {
    return '$start – $end';
  }

  @override
  String get metaEventLiveBadge => 'Event running';

  @override
  String get metaEventMissionsTitle => 'Event missions';

  @override
  String get metaEventRulesTitle => 'How it works';

  @override
  String get metaEventRuleComplete =>
      'Complete the event missions while the event is running.';

  @override
  String get metaEventRuleEligible =>
      'A match counts when you play it to the end, make at least 3 moves and it lasts at least 30 seconds.';

  @override
  String get metaEventRuleClaim =>
      'Claim each reward here — it is added to your account right away.';

  @override
  String get metaEventRuleEnd =>
      'Rewards not claimed before the event ends are no longer available. Your XP, level and collection are never affected.';

  @override
  String get metaNoEventsTitle => 'No events right now';

  @override
  String get metaNoEventsMessage =>
      'New events will appear here. Your daily missions are always available.';

  @override
  String get metaGoToMissions => 'Go to missions';

  @override
  String metaXpToNextLevel(String xp, int level) {
    return '$xp XP to level $level';
  }

  @override
  String get metaMaxLevelReached =>
      'Max level reached — XP still counts for the weekly ranking';

  @override
  String get metaMaxBadge => 'MAX';

  @override
  String metaTotalXp(String xp) {
    return 'Total XP: $xp';
  }

  @override
  String get metaHowToEarnXp => 'How to earn XP';

  @override
  String metaXpForMatch(int xp) {
    return '+$xp XP for every completed match';
  }

  @override
  String metaXpForWin(int xp) {
    return '+$xp XP bonus for a win';
  }

  @override
  String metaXpForFriend(int xp) {
    return '+$xp XP when a friend plays with you';
  }

  @override
  String get metaXpForMissions => 'Mission rewards include XP too';

  @override
  String get metaXpFairPlayNote =>
      'Matches count when played to the end (at least 3 moves and 30 seconds). Bots never earn XP.';

  @override
  String get metaMilestonesTitle => 'Milestones';

  @override
  String get metaMilestoneUnlocked => 'Unlocked';

  @override
  String metaMilestoneNext(String xp) {
    return 'Next milestone · $xp XP to go';
  }

  @override
  String metaMilestoneLocked(String xp) {
    return '$xp XP to go';
  }

  @override
  String get metaNoMilestones => 'Milestones will appear here.';

  @override
  String get metaLevelUpTitle => 'Level up!';

  @override
  String metaLevelUpMessage(int level) {
    return 'You reached level $level.';
  }

  @override
  String get metaUnlockedHeader => 'Unlocked for you';

  @override
  String get metaLevelUpContinue => 'Awesome!';

  @override
  String get metaYourLook => 'Your look';

  @override
  String metaCollectedCount(String owned, String total) {
    return '$owned of $total collected';
  }

  @override
  String get metaTabDice => 'Dice';

  @override
  String get metaTabTokens => 'Tokens';

  @override
  String get metaTabLudoBoards => 'Ludo boards';

  @override
  String get metaTabSnakesBoards => 'Snakes boards';

  @override
  String get metaTabTrails => 'Trails';

  @override
  String get metaTabVictory => 'Victory';

  @override
  String get metaTabFrames => 'Frames';

  @override
  String get metaTabTitles => 'Titles';

  @override
  String get metaTabBadges => 'Badges';

  @override
  String get metaTabEmotes => 'Emotes';

  @override
  String get metaTabPictures => 'Pictures';

  @override
  String get metaFilterAll => 'All';

  @override
  String get metaFilterOwned => 'Owned';

  @override
  String get metaFilterLocked => 'To unlock';

  @override
  String get metaEquipped => 'Equipped';

  @override
  String get metaOwned => 'Owned';

  @override
  String get metaLocked => 'Locked';

  @override
  String get metaNewBadge => 'New';

  @override
  String metaItemSemantics(
    String name,
    String rarity,
    String state,
    String how,
  ) {
    return '$name, $rarity, $state. $how';
  }

  @override
  String get metaAcqStarter => 'Starter item';

  @override
  String metaAcqLevel(int level) {
    return 'Reach level $level';
  }

  @override
  String get metaAcqMission => 'Mission reward';

  @override
  String get metaAcqWeeklyChallenge => 'Weekly challenge reward';

  @override
  String get metaAcqFirstWin => 'Win your first match';

  @override
  String get metaAcqEvent => 'Event reward';

  @override
  String get metaAcqAutumnCup => 'Autumn Cup reward';

  @override
  String metaPriceCoins(String amount) {
    return '$amount coins';
  }

  @override
  String metaPriceDiamonds(String amount) {
    return '$amount diamonds';
  }

  @override
  String get metaEquip => 'Equip';

  @override
  String get metaEquipDefault => 'Use default';

  @override
  String get metaEquippedToast => 'Equipped!';

  @override
  String get metaDefaultEquippedToast => 'Back to the default look';

  @override
  String get metaEmoteHint =>
      'Use your emotes during matches from the emote button.';

  @override
  String get metaBadgeHint =>
      'Badges celebrate what you have achieved. They are yours to keep.';

  @override
  String metaBuyFor(String price) {
    return 'Buy for $price';
  }

  @override
  String get metaBuy => 'Buy';

  @override
  String metaPurchaseTitle(String item) {
    return 'Buy $item?';
  }

  @override
  String get metaPrice => 'Price';

  @override
  String get metaYourBalance => 'Your balance';

  @override
  String get metaBalanceAfter => 'After purchase';

  @override
  String metaNeedMore(String amount) {
    return 'Not enough yet — you need another $amount. Win matches and complete missions to earn more.';
  }

  @override
  String get metaCosmeticOnlyNote =>
      'Cosmetic only — it never changes dice, rules or matchmaking.';

  @override
  String metaPurchaseSuccess(String item) {
    return '$item is now in your collection!';
  }

  @override
  String get metaNotEnoughCoins => 'Not enough coins for this item.';

  @override
  String get metaNotEnoughDiamonds => 'Not enough diamonds for this item.';

  @override
  String get metaAlreadyOwned => 'You already own this item.';

  @override
  String get metaItemNotForSale =>
      'This item is unlocked by playing, not bought.';

  @override
  String metaUnlocksAtLevel(int level) {
    return 'Unlocks automatically when you reach level $level.';
  }

  @override
  String get metaEarnFromMissionsHint =>
      'Earn it by completing the matching mission or event — no purchase needed.';

  @override
  String get metaAllOwnedInKind =>
      'You have unlocked everything here. Nicely done!';

  @override
  String get metaNothingOwnedInKind =>
      'Nothing here yet — keep playing to unlock more.';

  @override
  String get metaKindEmptyMessage =>
      'Nothing to collect here yet. Take a look in the Shop!';

  @override
  String get metaGoToShop => 'Go to Shop';

  @override
  String get metaFindMoreInShop => 'Find more in the Shop';

  @override
  String get metaCollectionFairNote =>
      'Every item is cosmetic and has a fixed way to get it — no random boxes, no gameplay advantage.';

  @override
  String get metaDescDiceClassic =>
      'Timeless ivory dice with crisp black pips.';

  @override
  String get metaDescDiceNeon => 'Glowing dice that pulse with every roll.';

  @override
  String get metaDescDiceGolden => 'Polished gold dice fit for royalty.';

  @override
  String get metaDescDiceAutumn => 'Warm amber dice from the Autumn Cup.';

  @override
  String get metaDescTokenClassic => 'The pawn everyone knows.';

  @override
  String get metaDescTokenGem => 'Faceted gem tokens that catch the light.';

  @override
  String get metaDescTokenRoyal => 'Pawns wearing tiny crowns.';

  @override
  String get metaDescTokenCrown => 'A legendary crown-shaped piece.';

  @override
  String get metaDescLudoBoardClassic =>
      'The traditional four-colour Ludo board.';

  @override
  String get metaDescLudoBoardMidnight => 'Dark marble with silver inlays.';

  @override
  String get metaDescLudoBoardRoyal =>
      'A palace courtyard in gold and crimson.';

  @override
  String get metaDescSnakesBoardClassic =>
      'Green meadows, friendly snakes, sturdy ladders.';

  @override
  String get metaDescSnakesBoardJungle => 'Vines, ruins and temple stairs.';

  @override
  String get metaDescSnakesBoardCandy =>
      'Licorice snakes and candy-cane ladders.';

  @override
  String get metaDescTrailNone => 'Clean moves, no trail.';

  @override
  String get metaDescTrailSparkle => 'A shower of sparkles follows every move.';

  @override
  String get metaDescTrailComet => 'A blazing comet tail.';

  @override
  String get metaDescVictoryConfetti => 'A classic confetti celebration.';

  @override
  String get metaDescVictoryFireworks => 'Light up the sky when you win.';

  @override
  String get metaDescVictoryCrown => 'A golden crown descends on the winner.';

  @override
  String get metaDescFrameNone => 'Your avatar, unframed.';

  @override
  String get metaDescFrameBronze => 'A simple bronze ring around your avatar.';

  @override
  String get metaDescFrameSilver => 'A silver laurel wreath.';

  @override
  String get metaDescFrameGold => 'A gold laurel wreath for seasoned players.';

  @override
  String get metaDescFrameRoyal => 'An ornate royal crest.';

  @override
  String get metaDescTitleRookie => 'Everyone starts somewhere.';

  @override
  String get metaDescTitleStrategist =>
      'For players who think three moves ahead.';

  @override
  String get metaDescTitleDiceMaster => 'The dice seem to listen to you.';

  @override
  String get metaDescTitleRoyal => 'Reserved for true royalty.';

  @override
  String get metaDescTitleWeeklyChampion => 'Completed a weekly challenge.';

  @override
  String get metaDescBadgeFirstWin => 'Won your first match.';

  @override
  String get metaDescBadgeFriendly => 'Completed a weekly challenge.';

  @override
  String get metaDescEmoteWave => 'Say hello.';

  @override
  String get metaDescEmoteThumbs => 'Nice one!';

  @override
  String get metaDescEmoteLaugh => 'Share a laugh.';

  @override
  String get metaDescEmoteWow => 'Did that just happen?';

  @override
  String get metaDescEmoteCrown => 'Show who rules the board.';

  @override
  String get metaYourFriendCode => 'Your friend code';

  @override
  String get metaFriendCodeHint => 'Share it so friends can add you.';

  @override
  String metaFriendCodeSemantics(String code) {
    return 'Friend code: $code';
  }

  @override
  String metaShareFriendCodeMessage(String code) {
    return 'Let\'s play Ludo Arena together! Add me as a friend with my code: $code';
  }

  @override
  String get metaAddFriend => 'Add friend';

  @override
  String get metaAdd => 'Add';

  @override
  String get metaAddFriendTitle => 'Add a friend';

  @override
  String get metaAddFriendHelp =>
      'Enter your friend\'s code. They can find it on their Friends screen.';

  @override
  String get metaFriendCodeLabel => 'Friend code';

  @override
  String get metaFriendCodeHintExample => 'u_abcd 2345 wxyz';

  @override
  String get metaPaste => 'Paste';

  @override
  String get metaSendRequest => 'Send request';

  @override
  String get metaFriendCodeRequired => 'Enter a friend code.';

  @override
  String get metaInvalidFriendCode =>
      'That doesn\'t look like a friend code. It starts with u_ followed by letters and numbers.';

  @override
  String metaRequestSent(String name) {
    return 'Friend request sent to $name';
  }

  @override
  String metaNowFriends(String name) {
    return 'You and $name are now friends!';
  }

  @override
  String get metaAlreadyFriends => 'You\'re already friends.';

  @override
  String get metaTabFriends => 'Friends';

  @override
  String get metaTabRequests => 'Requests';

  @override
  String get metaTabRecent => 'Recent';

  @override
  String get metaOnline => 'Online';

  @override
  String get metaOffline => 'Offline';

  @override
  String get metaMoreActions => 'More actions';

  @override
  String get metaRemoveFriend => 'Remove friend';

  @override
  String metaRemoveFriendTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get metaRemoveFriendMessage =>
      'You can add each other again any time with a friend code.';

  @override
  String get metaRemove => 'Remove';

  @override
  String metaFriendRemoved(String name) {
    return '$name was removed from your friends';
  }

  @override
  String get metaIncomingRequests => 'Received';

  @override
  String get metaOutgoingRequests => 'Sent';

  @override
  String get metaWantsToBeFriends => 'Wants to be your friend';

  @override
  String get metaRequestPending => 'Waiting for an answer';

  @override
  String get metaAccept => 'Accept';

  @override
  String get metaDecline => 'Decline';

  @override
  String get metaRequestDeclined => 'Request declined';

  @override
  String get metaRequestCancelled => 'Request cancelled';

  @override
  String get metaRequested => 'Requested';

  @override
  String get metaFriendsLabel => 'Friends';

  @override
  String get metaNoFriendsTitle => 'No friends yet';

  @override
  String get metaNoFriendsMessage =>
      'Share your code or add a friend to play together.';

  @override
  String get metaNoRequestsTitle => 'No pending requests';

  @override
  String get metaNoRequestsMessage =>
      'Friend requests you send or receive appear here.';

  @override
  String get metaRecentHint =>
      'Players you met in online matches during the last 14 days.';

  @override
  String get metaNoRecentTitle => 'No recent opponents';

  @override
  String get metaNoRecentMessage =>
      'Play an online match — the players you meet will show up here.';

  @override
  String metaFriendRequestBanner(String name) {
    return '$name wants to be your friend';
  }

  @override
  String get metaView => 'View';

  @override
  String get metaErrorCannotFriendSelf => 'That\'s your own friend code.';

  @override
  String metaErrorFriendLimit(int max) {
    return 'You can have up to $max friends. Remove a friend to add someone new.';
  }

  @override
  String get metaErrorUnknownFriendCode =>
      'No player has this friend code. Check it and try again.';

  @override
  String get metaErrorRequestInProgress =>
      'Still working on it — please try again in a moment.';

  @override
  String get metaErrorMissionEnded =>
      'This mission has ended. Pull down to see the current missions.';

  @override
  String get metaLeaderboardSubtitle =>
      'You and your friends, ranked by XP earned this week.';

  @override
  String get metaLeaderboardTeaser =>
      'See how you and your friends are doing this week.';

  @override
  String metaWeeklyXp(String xp) {
    return '$xp XP';
  }

  @override
  String metaYouName(String name) {
    return '$name (you)';
  }

  @override
  String metaLeaderboardRowSemantics(int rank, String name, String xp) {
    return 'Rank $rank: $name, $xp';
  }

  @override
  String get metaLeaderboardAlone =>
      'Add friends to see how you compare. Friendly competition, no pressure.';

  @override
  String numberLakh(String value) {
    return '$value Lakh';
  }

  @override
  String numberCrore(String value) {
    return '$value Crore';
  }

  @override
  String numberThousand(String value) {
    return '${value}K';
  }

  @override
  String numberMillion(String value) {
    return '${value}M';
  }

  @override
  String numberBillion(String value) {
    return '${value}B';
  }

  @override
  String get onboardingLanguageTitle => 'Choose your language';

  @override
  String get onboardingLanguageSubtitle =>
      'You can change it any time in Settings.';

  @override
  String get onboardingPreviewLabel => 'Preview';

  @override
  String get onboardingPreviewTitle => 'Welcome to Ludo Arena!';

  @override
  String get onboardingPreviewBody =>
      'Roll the dice, race your tokens home and claim the crown.';

  @override
  String playGameVariantTitle(String game, String variant) {
    return '$game · $variant';
  }

  @override
  String get playModeOnline => 'Online';

  @override
  String get playModePrivate => 'Private room';

  @override
  String get playModePractice => 'Practice';

  @override
  String playSeatPlayer(int seat) {
    return 'Player $seat';
  }

  @override
  String playNameYou(String name) {
    return '$name (you)';
  }

  @override
  String get playHome => 'Home';

  @override
  String get playBackHome => 'Back to home';

  @override
  String get playTryAgain => 'Try again';

  @override
  String playEntryFee(String fee) {
    return 'Entry $fee';
  }

  @override
  String playEntryFeeNote(String fee) {
    return 'Entry fee: $fee coins per player, charged when the game starts. The winner takes the pot.';
  }

  @override
  String get playNotEnoughCoinsTitle => 'Not enough coins';

  @override
  String playNotEnoughCoinsHint(String fee) {
    return 'You need $fee coins to play. Earn coins from missions and come back!';
  }

  @override
  String get playSeatOpen => 'Open seat';

  @override
  String get playLoadingMatch => 'Joining the match…';

  @override
  String get playMatchUnavailable => 'This match is no longer available.';

  @override
  String get playRoomClosed => 'The room was closed.';

  @override
  String get playRemovedFromRoom => 'You\'re no longer in this room.';

  @override
  String get playRoomUnavailable => 'This room is no longer available.';

  @override
  String get playLoadingRoom => 'Opening the room…';

  @override
  String get playGameLabel => 'Game';

  @override
  String get playModeLabel => 'Rules';

  @override
  String get playPlayersLabel => 'Players';

  @override
  String get playVariantClassicCaption => '4 tokens · leave base on a 6';

  @override
  String get playVariantQuickCaption => '2 tokens · leave base on a 1 or 6';

  @override
  String get playMatchmakingTitle => 'Finding players';

  @override
  String get playMatchmakingConnecting => 'Connecting to the game server…';

  @override
  String get playMatchmakingJoining => 'Joining the queue…';

  @override
  String get playMatchmakingSearching => 'Looking for opponents…';

  @override
  String get playMatchmakingStarting => 'Table full! Starting…';

  @override
  String get playMatchmakingStartsSoon =>
      'The match starts when all seats are filled or when the timer runs out.';

  @override
  String get playMatchmakingStartsWhenFull =>
      'The match starts as soon as all seats are filled.';

  @override
  String playMatchmakingPlayers(int count, int capacity) {
    return '$count of $capacity players joined';
  }

  @override
  String get playMatchmakingCancel => 'Cancel search';

  @override
  String get playMatchmakingFeeNote =>
      'The entry fee is charged when the match starts. The winner takes the pot.';

  @override
  String get playMatchmakingTimeoutTitle => 'No opponents right now';

  @override
  String get playMatchmakingTimeoutMessage =>
      'Nobody joined in time. Try again, or invite friends to a private room.';

  @override
  String get playMatchmakingErrorTitle => 'Couldn\'t find a match';

  @override
  String get playCreateRoomTitle => 'Create private room';

  @override
  String get playCreateRoomAction => 'Create room';

  @override
  String get playCreatingRoom => 'Creating your room…';

  @override
  String get playLobbyTitle => 'Private room';

  @override
  String get playRoomCodeLabel => 'Room code';

  @override
  String playRoomCodeA11y(String letters) {
    return 'Room code $letters';
  }

  @override
  String get playCopyCode => 'Copy code';

  @override
  String get playCodeCopied => 'Room code copied';

  @override
  String get playShareInvite => 'Share invite';

  @override
  String playInviteShareText(String game, String code) {
    return 'Join me for $game on Ludo Arena! Open the app, tap Join with Code and enter: $code';
  }

  @override
  String get playInviteShareSubject => 'Ludo Arena invite';

  @override
  String playLobbyPlayers(int count, int capacity) {
    return 'Players $count/$capacity';
  }

  @override
  String get playLobbyStart => 'Start game';

  @override
  String get playLobbyWaitingForHost => 'Waiting for the host to start…';

  @override
  String playLobbyWaitingForNamedHost(String name) {
    return 'Waiting for $name (host) to start…';
  }

  @override
  String get playStartBlockedNeedPlayers =>
      'At least 2 players are needed to start.';

  @override
  String get playStartBlockedConnections =>
      'Waiting for everyone to reconnect.';

  @override
  String get playStartBlockedBots => 'Bots are taking their seats…';

  @override
  String get playAllowBots => 'Allow bots';

  @override
  String get playAllowBotsHint =>
      'Fill empty seats with computer players. Everyone pays the entry fee, computer players too.';

  @override
  String get playAddBot => 'Add bot';

  @override
  String get playBotJoining => 'Bot joining…';

  @override
  String playRemoveBotA11y(String name) {
    return 'Remove $name';
  }

  @override
  String get playInviteFriends => 'Invite friends';

  @override
  String get playInviteSheetTitle => 'Invite friends';

  @override
  String get playInviteSend => 'Invite';

  @override
  String get playInviteSent => 'Invited';

  @override
  String get playFriendOnline => 'Online';

  @override
  String get playFriendOffline => 'Offline';

  @override
  String get playInviteEmptyTitle => 'No friends yet';

  @override
  String get playInviteEmptyMessage =>
      'Share the room code instead, or add friends from the Friends screen.';

  @override
  String get playInviteError => 'Couldn\'t load your friends.';

  @override
  String get playLeaveRoom => 'Leave room';

  @override
  String get playLeaveRoomTitle => 'Leave this room?';

  @override
  String get playLeaveRoomHostMessage =>
      'You\'re the host. The next player becomes host when you leave.';

  @override
  String get playLeaveRoomMessage =>
      'You can come back with the room code while the room is open.';

  @override
  String get playStay => 'Stay';

  @override
  String get playHostBadge => 'Host';

  @override
  String get playJoinTitle => 'Join with code';

  @override
  String get playJoinHint =>
      'Enter the 6-character room code your friend shared.';

  @override
  String playJoinCodeIncomplete(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining more characters',
      one: '1 more character',
    );
    return '$_temp0';
  }

  @override
  String get playJoinInvalidChars =>
      'Room codes use the letters A–Z and the numbers 2–9 (no I, O, 0 or 1).';

  @override
  String get playJoinLookingUp => 'Looking up the room…';

  @override
  String get playJoinAction => 'Join room';

  @override
  String get playJoining => 'Joining…';

  @override
  String playJoinPreviewHost(String name) {
    return 'Hosted by $name';
  }

  @override
  String playJoinPreviewPlayers(int count, int capacity) {
    return '$count/$capacity players';
  }

  @override
  String get playJoinStatusOpen => 'Open';

  @override
  String get playJoinStatusFull => 'Full';

  @override
  String get playJoinStatusInProgress => 'In progress';

  @override
  String get playJoinStatusClosed => 'Closed';

  @override
  String get playPaste => 'Paste';

  @override
  String get playPracticeTitle => 'Practice vs bots';

  @override
  String get playPracticeBotsLabel => 'Bots';

  @override
  String playPracticeBotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bots',
      one: '1 bot',
    );
    return '$_temp0';
  }

  @override
  String get playPracticeStart => 'Start practice';

  @override
  String get playPracticeNote =>
      'Practice is free and pays no coins. You play against computer players.';

  @override
  String get playPracticeSettingUp => 'Setting up your practice table…';

  @override
  String playPracticeBotsJoining(int seated, int total) {
    return 'Bots joining… $seated/$total';
  }

  @override
  String get playPracticeBotsUnavailableTitle => 'Bots are busy';

  @override
  String get playPracticeErrorTitle => 'Couldn\'t start practice';

  @override
  String get playLeave => 'Leave match';

  @override
  String get playTurnYourRoll => 'Your turn — tap the dice!';

  @override
  String get playTurnPickToken => 'Pick a glowing token to move';

  @override
  String get playTurnYours => 'Your turn';

  @override
  String playTurnOther(String name) {
    return '$name\'s turn';
  }

  @override
  String get playVoidedThreeSixes => 'Three sixes in a row! The turn passes.';

  @override
  String playAutoPlayed(String name) {
    return 'Time\'s up — played automatically for $name';
  }

  @override
  String playForfeitLeft(String name) {
    return '$name left the match';
  }

  @override
  String playForfeitTimeouts(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name was removed after $count missed turns in a row',
      one: '$name was removed after missing a turn',
    );
    return '$_temp0';
  }

  @override
  String playRemovedForInactivity(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'You were removed from the match because you missed $count turns in a row.',
      one: 'You were removed from the match because you missed your turn.',
    );
    return '$_temp0';
  }

  @override
  String get playPlayerDisconnected => 'Offline';

  @override
  String get playPlayerForfeited => 'Left';

  @override
  String get playPlayerOnline => 'Online';

  @override
  String get playPlayerMuted => 'Muted';

  @override
  String get playPanelTurnA11y => 'current turn';

  @override
  String playStrikesA11y(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count missed turns',
      one: '1 missed turn',
    );
    return '$_temp0';
  }

  @override
  String playTokensHome(int home, int total) {
    return '$home of $total tokens home';
  }

  @override
  String playSquare(int square) {
    return 'Square $square';
  }

  @override
  String get playAtStart => 'At the start';

  @override
  String get playReconnecting => 'Reconnecting… your match continues';

  @override
  String get playSyncing => 'Syncing the board…';

  @override
  String get playLeaveMatchTitle => 'Leave the match?';

  @override
  String get playLeaveMatchMessage =>
      'Leaving counts as a forfeit and your entry fee isn\'t returned.';

  @override
  String get playLeavePracticeMessage => 'Your practice game will end.';

  @override
  String get playLeaveMatchConfirm => 'Leave';

  @override
  String get playKeepPlaying => 'Keep playing';

  @override
  String playRoundLabel(int round) {
    return 'Round $round';
  }

  @override
  String get playStartingNextRound => 'Starting the next round…';

  @override
  String get playChatOpen => 'Quick chat';

  @override
  String get playChatTitle => 'Quick chat';

  @override
  String get playChatEmotes => 'Emotes';

  @override
  String get playChatMuteOthers => 'Mute other players';

  @override
  String get playChatMutedBySettings => 'Quick chat is muted in Settings.';

  @override
  String playChatCooldown(int seconds) {
    return 'Next message in ${seconds}s';
  }

  @override
  String get playChatGg => 'Good game!';

  @override
  String get playChatNiceMove => 'Nice move!';

  @override
  String get playChatWellPlayed => 'Well played!';

  @override
  String get playChatRematch => 'Rematch?';

  @override
  String get playChatAgain => 'Let\'s play again.';

  @override
  String get playChatGoodLuck => 'Good luck!';

  @override
  String get playChatOops => 'Oops!';

  @override
  String get playChatThanks => 'Thanks!';

  @override
  String get playResultYouWon => 'You won!';

  @override
  String playResultWinnerIs(String name) {
    return '$name wins!';
  }

  @override
  String get playResultGameOver => 'Game over';

  @override
  String get playResultYouForfeited => 'You left the match';

  @override
  String get playResultByForfeit => 'The others forfeited — the win is yours.';

  @override
  String get playResultWellPlayed => 'Well played!';

  @override
  String playResultYouFinished(int place) {
    return 'You finished #$place';
  }

  @override
  String get playResultFinishingOrder => 'Finishing order';

  @override
  String playResultPlaceShort(int place) {
    return '$place';
  }

  @override
  String playResultPlaceA11y(int place) {
    return 'Place $place';
  }

  @override
  String get playRewardsTitle => 'Rewards';

  @override
  String playRewardCoins(String amount) {
    return '+$amount coins';
  }

  @override
  String playRewardCoinsBalance(String amount) {
    return 'Wallet: $amount coins';
  }

  @override
  String get playRewardNoCoinsMatch => 'This match doesn\'t pay coins.';

  @override
  String get playRewardNoCoins =>
      'No coins this time — the winner takes the pot.';

  @override
  String playRewardXp(int xp) {
    return '+$xp XP';
  }

  @override
  String get playRewardXpPending => 'Calculating XP…';

  @override
  String get playRewardXpLater => 'Your XP will show on your profile shortly.';

  @override
  String playRewardLevelUp(int level) {
    return 'Level up! You reached level $level';
  }

  @override
  String get playRewardUnlocked => 'Unlocked';

  @override
  String get playRematchTitle => 'Rematch';

  @override
  String get playRematchRequest => 'Ask for a rematch';

  @override
  String get playRematchAccept => 'Accept';

  @override
  String get playRematchDecline => 'Decline';

  @override
  String playRematchIncoming(String name) {
    return '$name wants a rematch!';
  }

  @override
  String get playRematchWaiting => 'You\'re in! Waiting for the others…';

  @override
  String get playRematchYouDeclined => 'You declined the rematch.';

  @override
  String get playRematchClosed => 'Rematch is no longer available.';

  @override
  String get playRematchPublicNote =>
      'Players who accept move to a new private room together.';

  @override
  String get playRematchStatusAccepted => 'Ready';

  @override
  String get playRematchStatusDeclined => 'Declined';

  @override
  String get playRematchStatusPending => 'Deciding…';

  @override
  String get playRematchStatusOut => 'Left';

  @override
  String playRematchSeatA11y(String name, String status) {
    return '$name: $status';
  }

  @override
  String get playPlayAgain => 'Play again';

  @override
  String playInviteIncoming(String name, String game) {
    return '$name invited you to play $game';
  }

  @override
  String get playInviteJoin => 'Join';

  @override
  String get playInviteDismiss => 'Not now';

  @override
  String get playInviteSomeone => 'A friend';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileFriendCode => 'Friend code';

  @override
  String get profileFriendCodeHint => 'Share it so friends can add you.';

  @override
  String profileShareFriendCode(String code) {
    return 'Add me on Ludo Arena! My friend code is $code';
  }

  @override
  String profileLevelProgress(String xp, int level) {
    return '$xp XP to level $level';
  }

  @override
  String get profileMaxLevel => 'Max level reached';

  @override
  String get profileTitleLabel => 'Title';

  @override
  String get profileAccountSection => 'Account';

  @override
  String get profileAccountType => 'Account type';

  @override
  String get profileAccountGuest => 'Guest (not saved)';

  @override
  String get profileAccountLinked => 'Saved account';

  @override
  String get profileLinkedAccounts => 'Sign-in methods';

  @override
  String get profileLinked => 'Linked';

  @override
  String get profileNotLinked => 'Not linked';

  @override
  String get profileSaveProgressCta => 'Save progress';

  @override
  String get profileTotalXp => 'Total XP';

  @override
  String get profileStatsSection => 'Progress';

  @override
  String get profileEditNameTooltip => 'Edit name';

  @override
  String get profileChangePicture => 'Change picture';

  @override
  String get profilePictureTitle => 'Choose your picture';

  @override
  String get profilePictureClassic => 'Classic avatar';

  @override
  String get profilePictureEmptyMessage =>
      'Pictures you buy in the Shop show up here.';

  @override
  String get profilePictureOpenShop => 'Visit the Shop';

  @override
  String get profilePictureGetMore => 'Get more in the Shop';

  @override
  String get profilePictureShowMore => 'Show more';

  @override
  String get profileEditNameTitle => 'Change your name';

  @override
  String get profileNameLabel => 'Display name';

  @override
  String get profileNameRules =>
      '3–16 characters. Letters, numbers, spaces, _ . and - are allowed.';

  @override
  String get profileNameNote =>
      'Friends, leaderboards and new games will show your new name. A game in progress keeps the old one.';

  @override
  String profileNameCounterSemantics(int count, int max) {
    return '$count of $max characters';
  }

  @override
  String profileNameSaved(String name) {
    return 'Your name is now $name';
  }

  @override
  String get profileNameChangeLimit =>
      'You\'ve changed your name too often. Please try again later.';

  @override
  String profileNameChangeLimitRetry(String wait) {
    return 'You\'ve changed your name too often. Try again in $wait.';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsNumberSystem => 'Number format';

  @override
  String get settingsNumberSystemHint => 'Choose how coin amounts are shown.';

  @override
  String get settingsNumberSystemIndian => 'Indian';

  @override
  String get settingsNumberSystemInternational => 'International';

  @override
  String settingsNumberSystemExample(String full, String compact) {
    return '$full · $compact';
  }

  @override
  String settingsNumberSystemSummary(String system, String example) {
    return '$system ($example)';
  }

  @override
  String get settingsSoundAndHaptics => 'Sound & haptics';

  @override
  String get settingsSound => 'Sound';

  @override
  String get settingsSoundSubtitle => 'Music and sound effects';

  @override
  String get settingsSfxVolume => 'Sound effects volume';

  @override
  String get settingsMusicVolume => 'Music volume';

  @override
  String get settingsHaptics => 'Vibration';

  @override
  String get settingsReducedMotion => 'Reduce motion';

  @override
  String get settingsReducedMotionSubtitle => 'Fewer animations and effects';

  @override
  String get settingsReducedMotionSystemOn => 'Also on in your device settings';

  @override
  String get settingsGameplay => 'Gameplay';

  @override
  String get settingsQuickChatMute => 'Mute quick chat';

  @override
  String get settingsQuickChatMuteSubtitle =>
      'Hide other players\' chat messages and emotes';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsAnalytics => 'Share anonymous usage stats';

  @override
  String get settingsAnalyticsSubtitle =>
      'Helps us improve the game. Never includes your name, chats or room codes.';

  @override
  String get settingsAnalyticsNotConfigured => 'Not available in this build';

  @override
  String get settingsAccount => 'Account';

  @override
  String settingsSignedInAs(String name) {
    return 'Signed in as $name';
  }

  @override
  String get settingsSaveProgress => 'Save progress';

  @override
  String get settingsSaveProgressSubtitle =>
      'Link a sign-in method to keep your progress safe';

  @override
  String get settingsSwitchToGuest => 'Switch back to guest';

  @override
  String get settingsSwitchToGuestSubtitle =>
      'Return to the guest account saved on this device';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsDeleteAccountSubtitle =>
      'Permanently delete your account and its data';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsLegalNotices => 'Legal notices';

  @override
  String get settingsLegalNoticesSubtitle =>
      'Open-source licenses · opens in your browser';

  @override
  String get settingsLegalNoticesOpenFailed =>
      'Couldn\'t open the page. Please try again later.';

  @override
  String get settingsConsentTitle => 'Help us make Ludo Arena better';

  @override
  String get settingsConsentMessage =>
      'Can we collect anonymous usage stats, like which game modes are popular? We never collect your name, chats, room codes or contact details. You can change this any time in Settings.';

  @override
  String get settingsConsentAllow => 'Share anonymous stats';

  @override
  String get settingsConsentDeny => 'No thanks';

  @override
  String get socialPodOptionsHint => 'Show player options';

  @override
  String get socialRequestSent => 'Request sent';

  @override
  String get socialAcceptRequest => 'Accept request';

  @override
  String get socialReportPlayer => 'Report player';

  @override
  String get socialReported => 'Reported';

  @override
  String get socialMutePlayer => 'Mute player';

  @override
  String get socialUnmutePlayer => 'Unmute player';

  @override
  String get socialMutedNote => 'You won\'t see this player\'s chat or emotes.';

  @override
  String get socialAlreadyReported =>
      'You reported this player in the last 24 hours.';

  @override
  String socialReportsLeft(int remaining, int total) {
    return 'Reports left today: $remaining of $total';
  }

  @override
  String socialReportLimitAt(int total, String time) {
    return 'You\'ve used today\'s $total reports. You can report again at $time.';
  }

  @override
  String socialReportLimitLater(int total) {
    return 'You\'ve used today\'s $total reports. Try again later.';
  }

  @override
  String socialReportTitle(String name) {
    return 'Report $name';
  }

  @override
  String get socialReportWhy => 'What happened?';

  @override
  String get socialReasonCheating => 'Cheating';

  @override
  String get socialReasonOffensiveName => 'Offensive name';

  @override
  String get socialReasonAbusiveBehavior => 'Harassment or abusive chat';

  @override
  String get socialReasonLeavingOrStalling => 'Leaving or stalling';

  @override
  String get socialReasonOther => 'Something else';

  @override
  String get socialReportReviewNote =>
      'Our team reviews every report. Follow its status in the Reported tab on the Friends screen.';

  @override
  String get socialSendReport => 'Send report';

  @override
  String socialReportSent(int remaining, int total) {
    return 'Report sent. $remaining of $total reports left today.';
  }

  @override
  String socialFriendLimitNote(int max) {
    return 'You can have up to $max friends — remove one to add more.';
  }

  @override
  String get socialErrorCannotReportSelf => 'You can\'t report yourself.';

  @override
  String get socialErrorCannotReportBot => 'This player can\'t be reported.';

  @override
  String get socialErrorNotInRoom =>
      'You can only report players from a match you\'re in.';

  @override
  String get socialErrorRoomNotFound =>
      'This match can\'t be found anymore, so the report wasn\'t sent.';

  @override
  String get socialErrorPlayerNotFound => 'This player couldn\'t be found.';

  @override
  String get socialTabReported => 'Reported';

  @override
  String socialOnlineNow(int count) {
    return 'Online now ($count)';
  }

  @override
  String socialOfflineCount(int count) {
    return 'Offline ($count)';
  }

  @override
  String socialFriendsCount(int count, int max) {
    return 'Friends $count/$max';
  }

  @override
  String socialReportsResetAt(String time) {
    return 'You can report again at $time.';
  }

  @override
  String socialReportsInfo(int total) {
    return 'You can report up to $total players a day. Our team reviews every report.';
  }

  @override
  String get socialNoReportsTitle => 'No reports';

  @override
  String get socialNoReportsMessage =>
      'Players you report from a match show up here with the status of each report.';

  @override
  String get socialStatusSubmitted => 'Submitted';

  @override
  String get socialStatusReviewing => 'Under review';

  @override
  String get socialStatusActionTaken => 'Action taken';

  @override
  String get socialStatusDismissed => 'Dismissed';

  @override
  String get socialJustNow => 'Just now';

  @override
  String socialMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String socialHoursAgo(int hours) {
    return '$hours h ago';
  }

  @override
  String get socialYesterday => 'Yesterday';

  @override
  String socialReportStatusA11y(String status) {
    return 'Status: $status';
  }

  @override
  String get storeTitle => 'Shop';

  @override
  String get storeHeroTitle => 'Profile pictures';

  @override
  String get storeHeroSubtitle => 'Buy once with diamonds and keep it forever.';

  @override
  String get storeCosmeticsHeroSubtitle =>
      'Fixed prices, nothing random. Cosmetic only, and yours forever.';

  @override
  String get storeFilterAnimated => 'Animated';

  @override
  String get storeFilterStatic => 'Static';

  @override
  String get storeKindAnimated => 'Animated picture';

  @override
  String get storeKindStatic => 'Picture';

  @override
  String get storeApply => 'Apply';

  @override
  String get storeApplyNow => 'Apply now';

  @override
  String get storeRemove => 'Use classic avatar';

  @override
  String get storeAppliedToast => 'Picture applied!';

  @override
  String get storeRemovedToast => 'Back to your classic avatar.';

  @override
  String storePurchasedToast(String name) {
    return '$name is yours forever!';
  }

  @override
  String get storeNextMatchNote =>
      'Shows on your profile now, and to other players from your next match.';

  @override
  String get storeEmptyOwnedTitle => 'No pictures yet';

  @override
  String get storeEmptyTitle => 'Nothing here yet';

  @override
  String get storeEmptyMessage => 'New pictures are on their way.';

  @override
  String get storeAllOwnedTitle => 'You own them all!';

  @override
  String get storeAllOwnedMessage =>
      'Everything here is already in your Collection.';

  @override
  String get storeViewInCollection => 'View in Collection';

  @override
  String get storeLoadMoreFailed => 'Couldn\'t load more pictures.';

  @override
  String storeTileSemantics(String name, String status) {
    return '$name, $status';
  }

  @override
  String get storeEmotesHeroTitle => 'Animated emotes';

  @override
  String get storeEmotesHeroSubtitle =>
      'Send them in any match. Buy once with diamonds, keep them forever.';

  @override
  String get storeEmoteKind => 'Animated emote';

  @override
  String get storeEmoteUseInMatchNote =>
      'Send it from the chat button during a match.';

  @override
  String get storeEmotesLoadMoreFailed => 'Couldn\'t load more emotes.';

  @override
  String get storeEmotesOwnedEmpty =>
      'Animated emotes you buy in the Shop show up here.';

  @override
  String get walletTitle => 'Your wallet';

  @override
  String get walletCoinsCaption =>
      'For match entry fees — winners take the pot.';

  @override
  String get walletDiamondsCaption =>
      'For premium cosmetics in the Collection Room.';

  @override
  String walletExactBalance(String amount) {
    return 'Exact balance: $amount';
  }

  @override
  String get walletVirtualTitle => 'Virtual currency';

  @override
  String get walletVirtualNotice =>
      'Coins and diamonds are virtual items for fun only. They have no real-world value and can\'t be sold, transferred, withdrawn or exchanged for money.';

  @override
  String get walletEarnTitle => 'How to earn more';

  @override
  String get walletEarnWins => 'Win matches to take the pot';

  @override
  String get walletEarnMissions => 'Complete daily and weekly missions';

  @override
  String get walletEarnLevels => 'Level up for milestone rewards';

  @override
  String get walletRefresh => 'Refresh balance';

  @override
  String widgetsCoinsBalance(String amount) {
    return 'Coins: $amount';
  }

  @override
  String widgetsDiamondsBalance(String amount) {
    return 'Diamonds: $amount';
  }

  @override
  String widgetsXpLabel(String current, String total) {
    return 'Experience: $current of $total';
  }

  @override
  String get widgetsAvatarLabel => 'Player avatar';

  @override
  String widgetsTitleLabel(String title) {
    return 'Title: $title';
  }

  @override
  String widgetsEmoteLabel(String name) {
    return 'Emote: $name';
  }

  @override
  String widgetsBadgeLabel(String name) {
    return 'Badge: $name';
  }

  @override
  String widgetsSecondsLeft(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds left',
      one: '1 second left',
    );
    return '$_temp0';
  }

  @override
  String widgetsConnectionLabel(String status) {
    return 'Connection: $status';
  }

  @override
  String widgetsNewItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new',
      one: '1 new',
    );
    return '$_temp0';
  }

  @override
  String get widgetsSelected => 'Selected';

  @override
  String widgetsLogoLabel(String appName) {
    return '$appName crest';
  }
}
