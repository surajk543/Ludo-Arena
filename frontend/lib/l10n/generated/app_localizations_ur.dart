// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Urdu (`ur`).
class AppLocalizationsUr extends AppLocalizations {
  AppLocalizationsUr([String locale = 'ur']) : super(locale);

  @override
  String get authWelcomeTitle => 'بورڈ پر راج کرنے کے لیے تیار؟';

  @override
  String get authWelcomeSubtitle =>
      'دوستوں اور دنیا بھر کے کھلاڑیوں کے ساتھ لوڈو اور سانپ سیڑھی کھیلیں۔';

  @override
  String get authContinueWithGoogle => 'Google کے ساتھ جاری رکھیں';

  @override
  String get authContinueWithFacebook => 'Facebook کے ساتھ جاری رکھیں';

  @override
  String get authContinueWithApple => 'Apple کے ساتھ سائن اِن کریں';

  @override
  String get authPlayAsGuest => 'مہمان کے طور پر کھیلیں';

  @override
  String get authGuestHint =>
      'فوراً شروع کریں — آپ کسی بھی وقت اپنی پیش رفت محفوظ کر سکتے ہیں۔';

  @override
  String get authOrDivider => 'یا';

  @override
  String get authFairPlayNote =>
      'سکے اور ہیرے ورچوئل ہیں اور اصلی رقم میں تبدیل نہیں ہو سکتے۔';

  @override
  String get authSessionExpiredBanner =>
      'آپ سائن آؤٹ ہو گئے تھے۔ براہ کرم دوبارہ سائن اِن کریں۔';

  @override
  String get authSignedInElsewhereTitle => 'کسی دوسرے آلے پر سائن اِن ہوا';

  @override
  String get authSignedInElsewhereMessage =>
      'کسی نے آپ کے اکاؤنٹ سے دوسرے آلے پر سائن اِن کیا ہے، اس لیے آپ کو یہاں سے سائن آؤٹ کر دیا گیا ہے۔ ایک وقت میں صرف ایک آلے پر سائن اِن کیا جا سکتا ہے۔ یہاں کھیلنے کے لیے دوبارہ سائن اِن کریں — دوسرا آلہ سائن آؤٹ ہو جائے گا۔';

  @override
  String get authSignedInElsewhereBanner =>
      'آپ کے اکاؤنٹ سے کسی دوسرے آلے پر سائن اِن کیا گیا۔';

  @override
  String get authChangeLanguage => 'زبان بدلیں';

  @override
  String get authProviderGoogle => 'Google';

  @override
  String get authProviderFacebook => 'Facebook';

  @override
  String get authProviderApple => 'Apple';

  @override
  String get authProviderGuest => 'مہمان';

  @override
  String get authSaveProgressTitle => 'اپنی پیش رفت محفوظ کریں';

  @override
  String get authSaveProgressSubtitle =>
      'سائن اِن کا کوئی طریقہ جوڑیں تاکہ آپ کے سکے، لیول اور کلیکشن کبھی ضائع نہ ہوں — نئے فون پر بھی۔';

  @override
  String get authSaveBenefitKeep =>
      'اپنے تمام سکے، XP اور کاسمیٹکس برقرار رکھیں';

  @override
  String get authSaveBenefitDevices => 'کسی بھی ڈیوائس پر سائن اِن کریں';

  @override
  String get authSaveBenefitSame =>
      'وہی اکاؤنٹ — کچھ بھی ری سیٹ یا منتقل نہیں ہوتا';

  @override
  String get authSaveWithGoogle => 'Google کے ساتھ محفوظ کریں';

  @override
  String get authSaveWithFacebook => 'Facebook کے ساتھ محفوظ کریں';

  @override
  String get authSaveWithApple => 'Apple کے ساتھ محفوظ کریں';

  @override
  String get authSaveNoProviders =>
      'اس بلڈ میں سائن اِن کا کوئی طریقہ دستیاب نہیں۔';

  @override
  String get authLinkSuccessTitle => 'پیش رفت محفوظ ہو گئی!';

  @override
  String authLinkSuccessMessage(String provider) {
    return 'آپ کا اکاؤنٹ اب $provider سے منسلک ہے۔ کسی بھی ڈیوائس پر $provider سے سائن اِن کر کے کھیل جاری رکھیں۔';
  }

  @override
  String get authAlreadySavedTitle => 'آپ کی پیش رفت محفوظ ہے';

  @override
  String get authAlreadySavedMessage =>
      'یہ اکاؤنٹ سائن اِن کے ایک طریقے سے منسلک ہے، اس لیے آپ کی پیش رفت محفوظ ہے۔';

  @override
  String authConflictTitle(String provider) {
    return 'یہ $provider اکاؤنٹ پہلے سے استعمال میں ہے';
  }

  @override
  String authConflictMessage(String provider) {
    return 'اس $provider اکاؤنٹ کا اپنا الگ لوڈو رائل اکاؤنٹ پہلے سے موجود ہے۔ دونوں اکاؤنٹس کے درمیان کچھ بھی ضم یا منتقل نہیں ہوگا۔';
  }

  @override
  String get authConflictSignIn => 'اس اکاؤنٹ میں سائن اِن کریں';

  @override
  String get authConflictGuestNote =>
      'آپ کا مہمان اکاؤنٹ اسی ڈیوائس پر رہے گا — آپ سیٹنگز سے اس پر واپس جا سکتے ہیں۔';

  @override
  String get authAlreadyLinkedTitle => 'پہلے سے منسلک ہے';

  @override
  String authAlreadyLinkedMessage(String provider) {
    return 'یہ اکاؤنٹ پہلے سے کسی دوسرے $provider اکاؤنٹ سے منسلک ہے۔';
  }

  @override
  String get authLogoutTitle => 'سائن آؤٹ کریں؟';

  @override
  String get authLogoutMessage =>
      'آپ کسی بھی وقت اسی طریقے سے دوبارہ سائن اِن کر سکتے ہیں۔';

  @override
  String get authLogoutConfirm => 'سائن آؤٹ کریں';

  @override
  String get authGuestLogoutTitle => 'مہمان اکاؤنٹ سے سائن آؤٹ کریں؟';

  @override
  String get authGuestLogoutMessage =>
      'آپ مہمان کے طور پر کھیل رہے ہیں۔ اگر آپ ابھی سائن آؤٹ کرتے ہیں تو پیش رفت محفوظ کیے بغیر آپ کے سکے، لیول اور کلیکشن ضائع ہو جائیں گے۔';

  @override
  String get authGuestLogoutConfirm => 'سائن آؤٹ کریں اور پیش رفت کھو دیں';

  @override
  String get authSaveProgressFirst => 'پہلے پیش رفت محفوظ کریں';

  @override
  String get authSwitchToGuestTitle => 'مہمان اکاؤنٹ پر واپس جائیں؟';

  @override
  String get authSwitchToGuestMessage =>
      'آپ اس اکاؤنٹ سے نکل کر اس ڈیوائس پر محفوظ مہمان اکاؤنٹ کے ساتھ جاری رکھیں گے۔';

  @override
  String get authSwitchToGuestConfirm => 'مہمان پر جائیں';

  @override
  String get authGuestUnavailable => 'وہ مہمان اکاؤنٹ اب دستیاب نہیں ہے۔';

  @override
  String authWelcomeBack(String name) {
    return 'خوش آمدید، $name!';
  }

  @override
  String get boardsColorRed => 'سرخ';

  @override
  String get boardsColorGreen => 'سبز';

  @override
  String get boardsColorYellow => 'پیلی';

  @override
  String get boardsColorBlue => 'نیلی';

  @override
  String get boardsLudoBoardLabel => 'لوڈو بورڈ';

  @override
  String get boardsSnakesBoardLabel => 'سانپ سیڑھی بورڈ';

  @override
  String boardsTokenInBase(String color, int number) {
    return '$color گوٹی $number، ابتدائی گھر میں';
  }

  @override
  String boardsTokenStepsFromHome(String color, int number, int steps) {
    String _temp0 = intl.Intl.pluralLogic(
      steps,
      locale: localeName,
      other: 'منزل سے $steps خانے دور',
      one: 'منزل سے 1 خانہ دور',
    );
    return '$color گوٹی $number، $_temp0';
  }

  @override
  String boardsTokenHome(String color, int number) {
    return '$color گوٹی $number، منزل پر پہنچ گئی';
  }

  @override
  String get boardsTokenCanMove => 'چل سکتی ہے';

  @override
  String get boardsTokenMoveHint => 'یہ گوٹی چلائیں';

  @override
  String get boardsCurrentTurn => 'ابھی اس کی باری ہے';

  @override
  String boardsSnakesTokenOnSquare(String color, int square) {
    return '$color گوٹی خانہ $square پر';
  }

  @override
  String boardsSnakesTokenAtStart(String color) {
    return '$color گوٹی آغاز پر';
  }

  @override
  String boardsDiceShowing(int value) {
    return 'پانسے پر $value ہے';
  }

  @override
  String get boardsDiceRolling => 'پانسہ گھوم رہا ہے';

  @override
  String get boardsDiceRollHint => 'پانسہ پھینکیں';

  @override
  String get boardsVictoryCelebration => 'فتح کا جشن';

  @override
  String get boardsLevelUp => 'لیول بڑھ گیا';

  @override
  String get commonOk => 'ٹھیک ہے';

  @override
  String get commonCancel => 'منسوخ کریں';

  @override
  String get commonRetry => 'دوبارہ کوشش کریں';

  @override
  String get commonClose => 'بند کریں';

  @override
  String get commonContinue => 'جاری رکھیں';

  @override
  String get commonBack => 'واپس';

  @override
  String get commonDone => 'ہو گیا';

  @override
  String get commonSave => 'محفوظ کریں';

  @override
  String get commonLater => 'بعد میں';

  @override
  String get commonLoading => 'لوڈ ہو رہا ہے…';

  @override
  String get commonCopy => 'کاپی کریں';

  @override
  String get commonCopied => 'کاپی ہو گیا!';

  @override
  String get commonShare => 'شیئر کریں';

  @override
  String get commonYes => 'ہاں';

  @override
  String get commonNo => 'نہیں';

  @override
  String get commonSomethingWentWrong => 'کچھ گڑبڑ ہو گئی۔';

  @override
  String get commonNothingHereYet => 'یہاں ابھی کچھ نہیں ہے';

  @override
  String get commonYou => 'آپ';

  @override
  String get commonGuest => 'مہمان';

  @override
  String get commonCoins => 'سکے';

  @override
  String get commonDiamonds => 'ہیرے';

  @override
  String commonLevel(int level) {
    return 'لیول $level';
  }

  @override
  String commonLevelShort(int level) {
    return 'لیول $level';
  }

  @override
  String commonXpProgress(String current, String total) {
    return '$current / $total XP';
  }

  @override
  String get commonConnectionConnected => 'آن لائن';

  @override
  String get commonConnectionConnecting => 'کنیکٹ ہو رہا ہے…';

  @override
  String get commonConnectionReconnecting => 'دوبارہ کنیکٹ ہو رہا ہے…';

  @override
  String get commonConnectionOffline => 'آف لائن';

  @override
  String get commonConnectionReplaced => 'یہ گیم کہیں اور کھلا ہے';

  @override
  String get commonReconnect => 'دوبارہ کنیکٹ کریں';

  @override
  String commonSecondsShort(int seconds) {
    return '$seconds سیکنڈ';
  }

  @override
  String get commonGameLudo => 'لوڈو';

  @override
  String get commonGameSnakesLadders => 'سانپ سیڑھی';

  @override
  String get commonVariantClassic => 'کلاسک';

  @override
  String get commonVariantQuick => 'فوری';

  @override
  String commonPlayerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count کھلاڑی',
      one: '1 کھلاڑی',
    );
    return '$_temp0';
  }

  @override
  String get commonOfflineHint =>
      'آپ آف لائن ہیں۔ اپنا کنکشن چیک کریں اور دوبارہ کوشش کریں۔';

  @override
  String commonEntryFee(String amount) {
    return 'انٹری $amount';
  }

  @override
  String get commonFree => 'مفت';

  @override
  String get appTitle => 'لوڈو رائل';

  @override
  String get languageNameNative => 'اردو';

  @override
  String get cosmeticDiceClassic => 'کلاسک آئیوری';

  @override
  String get cosmeticDiceNeon => 'نیون پلس';

  @override
  String get cosmeticDiceGolden => 'شاہی سونا';

  @override
  String get cosmeticDiceAutumn => 'خزاں کا پتّا';

  @override
  String get cosmeticTokenClassic => 'کلاسک گوٹی';

  @override
  String get cosmeticTokenGem => 'جواہر';

  @override
  String get cosmeticTokenRoyal => 'شاہی گوٹی';

  @override
  String get cosmeticTokenCrown => 'تاج والی گوٹی';

  @override
  String get cosmeticLudoBoardClassic => 'کلاسک';

  @override
  String get cosmeticLudoBoardMidnight => 'آدھی رات کا سنگِ مرمر';

  @override
  String get cosmeticLudoBoardRoyal => 'شاہی دربار';

  @override
  String get cosmeticSnakesBoardClassic => 'کلاسک سبزہ زار';

  @override
  String get cosmeticSnakesBoardJungle => 'جنگل کا مندر';

  @override
  String get cosmeticSnakesBoardCandy => 'کینڈی لینڈ';

  @override
  String get cosmeticTrailNone => 'کوئی ٹریل نہیں';

  @override
  String get cosmeticTrailSparkle => 'چمک';

  @override
  String get cosmeticTrailComet => 'دُم دار ستارہ';

  @override
  String get cosmeticVictoryConfetti => 'کنفیٹی';

  @override
  String get cosmeticVictoryFireworks => 'آتش بازی';

  @override
  String get cosmeticVictoryCrown => 'سنہری تاج';

  @override
  String get cosmeticFrameNone => 'کوئی فریم نہیں';

  @override
  String get cosmeticFrameBronze => 'کانسی کا حلقہ';

  @override
  String get cosmeticFrameSilver => 'چاندی کا فاتحانہ ہار';

  @override
  String get cosmeticFrameGold => 'سونے کا فاتحانہ ہار';

  @override
  String get cosmeticFrameRoyal => 'شاہی نشان';

  @override
  String get cosmeticTitleRookie => 'نیا کھلاڑی';

  @override
  String get cosmeticTitleStrategist => 'ماہرِ حکمتِ عملی';

  @override
  String get cosmeticTitleDiceMaster => 'پانسے کا اُستاد';

  @override
  String get cosmeticTitleRoyal => 'عالی جاہ';

  @override
  String get cosmeticTitleWeeklyChampion => 'ہفتہ وار چیمپئن';

  @override
  String get cosmeticBadgeFirstWin => 'پہلی جیت';

  @override
  String get cosmeticBadgeFriendly => 'اچھی صحبت';

  @override
  String get cosmeticEmoteWave => 'ہاتھ ہلانا';

  @override
  String get cosmeticEmoteThumbs => 'شاباش';

  @override
  String get cosmeticEmoteLaugh => 'ہنسی';

  @override
  String get cosmeticEmoteWow => 'واہ';

  @override
  String get cosmeticEmoteCrown => 'تاج';

  @override
  String get cosmeticRarityCommon => 'عام';

  @override
  String get cosmeticRarityRare => 'نایاب';

  @override
  String get cosmeticRarityEpic => 'ایپک';

  @override
  String get cosmeticRarityLegendary => 'افسانوی';

  @override
  String get cosmeticKindDice => 'پانسا';

  @override
  String get cosmeticKindToken => 'گوٹیاں';

  @override
  String get cosmeticKindLudoBoard => 'لوڈو بورڈ';

  @override
  String get cosmeticKindSnakesBoard => 'سانپ سیڑھی بورڈ';

  @override
  String get cosmeticKindFrame => 'اوتار فریم';

  @override
  String get cosmeticKindTitle => 'خطاب';

  @override
  String get cosmeticKindBadge => 'بیج';

  @override
  String get cosmeticKindEmote => 'ایموٹ';

  @override
  String get cosmeticKindVictory => 'جیت کا جشن';

  @override
  String get cosmeticKindTrail => 'گوٹی کی ٹریل';

  @override
  String get errorGeneric => 'کچھ گڑبڑ ہو گئی۔ براہِ کرم دوبارہ کوشش کریں۔';

  @override
  String get errorBadRequest => 'یہ درخواست پوری نہیں ہو سکی۔';

  @override
  String get errorUnknownType =>
      'یہ سہولت دستیاب نہیں ہے۔ براہِ کرم ایپ اپ ڈیٹ کریں۔';

  @override
  String get errorRateLimited => 'ذرا آہستہ! چند لمحے رک کر دوبارہ کوشش کریں۔';

  @override
  String get errorUnauthorized =>
      'آپ کا سیشن ختم ہو گیا ہے۔ براہِ کرم دوبارہ سائن اِن کریں۔';

  @override
  String get errorUpdateRequired => 'ایپ کا نیا ورژن ضروری ہے۔';

  @override
  String get errorMaintenance =>
      'گیم سرورز پر مینٹیننس جاری ہے۔ تھوڑی دیر بعد دوبارہ کوشش کریں۔';

  @override
  String get errorNotInRoom => 'اب آپ اس روم میں نہیں ہیں۔';

  @override
  String get errorRoomNotFound => 'یہ روم اب موجود نہیں ہے۔';

  @override
  String get errorRoomFull => 'یہ روم پہلے ہی بھر چکا ہے۔';

  @override
  String get errorRoomInProgress => 'یہ گیم پہلے ہی شروع ہو چکی ہے۔';

  @override
  String get errorRoomClosed => 'یہ روم بند ہو گیا ہے۔';

  @override
  String get errorAlreadyInRoom =>
      'آپ پہلے سے ایک روم میں ہیں۔ دوسرے میں جانے کے لیے پہلے اسے چھوڑیں۔';

  @override
  String get errorNotHost => 'یہ صرف ہوسٹ کر سکتا ہے۔';

  @override
  String get errorNotEnoughPlayers =>
      'شروع کرنے کے لیے کم از کم 2 کھلاڑی چاہییں۔';

  @override
  String get errorPlayersNotReady => 'تمام کھلاڑیوں کے تیار ہونے کا انتظار ہے۔';

  @override
  String get errorNotYourTurn => 'ابھی آپ کی باری نہیں ہے۔';

  @override
  String get errorInvalidPhase => 'ابھی یہ نہیں کیا جا سکتا۔';

  @override
  String get errorIllegalMove => 'یہ چال جائز نہیں ہے۔';

  @override
  String get errorStaleState => 'بورڈ ابھی بدلا ہے۔ دوبارہ کوشش کریں۔';

  @override
  String get errorInsufficientFunds => 'اس کے لیے آپ کے پاس کافی سکے نہیں ہیں۔';

  @override
  String get errorInvalidCode =>
      'یہ روم کوڈ درست نہیں ہے۔ چیک کر کے دوبارہ کوشش کریں۔';

  @override
  String get errorRematchClosed => 'ری میچ کا وقت ختم ہو گیا۔';

  @override
  String get errorNotFriends => 'آپ صرف دوستوں کو بلا سکتے ہیں۔';

  @override
  String get errorItemNotOwned => 'یہ آئٹم ابھی آپ کے پاس نہیں ہے۔';

  @override
  String get errorBotsUnavailable =>
      'ابھی کوئی کمپیوٹر کھلاڑی دستیاب نہیں ہے۔ تھوڑی دیر میں دوبارہ کوشش کریں۔';

  @override
  String get errorBotsNotAllowed =>
      'اس روم میں کمپیوٹر کھلاڑیوں کی اجازت نہیں ہے۔';

  @override
  String get errorInternal =>
      'ہماری طرف سے کچھ گڑبڑ ہو گئی۔ براہِ کرم دوبارہ کوشش کریں۔';

  @override
  String get errorClientVersionRequired =>
      'ایپ اپنا ورژن نہیں پہچان سکی۔ براہِ کرم ایپ اپ ڈیٹ یا دوبارہ انسٹال کریں۔';

  @override
  String get errorEnvironmentMismatch => 'یہ ایپ بلڈ غلط سرور سے جڑا ہوا ہے۔';

  @override
  String get errorInvalidCredential =>
      'سائن اِن نہیں ہو سکا۔ براہِ کرم دوبارہ کوشش کریں۔';

  @override
  String get errorRefreshReused =>
      'آپ کی حفاظت کے لیے آپ کو سائن آؤٹ کر دیا گیا ہے۔ براہِ کرم دوبارہ سائن اِن کریں۔';

  @override
  String get errorSessionReplaced =>
      'آپ کے اکاؤنٹ سے کسی دوسرے آلے پر سائن اِن کیا گیا۔ براہِ کرم دوبارہ سائن اِن کریں۔';

  @override
  String get errorForbidden => 'آپ کو یہ کرنے کی اجازت نہیں ہے۔';

  @override
  String get errorNotFound => 'جو آپ ڈھونڈ رہے تھے وہ نہیں ملا۔';

  @override
  String get errorIdentityConflict =>
      'یہ سائن اِن اکاؤنٹ پہلے سے کسی دوسرے کھلاڑی پروفائل کا ہے۔';

  @override
  String get errorProviderAlreadyLinked =>
      'آپ کی پروفائل سے اس قسم کا ایک دوسرا اکاؤنٹ پہلے ہی منسلک ہے۔';

  @override
  String get errorAlreadyOwned => 'یہ آئٹم پہلے ہی آپ کے پاس ہے۔';

  @override
  String get errorAlreadyClaimed => 'آپ یہ انعام پہلے ہی لے چکے ہیں۔';

  @override
  String get errorAlreadyFriends => 'آپ پہلے سے دوست ہیں۔';

  @override
  String get errorNotCompleted => 'انعام لینے کے لیے پہلے یہ مشن مکمل کریں۔';

  @override
  String get errorItemLocked => 'یہ آئٹم ابھی لاک ہے۔';

  @override
  String get errorProviderUnavailable =>
      'سائن اِن سروس ابھی دستیاب نہیں ہے۔ براہِ کرم بعد میں کوشش کریں۔';

  @override
  String get errorNetwork =>
      'گیم سروس سے رابطہ نہیں ہو پا رہا۔ اپنا انٹرنیٹ کنکشن چیک کریں۔';

  @override
  String get errorTimeout =>
      'کنکشن کا وقت ختم ہو گیا۔ براہِ کرم دوبارہ کوشش کریں۔';

  @override
  String get errorBadResponse =>
      'سرور سے غیر متوقع جواب ملا۔ براہِ کرم دوبارہ کوشش کریں۔';

  @override
  String get errorCancelled => 'منسوخ کر دیا گیا۔';

  @override
  String get errorNotConnected =>
      'ابھی آپ کنیکٹ نہیں ہیں۔ دوبارہ کنیکٹ ہو رہا ہے…';

  @override
  String errorRateLimitedRetry(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'بہت زیادہ کوششیں۔ $seconds سیکنڈ بعد دوبارہ کوشش کریں۔',
      one: 'بہت زیادہ کوششیں۔ 1 سیکنڈ بعد دوبارہ کوشش کریں۔',
    );
    return '$_temp0';
  }

  @override
  String get errorInvalidName =>
      'یہ نام استعمال نہیں کیا جا سکتا۔ براہِ کرم کوئی اور نام چنیں۔';

  @override
  String get errorInvalidNameTooShort => 'نام میں کم از کم 3 حروف ہونے چاہییں۔';

  @override
  String get errorInvalidNameTooLong =>
      'نام میں زیادہ سے زیادہ 16 حروف ہو سکتے ہیں۔';

  @override
  String get errorInvalidNameCharacters =>
      'صرف حروف، اعداد، اسپیس، _ . یا - استعمال کریں (کم از کم ایک حرف)۔ ایموجی یا علامات نہیں۔';

  @override
  String get errorInvalidNameReserved =>
      'یہ نام مخصوص ہے۔ براہِ کرم کوئی اور نام چنیں۔';

  @override
  String get errorInvalidNameInappropriate =>
      'اس نام کی اجازت نہیں ہے۔ براہِ کرم کوئی مناسب نام چنیں۔';

  @override
  String get gateSplashTagline => 'پانسہ پھینکو۔ دوڑ لگاؤ۔ راج کرو۔';

  @override
  String get gateStatusChecking => 'گیم سرورز چیک کیے جا رہے ہیں…';

  @override
  String get gateStatusSigningIn => 'آپ کو سائن اِن کیا جا رہا ہے…';

  @override
  String get gateStatusLoadingProfile => 'آپ کی پروفائل لوڈ ہو رہی ہے…';

  @override
  String get gateUpdateNow => 'ابھی اپڈیٹ کریں';

  @override
  String get gateForceUpdateTitle => 'اپڈیٹ ضروری ہے';

  @override
  String get gateForceUpdateMessage =>
      'لوڈو رائل کا یہ ورژن اب سپورٹ نہیں ہوتا۔ آن لائن کھیلتے رہنے کے لیے اپڈیٹ کریں — آپ کے سکے اور پیش رفت محفوظ ہیں۔';

  @override
  String get gateInstalledVersion => 'انسٹال شدہ ورژن';

  @override
  String get gateRequiredVersion => 'مطلوبہ ورژن';

  @override
  String get gateStoreNotReadyTitle => 'اپڈیٹ ابھی اسٹور میں دستیاب نہیں';

  @override
  String get gateStoreNotReadyMessage =>
      'نیا ورژن جلد آپ کے ایپ اسٹور میں آ رہا ہے۔ تھوڑی دیر بعد دوبارہ چیک کریں۔';

  @override
  String get gateCheckAgain => 'دوبارہ چیک کریں';

  @override
  String get gateOptionalUpdateTitle => 'نیا ورژن دستیاب ہے';

  @override
  String gateOptionalUpdateMessage(String version) {
    return 'ورژن $version میں خرابیوں کی درستگی اور بہتریاں ہیں۔ بہترین گیمز کے لیے ابھی اپڈیٹ کریں۔';
  }

  @override
  String get gateMaintenanceTitle => 'ہم بورڈز چمکا رہے ہیں';

  @override
  String get gateMaintenanceMessage =>
      'لوڈو رائل پر مینٹیننس جاری ہے۔ آپ کے سکے، پیش رفت اور جاری میچ محفوظ ہیں — ہماری واپسی پر میچ دوبارہ شروع ہوں گے۔';

  @override
  String gateMaintenanceEstimatedEnd(String time) {
    return 'متوقع اختتام: $time';
  }

  @override
  String get gateMaintenanceEstimateNote =>
      'یہ صرف ایک اندازہ ہے اور بدل سکتا ہے۔';

  @override
  String get gateMaintenanceAutoCheck =>
      'ہم ہر 30 سیکنڈ بعد خود بخود دوبارہ چیک کریں گے۔';

  @override
  String gateLastChecked(String time) {
    return 'آخری بار $time پر چیک کیا گیا';
  }

  @override
  String get gateCheckingNow => 'چیک ہو رہا ہے…';

  @override
  String get gateServiceReachable => 'گیم سروس سے رابطہ ہے';

  @override
  String get gateServiceUnreachableShort => 'گیم سروس سے رابطہ نہیں';

  @override
  String get gateUnreachableTitle => 'گیم سروس تک رسائی نہیں ہو پا رہی';

  @override
  String get gateUnreachableMessage =>
      'آن لائن کھیلنے کے لیے لوڈو رائل کو انٹرنیٹ کنکشن درکار ہے۔ اپنا وائی فائی یا موبائل ڈیٹا چیک کریں اور دوبارہ کوشش کریں۔';

  @override
  String get gateUnreachableLastKnownMaintenance =>
      'ہمیں ملنے والی آخری اطلاع کے مطابق سرورز پر مینٹیننس جاری تھی۔';

  @override
  String get gateUnreachableLastKnownUpdate =>
      'ہمیں ملنے والی آخری اطلاع کے مطابق اس ورژن کو اپڈیٹ کرنا ضروری ہے۔';

  @override
  String get gateNotFoundTitle => 'ابھی دستیاب نہیں';

  @override
  String get gateNotFoundMessage =>
      'لوڈو رائل کا یہ حصہ اس ورژن میں ابھی دستیاب نہیں ہے۔';

  @override
  String get gateGoHome => 'ہوم پر واپس جائیں';

  @override
  String homeGreeting(String name) {
    return 'ہیلو، $name';
  }

  @override
  String get homeQuickPlay => 'فوری کھیل';

  @override
  String homeQuickPlayDetails(String game, String variant, String players) {
    return '$game · $variant · $players';
  }

  @override
  String get homePrivateRoom => 'پرائیویٹ روم';

  @override
  String get homePrivateRoomSubtitle => 'دوستوں کے لیے روم بنائیں';

  @override
  String get homeJoinWithCode => 'کوڈ سے شامل ہوں';

  @override
  String get homeJoinWithCodeSubtitle => 'روم کوڈ درج کریں';

  @override
  String get homePlayOnline => 'آن لائن کھیلیں';

  @override
  String get homePlayWithFriends => 'دوستوں کے ساتھ کھیلیں';

  @override
  String get homePracticeVsBots => 'بوٹس کے ساتھ پریکٹس';

  @override
  String get homeLudoTagline => 'چاروں گوٹیاں گھر پہنچاؤ';

  @override
  String get homeSnakesTagline => 'سیڑھی چڑھو، سانپ سے بچو';

  @override
  String get homeMissions => 'مشنز';

  @override
  String get homeMissionsSubtitle => 'روزانہ اور ہفتہ وار اہداف';

  @override
  String get homeCollection => 'کلیکشن';

  @override
  String get homeCollectionSubtitle => 'پانسے، گوٹیاں اور فریم';

  @override
  String get homeFriends => 'دوست';

  @override
  String get homeFriendsSubtitle => 'اپنے دوستوں کے ساتھ کھیلیں';

  @override
  String get homeEvents => 'ایونٹس';

  @override
  String get homeEventsSubtitle => 'محدود وقت کے کپ';

  @override
  String get homeExploreHeader => 'مزید دریافت کریں';

  @override
  String get homeGamesHeader => 'گیم منتخب کریں';

  @override
  String get homeSaveProgressTooltip => 'پیش رفت محفوظ کریں';

  @override
  String get homeProfileTooltip => 'پروفائل';

  @override
  String get homeSettingsTooltip => 'سیٹنگز';

  @override
  String get homeThemeTooltip => 'لائٹ/ڈارک تھیم بدلیں';

  @override
  String get homeWalletTooltip => 'والٹ';

  @override
  String homeOptionsOnlineTitle(String game) {
    return '$game آن لائن';
  }

  @override
  String homeOptionsFriendsTitle(String game) {
    return 'دوستوں کے ساتھ $game';
  }

  @override
  String homeOptionsPracticeTitle(String game) {
    return '$game کی پریکٹس';
  }

  @override
  String get homeOptionsPrivateRoomTitle => 'پرائیویٹ روم بنائیں';

  @override
  String get homeGameLabel => 'گیم';

  @override
  String get homePlayersLabel => 'کھلاڑی';

  @override
  String get homeModeLabel => 'موڈ';

  @override
  String get homeBotsLabel => 'بوٹس';

  @override
  String get homeModeClassicCaption => 'مکمل قواعد';

  @override
  String get homeModeQuickCaption => 'مختصر گیمز';

  @override
  String homeBotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بوٹس',
      one: '1 بوٹ',
    );
    return '$_temp0';
  }

  @override
  String get homeFindMatch => 'میچ تلاش کریں';

  @override
  String get homeCreateRoom => 'روم بنائیں';

  @override
  String get homeStartPractice => 'پریکٹس شروع کریں';

  @override
  String get homeHaveACode => 'کوڈ ہے؟ روم میں شامل ہوں';

  @override
  String homeEntryFeeNote(String fee) {
    return 'انٹری فیس $fee سکے · جیتنے والے کو پورا پاٹ';
  }

  @override
  String get homePracticeNote =>
      'پریکٹس مفت ہے: سکے نہیں لگتے، پھر بھی XP اور مشن کی پیش رفت ملتی ہے۔';

  @override
  String homeNotEnoughCoins(String fee) {
    return 'اس میچ کے لیے کم از کم $fee سکے درکار ہیں۔';
  }

  @override
  String get homeJoinCodeTitle => 'پرائیویٹ روم میں شامل ہوں';

  @override
  String get homeJoinCodeLabel => 'روم کوڈ';

  @override
  String get homeJoinCodeHelper => 'ہوسٹ سے 6 حروف والا کوڈ مانگیں۔';

  @override
  String get homeJoinCodeInvalid => 'روم کوڈ میں 6 حروف یا ہندسے ہوتے ہیں۔';

  @override
  String get homeJoinCodeAction => 'روم میں شامل ہوں';

  @override
  String homeLevelUpToast(int level) {
    return 'لیول اپ! آپ لیول $level پر پہنچ گئے۔';
  }

  @override
  String homeCoinsGainedToast(String amount) {
    return '+$amount سکے';
  }

  @override
  String get homeQuickPlaySubtitle =>
      'بے ترتیب کھلاڑی ڈھونڈیں اور ابھی شروع کریں';

  @override
  String get homePlayNow => 'ابھی کھیلیں';

  @override
  String get homeQuickLudo => 'فوری لوڈو';

  @override
  String get homeChangeGameHint => 'گیم تبدیل کریں';

  @override
  String get homeChangePlayersHint => 'کھلاڑیوں کی تعداد تبدیل کریں';

  @override
  String get homeGamesSubtitle =>
      'گیم چنیں، پھر آن لائن، دوستوں کے ساتھ یا بوٹس کے خلاف کھیلیں۔';

  @override
  String get homeNavHome => 'ہوم';

  @override
  String get homeNavGames => 'گیمز';

  @override
  String get homeNavMissions => 'مشنز';

  @override
  String get homeNavFriends => 'دوست';

  @override
  String get homeNavProfile => 'پروفائل';

  @override
  String get metaMissionsTitle => 'مشنز';

  @override
  String get metaEventsTitle => 'ایونٹس';

  @override
  String get metaCollectionTitle => 'کلیکشن روم';

  @override
  String get metaFriendsTitle => 'دوست';

  @override
  String get metaLeaderboardTitle => 'ہفتہ وار رینکنگ';

  @override
  String get metaLevelRoadTitle => 'لیول روڈ';

  @override
  String get metaDailyTitle => 'روزانہ مشنز';

  @override
  String get metaWeeklyTitle => 'ہفتہ وار چیلنج';

  @override
  String get metaClaim => 'انعام لیں';

  @override
  String get metaStatusInProgress => 'جاری ہے';

  @override
  String get metaStatusReady => 'انعام لینے کے لیے تیار';

  @override
  String get metaStatusClaimed => 'انعام لے لیا گیا';

  @override
  String get metaCollected => 'انعام مل گیا — آپ کے اکاؤنٹ میں شامل کر دیا گیا';

  @override
  String metaProgressCount(String progress, String target) {
    return '$progress / $target';
  }

  @override
  String metaMissionSemantics(String title, String progress, String state) {
    return '$title۔ پیش رفت $progress۔ $state';
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
    return '$amount سکے';
  }

  @override
  String metaRewardDiamondsLabel(String amount) {
    return '$amount ہیرے';
  }

  @override
  String metaRewardXpLabel(String amount) {
    return '$amount تجربہ پوائنٹس';
  }

  @override
  String metaRewardItemLabel(String name, String kind) {
    return '$name ($kind)';
  }

  @override
  String get metaGameAny => 'کوئی بھی گیم';

  @override
  String metaResetsDailyAt(String time) {
    return 'نئے مشنز $time بجے';
  }

  @override
  String metaResetsWeeklyAt(String day, String time) {
    return '$day کو $time بجے ری سیٹ';
  }

  @override
  String metaEventEndsAt(String date) {
    return '$date کو ختم';
  }

  @override
  String metaWhenWithCountdown(String when, String duration) {
    return '$when · $duration میں';
  }

  @override
  String metaDurationDaysHours(int days, int hours) {
    return '$days دن $hours گھنٹے';
  }

  @override
  String metaDurationHoursMinutes(int hours, int minutes) {
    return '$hours گھنٹے $minutes منٹ';
  }

  @override
  String metaDurationMinutes(int minutes) {
    return '$minutes منٹ';
  }

  @override
  String get metaNoPenaltyNote =>
      'کوئی دن رہ گیا؟ کوئی بات نہیں — آپ کا XP، لیول اور کلیکشن ہمیشہ محفوظ رہتے ہیں۔';

  @override
  String get metaMissionsEmptyTitle => 'ابھی کوئی مشن نہیں';

  @override
  String get metaMissionsEmptyMessage =>
      'ہر روز نئے مشنز آتے ہیں۔ ریفریش کرنے کے لیے نیچے کھینچیں۔';

  @override
  String metaRetryHint(String message) {
    return '$message دوبارہ کوشش کے لیے پھر ٹیپ کریں۔';
  }

  @override
  String get metaNewItemsTitle => 'آپ کے کلیکشن میں نیا!';

  @override
  String metaNewItemsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'یہ $count آئٹمز اب آپ کے ہیں — انہیں لگائیں اور مزے کریں۔',
      one: 'یہ آئٹم اب آپ کا ہے — اسے لگائیں اور مزے کریں۔',
    );
    return '$_temp0';
  }

  @override
  String get metaNice => 'زبردست!';

  @override
  String get metaViewCollection => 'کلیکشن دیکھیں';

  @override
  String get metaEventDetails => 'تفصیل';

  @override
  String get metaMissionLudoTimeTitle => 'لوڈو ٹائم';

  @override
  String get metaMissionClimbTitle => 'سیڑھی چڑھو';

  @override
  String get metaMissionWarmUpTitle => 'وارم اپ';

  @override
  String get metaMissionFriendlyTableTitle => 'دوستوں کی محفل';

  @override
  String get metaMissionStayToEndTitle => 'آخر تک ڈٹے رہو';

  @override
  String get metaMissionTasteOfVictoryTitle => 'جیت کا مزہ';

  @override
  String get metaMissionQuickDrawTitle => 'فٹافٹ چال';

  @override
  String get metaMissionWeeklyChallengeTitle => 'ہفتہ وار چیلنج';

  @override
  String get metaMissionAutumnSprintTitle => 'خزاں کی دوڑ';

  @override
  String get metaMissionFallbackTitle => 'مشن';

  @override
  String metaMissionLudoMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count لوڈو میچ مکمل کریں۔',
      one: '1 لوڈو میچ مکمل کریں۔',
    );
    return '$_temp0';
  }

  @override
  String metaMissionSnakesMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سانپ سیڑھی میچ مکمل کریں۔',
      one: '1 سانپ سیڑھی میچ مکمل کریں۔',
    );
    return '$_temp0';
  }

  @override
  String metaMissionAnyMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'کسی بھی گیم میں $count میچ مکمل کریں۔',
      one: 'کسی بھی گیم میں 1 میچ مکمل کریں۔',
    );
    return '$_temp0';
  }

  @override
  String metaMissionFriendPrivateDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'دوستوں کے ساتھ $count پرائیویٹ میچ مکمل کریں۔',
      one: 'کسی دوست کے ساتھ ایک پرائیویٹ میچ مکمل کریں۔',
    );
    return '$_temp0';
  }

  @override
  String metaMissionNoLeavingDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'درمیان میں چھوڑے بغیر $count میچ مکمل کریں۔',
      one: 'درمیان میں چھوڑے بغیر ایک میچ مکمل کریں۔',
    );
    return '$_temp0';
  }

  @override
  String metaMissionWinDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count میچ جیتیں۔',
      one: '1 میچ جیتیں۔',
    );
    return '$_temp0';
  }

  @override
  String metaMissionQuickLudoDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count فوری لوڈو میچ مکمل کریں۔',
      one: '1 فوری لوڈو میچ مکمل کریں۔',
    );
    return '$_temp0';
  }

  @override
  String metaMissionWeeklyDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'لوڈو اور سانپ سیڑھی میں کل $count میچ مکمل کریں۔',
      one: 'لوڈو یا سانپ سیڑھی میں 1 میچ مکمل کریں۔',
    );
    return '$_temp0';
  }

  @override
  String get metaEventAutumnCupTitle => 'آٹم کپ';

  @override
  String get metaEventAutumnCupDesc =>
      'فوری لوڈو کے ساتھ موسم کا جشن منائیں اور خزاں کا پتّا پانسا جیتیں۔';

  @override
  String metaEventWindow(String start, String end) {
    return '$start – $end';
  }

  @override
  String get metaEventLiveBadge => 'ایونٹ جاری ہے';

  @override
  String get metaEventMissionsTitle => 'ایونٹ مشنز';

  @override
  String get metaEventRulesTitle => 'یہ کیسے کام کرتا ہے';

  @override
  String get metaEventRuleComplete =>
      'ایونٹ جاری رہنے کے دوران ایونٹ مشنز مکمل کریں۔';

  @override
  String get metaEventRuleEligible =>
      'میچ تب شمار ہوتا ہے جب آپ اسے آخر تک کھیلیں، کم از کم 3 چالیں چلیں اور وہ کم از کم 30 سیکنڈ چلے۔';

  @override
  String get metaEventRuleClaim =>
      'ہر انعام یہیں لیں — وہ فوراً آپ کے اکاؤنٹ میں شامل ہو جاتا ہے۔';

  @override
  String get metaEventRuleEnd =>
      'ایونٹ ختم ہونے سے پہلے نہ لیے گئے انعامات پھر دستیاب نہیں رہتے۔ آپ کے XP، لیول اور کلیکشن پر کبھی اثر نہیں پڑتا۔';

  @override
  String get metaNoEventsTitle => 'ابھی کوئی ایونٹ نہیں';

  @override
  String get metaNoEventsMessage =>
      'نئے ایونٹس یہاں نظر آئیں گے۔ آپ کے روزانہ مشنز ہمیشہ دستیاب ہیں۔';

  @override
  String get metaGoToMissions => 'مشنز پر جائیں';

  @override
  String metaXpToNextLevel(String xp, int level) {
    return 'لیول $level کے لیے $xp XP باقی';
  }

  @override
  String get metaMaxLevelReached =>
      'زیادہ سے زیادہ لیول مکمل — XP اب بھی ہفتہ وار رینکنگ میں شمار ہوتا ہے';

  @override
  String get metaMaxBadge => 'MAX';

  @override
  String metaTotalXp(String xp) {
    return 'کل XP: $xp';
  }

  @override
  String get metaHowToEarnXp => 'XP کیسے کمائیں';

  @override
  String metaXpForMatch(int xp) {
    return 'ہر مکمل میچ پر +$xp XP';
  }

  @override
  String metaXpForWin(int xp) {
    return 'جیت پر +$xp XP بونس';
  }

  @override
  String metaXpForFriend(int xp) {
    return 'کسی دوست کے ساتھ کھیلنے پر +$xp XP';
  }

  @override
  String get metaXpForMissions => 'مشن کے انعام میں بھی XP ملتا ہے';

  @override
  String get metaXpFairPlayNote =>
      'میچ تب شمار ہوتے ہیں جب آخر تک کھیلے جائیں (کم از کم 3 چالیں اور 30 سیکنڈ)۔ بوٹس کو کبھی XP نہیں ملتا۔';

  @override
  String get metaMilestonesTitle => 'سنگِ میل';

  @override
  String get metaMilestoneUnlocked => 'ان لاک ہو گیا';

  @override
  String metaMilestoneNext(String xp) {
    return 'اگلا سنگِ میل · $xp XP باقی';
  }

  @override
  String metaMilestoneLocked(String xp) {
    return '$xp XP باقی';
  }

  @override
  String get metaNoMilestones => 'سنگِ میل یہاں نظر آئیں گے۔';

  @override
  String get metaLevelUpTitle => 'لیول اپ!';

  @override
  String metaLevelUpMessage(int level) {
    return 'آپ لیول $level پر پہنچ گئے۔';
  }

  @override
  String get metaUnlockedHeader => 'آپ کے لیے ان لاک ہوا';

  @override
  String get metaLevelUpContinue => 'شاندار!';

  @override
  String get metaYourLook => 'آپ کا لُک';

  @override
  String metaCollectedCount(String owned, String total) {
    return '$total میں سے $owned جمع';
  }

  @override
  String get metaTabDice => 'پانسے';

  @override
  String get metaTabTokens => 'گوٹیاں';

  @override
  String get metaTabLudoBoards => 'لوڈو بورڈ';

  @override
  String get metaTabSnakesBoards => 'سانپ سیڑھی بورڈ';

  @override
  String get metaTabTrails => 'ٹریل';

  @override
  String get metaTabVictory => 'جیت کا جشن';

  @override
  String get metaTabFrames => 'فریم';

  @override
  String get metaTabTitles => 'ٹائٹل';

  @override
  String get metaTabBadges => 'بیجز';

  @override
  String get metaTabEmotes => 'ایموٹس';

  @override
  String get metaFilterAll => 'سب';

  @override
  String get metaFilterOwned => 'آپ کے پاس';

  @override
  String get metaFilterLocked => 'ان لاک کرنا ہے';

  @override
  String get metaEquipped => 'لگایا ہوا';

  @override
  String get metaOwned => 'آپ کے پاس ہے';

  @override
  String get metaLocked => 'لاک';

  @override
  String get metaNewBadge => 'نیا';

  @override
  String metaItemSemantics(
    String name,
    String rarity,
    String state,
    String how,
  ) {
    return '$name، $rarity، $state۔ $how';
  }

  @override
  String get metaAcqStarter => 'ابتدائی آئٹم';

  @override
  String metaAcqLevel(int level) {
    return 'لیول $level تک پہنچیں';
  }

  @override
  String get metaAcqMission => 'مشن انعام';

  @override
  String get metaAcqWeeklyChallenge => 'ہفتہ وار چیلنج کا انعام';

  @override
  String get metaAcqFirstWin => 'اپنا پہلا میچ جیتیں';

  @override
  String get metaAcqEvent => 'ایونٹ انعام';

  @override
  String get metaAcqAutumnCup => 'آٹم کپ کا انعام';

  @override
  String metaPriceCoins(String amount) {
    return '$amount سکے';
  }

  @override
  String metaPriceDiamonds(String amount) {
    return '$amount ہیرے';
  }

  @override
  String get metaEquip => 'لگائیں';

  @override
  String get metaEquipDefault => 'ڈیفالٹ لگائیں';

  @override
  String get metaEquippedToast => 'لگا دیا!';

  @override
  String get metaDefaultEquippedToast => 'ڈیفالٹ لُک واپس لگا دیا';

  @override
  String get metaEmoteHint => 'میچ کے دوران ایموٹ بٹن سے اپنے ایموٹس بھیجیں۔';

  @override
  String get metaBadgeHint =>
      'بیجز آپ کی کامیابیوں کا جشن ہیں۔ یہ ہمیشہ آپ کے رہیں گے۔';

  @override
  String metaBuyFor(String price) {
    return '$price میں خریدیں';
  }

  @override
  String get metaBuy => 'خریدیں';

  @override
  String metaPurchaseTitle(String item) {
    return '$item خریدیں؟';
  }

  @override
  String get metaPrice => 'قیمت';

  @override
  String get metaYourBalance => 'آپ کا بیلنس';

  @override
  String get metaBalanceAfter => 'خریداری کے بعد';

  @override
  String metaNeedMore(String amount) {
    return 'آپ کو $amount مزید چاہیے۔ میچ جیت کر اور مشنز مکمل کر کے مزید کمائیں۔';
  }

  @override
  String get metaCosmeticOnlyNote =>
      'صرف سجاوٹ کے لیے — اس سے پانسے، قواعد یا میچ میکنگ کبھی نہیں بدلتے۔';

  @override
  String metaPurchaseSuccess(String item) {
    return '$item اب آپ کے کلیکشن میں ہے!';
  }

  @override
  String get metaNotEnoughCoins => 'اس آئٹم کے لیے سکے کم ہیں۔';

  @override
  String get metaNotEnoughDiamonds => 'اس آئٹم کے لیے ہیرے کم ہیں۔';

  @override
  String get metaAlreadyOwned => 'یہ آئٹم پہلے سے آپ کے پاس ہے۔';

  @override
  String get metaItemNotForSale =>
      'یہ آئٹم خریدا نہیں جاتا، کھیل کر ان لاک ہوتا ہے۔';

  @override
  String metaUnlocksAtLevel(int level) {
    return 'لیول $level پر پہنچتے ہی خود بخود ان لاک ہو جائے گا۔';
  }

  @override
  String get metaEarnFromMissionsHint =>
      'اسے متعلقہ مشن یا ایونٹ مکمل کر کے حاصل کریں — کچھ خریدنے کی ضرورت نہیں۔';

  @override
  String get metaAllOwnedInKind =>
      'آپ نے یہاں سب کچھ ان لاک کر لیا ہے۔ بہت خوب!';

  @override
  String get metaNothingOwnedInKind =>
      'یہاں ابھی کچھ نہیں — مزید ان لاک کرنے کے لیے کھیلتے رہیں۔';

  @override
  String get metaCollectionFairNote =>
      'ہر آئٹم صرف سجاوٹ کے لیے ہے اور اسے پانے کا طریقہ طے ہے — کوئی رینڈم باکس نہیں، کھیل میں کوئی فائدہ نہیں۔';

  @override
  String get metaDescDiceClassic =>
      'صاف کالے نقطوں والے سدا بہار آئیوری پانسے۔';

  @override
  String get metaDescDiceNeon => 'چمکتے پانسے جو ہر پھینک کے ساتھ دھڑکتے ہیں۔';

  @override
  String get metaDescDiceGolden => 'شاہی شان والے چمکدار سنہرے پانسے۔';

  @override
  String get metaDescDiceAutumn => 'آٹم کپ کے گرم عنبری رنگ کے پانسے۔';

  @override
  String get metaDescTokenClassic => 'وہ گوٹی جسے ہر کوئی جانتا ہے۔';

  @override
  String get metaDescTokenGem =>
      'تراشے ہوئے جواہر جیسی گوٹیاں جو روشنی میں چمکتی ہیں۔';

  @override
  String get metaDescTokenRoyal => 'ننھے تاج پہنے گوٹیاں۔';

  @override
  String get metaDescTokenCrown => 'تاج کی شکل کی ایک لیجنڈری گوٹی۔';

  @override
  String get metaDescLudoBoardClassic => 'روایتی چار رنگوں والا لوڈو بورڈ۔';

  @override
  String get metaDescLudoBoardMidnight => 'چاندی کی جڑاؤ والا گہرا سنگِ مرمر۔';

  @override
  String get metaDescLudoBoardRoyal => 'سنہرے اور گہرے سرخ رنگ میں محل کا صحن۔';

  @override
  String get metaDescSnakesBoardClassic =>
      'ہرے گھاس کے میدان، دوستانہ سانپ، مضبوط سیڑھیاں۔';

  @override
  String get metaDescSnakesBoardJungle => 'بیلیں، کھنڈرات اور مندر کی سیڑھیاں۔';

  @override
  String get metaDescSnakesBoardCandy =>
      'ملیٹھی کینڈی کے سانپ اور کینڈی کین کی سیڑھیاں۔';

  @override
  String get metaDescTrailNone => 'صاف چالیں، کوئی نشان نہیں۔';

  @override
  String get metaDescTrailSparkle => 'ہر چال کے پیچھے چمک کی بوچھاڑ۔';

  @override
  String get metaDescTrailComet => 'دہکتی دم دار ستارے جیسی دم۔';

  @override
  String get metaDescVictoryConfetti => 'کنفیٹی کے ساتھ کلاسک جشن۔';

  @override
  String get metaDescVictoryFireworks => 'جیتنے پر آسمان روشن کر دیں۔';

  @override
  String get metaDescVictoryCrown => 'فاتح پر سنہرا تاج اترتا ہے۔';

  @override
  String get metaDescFrameNone => 'آپ کا اوتار، بغیر فریم کے۔';

  @override
  String get metaDescFrameBronze =>
      'آپ کے اوتار کے گرد کانسی کا ایک سادہ حلقہ۔';

  @override
  String get metaDescFrameSilver => 'چاندی کا لارل ہار۔';

  @override
  String get metaDescFrameGold => 'تجربہ کار کھلاڑیوں کے لیے سنہرا لارل ہار۔';

  @override
  String get metaDescFrameRoyal => 'ایک آراستہ شاہی نشان۔';

  @override
  String get metaDescTitleRookie => 'ہر کوئی کہیں سے شروعات کرتا ہے۔';

  @override
  String get metaDescTitleStrategist =>
      'ان کھلاڑیوں کے لیے جو تین چالیں آگے سوچتے ہیں۔';

  @override
  String get metaDescTitleDiceMaster => 'لگتا ہے پانسے آپ کی بات سنتے ہیں۔';

  @override
  String get metaDescTitleRoyal => 'سچے شاہی کھلاڑیوں کے لیے۔';

  @override
  String get metaDescTitleWeeklyChampion => 'ہفتہ وار چیلنج مکمل کیا۔';

  @override
  String get metaDescBadgeFirstWin => 'آپ نے اپنا پہلا میچ جیتا۔';

  @override
  String get metaDescBadgeFriendly => 'ہفتہ وار چیلنج مکمل کیا۔';

  @override
  String get metaDescEmoteWave => 'سلام کہیں۔';

  @override
  String get metaDescEmoteThumbs => 'بہت خوب!';

  @override
  String get metaDescEmoteLaugh => 'ساتھ مل کر ہنسیں۔';

  @override
  String get metaDescEmoteWow => 'کیا واقعی ایسا ہوا؟';

  @override
  String get metaDescEmoteCrown => 'دکھائیں کہ بورڈ پر کس کا راج ہے۔';

  @override
  String get metaYourFriendCode => 'آپ کا فرینڈ کوڈ';

  @override
  String get metaFriendCodeHint =>
      'اسے شیئر کریں تاکہ دوست آپ کو شامل کر سکیں۔';

  @override
  String metaFriendCodeSemantics(String code) {
    return 'فرینڈ کوڈ: $code';
  }

  @override
  String metaShareFriendCodeMessage(String code) {
    return 'آئیں مل کر لوڈو رائل کھیلیں! میرے کوڈ سے مجھے دوست بنائیں: $code';
  }

  @override
  String get metaAddFriend => 'دوست شامل کریں';

  @override
  String get metaAdd => 'شامل کریں';

  @override
  String get metaAddFriendTitle => 'دوست شامل کریں';

  @override
  String get metaAddFriendHelp =>
      'اپنے دوست کا کوڈ درج کریں۔ انہیں یہ اپنی دوست اسکرین پر ملے گا۔';

  @override
  String get metaFriendCodeLabel => 'فرینڈ کوڈ';

  @override
  String get metaFriendCodeHintExample => 'u_abcd 2345 wxyz';

  @override
  String get metaPaste => 'پیسٹ کریں';

  @override
  String get metaSendRequest => 'درخواست بھیجیں';

  @override
  String get metaFriendCodeRequired => 'فرینڈ کوڈ درج کریں۔';

  @override
  String get metaInvalidFriendCode =>
      'یہ فرینڈ کوڈ جیسا نہیں لگتا۔ یہ u_ سے شروع ہوتا ہے اور اس کے بعد حروف اور اعداد ہوتے ہیں۔';

  @override
  String metaRequestSent(String name) {
    return '$name کو فرینڈ درخواست بھیج دی گئی';
  }

  @override
  String metaNowFriends(String name) {
    return 'آپ اور $name اب دوست ہیں!';
  }

  @override
  String get metaAlreadyFriends => 'آپ پہلے سے دوست ہیں۔';

  @override
  String get metaTabFriends => 'دوست';

  @override
  String get metaTabRequests => 'درخواستیں';

  @override
  String get metaTabRecent => 'حالیہ';

  @override
  String get metaOnline => 'آن لائن';

  @override
  String get metaOffline => 'آف لائن';

  @override
  String get metaMoreActions => 'مزید اختیارات';

  @override
  String get metaRemoveFriend => 'دوست ہٹائیں';

  @override
  String metaRemoveFriendTitle(String name) {
    return '$name کو ہٹائیں؟';
  }

  @override
  String get metaRemoveFriendMessage =>
      'آپ فرینڈ کوڈ سے کبھی بھی ایک دوسرے کو دوبارہ شامل کر سکتے ہیں۔';

  @override
  String get metaRemove => 'ہٹائیں';

  @override
  String metaFriendRemoved(String name) {
    return '$name کو آپ کے دوستوں سے ہٹا دیا گیا';
  }

  @override
  String get metaIncomingRequests => 'موصول درخواستیں';

  @override
  String get metaOutgoingRequests => 'بھیجی گئی درخواستیں';

  @override
  String get metaWantsToBeFriends => 'آپ کا دوست بننا چاہتے ہیں';

  @override
  String get metaRequestPending => 'جواب کا انتظار';

  @override
  String get metaAccept => 'قبول کریں';

  @override
  String get metaDecline => 'انکار کریں';

  @override
  String get metaRequestDeclined => 'درخواست مسترد کر دی گئی';

  @override
  String get metaRequestCancelled => 'درخواست منسوخ کر دی گئی';

  @override
  String get metaRequested => 'بھیج دی';

  @override
  String get metaFriendsLabel => 'دوست';

  @override
  String get metaNoFriendsTitle => 'ابھی کوئی دوست نہیں';

  @override
  String get metaNoFriendsMessage =>
      'ساتھ کھیلنے کے لیے اپنا کوڈ شیئر کریں یا کسی دوست کو شامل کریں۔';

  @override
  String get metaNoRequestsTitle => 'کوئی زیرِ التوا درخواست نہیں';

  @override
  String get metaNoRequestsMessage =>
      'آپ کی بھیجی اور موصول فرینڈ درخواستیں یہاں نظر آتی ہیں۔';

  @override
  String get metaRecentHint =>
      'پچھلے 14 دنوں میں آن لائن میچوں میں ملے کھلاڑی۔';

  @override
  String get metaNoRecentTitle => 'حال میں کوئی حریف نہیں';

  @override
  String get metaNoRecentMessage =>
      'کوئی آن لائن میچ کھیلیں — جن سے ملیں گے وہ یہاں نظر آئیں گے۔';

  @override
  String metaFriendRequestBanner(String name) {
    return '$name آپ کا دوست بننا چاہتے ہیں';
  }

  @override
  String get metaView => 'دیکھیں';

  @override
  String get metaErrorCannotFriendSelf => 'یہ آپ کا اپنا فرینڈ کوڈ ہے۔';

  @override
  String metaErrorFriendLimit(int max) {
    return 'آپ کے زیادہ سے زیادہ $max دوست ہو سکتے ہیں۔ کسی نئے کو شامل کرنے کے لیے ایک دوست ہٹائیں۔';
  }

  @override
  String get metaErrorUnknownFriendCode =>
      'اس فرینڈ کوڈ والا کوئی کھلاڑی نہیں ہے۔ جانچ کر دوبارہ کوشش کریں۔';

  @override
  String get metaErrorRequestInProgress =>
      'ابھی کارروائی جاری ہے — براہِ کرم تھوڑی دیر میں دوبارہ کوشش کریں۔';

  @override
  String get metaErrorMissionEnded =>
      'یہ مشن ختم ہو چکا ہے۔ موجودہ مشنز دیکھنے کے لیے نیچے کھینچیں۔';

  @override
  String get metaLeaderboardSubtitle =>
      'آپ اور آپ کے دوست، اس ہفتے کمائے گئے XP کے مطابق۔';

  @override
  String get metaLeaderboardTeaser =>
      'دیکھیں اس ہفتے آپ اور آپ کے دوست کیسا کر رہے ہیں۔';

  @override
  String metaWeeklyXp(String xp) {
    return '$xp XP';
  }

  @override
  String metaYouName(String name) {
    return '$name (آپ)';
  }

  @override
  String metaLeaderboardRowSemantics(int rank, String name, String xp) {
    return 'رینک $rank: $name، $xp';
  }

  @override
  String get metaLeaderboardAlone =>
      'موازنہ دیکھنے کے لیے دوست شامل کریں۔ دوستانہ مقابلہ، کوئی دباؤ نہیں۔';

  @override
  String numberLakh(String value) {
    return '$value لاکھ';
  }

  @override
  String numberCrore(String value) {
    return '$value کروڑ';
  }

  @override
  String get onboardingLanguageTitle => 'اپنی زبان منتخب کریں';

  @override
  String get onboardingLanguageSubtitle =>
      'آپ اسے کسی بھی وقت سیٹنگز میں بدل سکتے ہیں۔';

  @override
  String get onboardingPreviewLabel => 'جھلک';

  @override
  String get onboardingPreviewTitle => 'لوڈو رائل میں خوش آمدید!';

  @override
  String get onboardingPreviewBody =>
      'پانسہ پھینکیں، اپنی گوٹیاں گھر پہنچائیں اور تاج جیتیں۔';

  @override
  String playGameVariantTitle(String game, String variant) {
    return '$game · $variant';
  }

  @override
  String get playModeOnline => 'آن لائن';

  @override
  String get playModePrivate => 'پرائیویٹ روم';

  @override
  String get playModePractice => 'پریکٹس';

  @override
  String playSeatPlayer(int seat) {
    return 'کھلاڑی $seat';
  }

  @override
  String playNameYou(String name) {
    return '$name (آپ)';
  }

  @override
  String get playHome => 'ہوم';

  @override
  String get playBackHome => 'ہوم پر واپس جائیں';

  @override
  String get playTryAgain => 'دوبارہ کوشش کریں';

  @override
  String playEntryFee(String fee) {
    return 'انٹری $fee';
  }

  @override
  String playEntryFeeNote(String fee) {
    return 'انٹری فیس: ہر کھلاڑی سے $fee سکے، گیم شروع ہونے پر لیے جائیں گے۔ پورا پاٹ جیتنے والے کو ملے گا۔ بوٹ ہو تو مفت۔';
  }

  @override
  String get playNotEnoughCoinsTitle => 'کافی سکے نہیں';

  @override
  String playNotEnoughCoinsHint(String fee) {
    return 'کھیلنے کے لیے $fee سکے درکار ہیں۔ مشنز سے سکے کمائیں اور پھر آئیں!';
  }

  @override
  String get playSeatOpen => 'خالی سیٹ';

  @override
  String get playLoadingMatch => 'میچ میں شامل ہو رہے ہیں…';

  @override
  String get playMatchUnavailable => 'یہ میچ اب دستیاب نہیں ہے۔';

  @override
  String get playRoomClosed => 'روم بند کر دیا گیا۔';

  @override
  String get playRemovedFromRoom => 'آپ اب اس روم میں نہیں ہیں۔';

  @override
  String get playRoomUnavailable => 'یہ روم اب دستیاب نہیں ہے۔';

  @override
  String get playLoadingRoom => 'روم کھل رہا ہے…';

  @override
  String get playGameLabel => 'گیم';

  @override
  String get playModeLabel => 'قواعد';

  @override
  String get playPlayersLabel => 'کھلاڑی';

  @override
  String get playVariantClassicCaption => '4 گوٹیاں · 6 پر گھر سے باہر';

  @override
  String get playVariantQuickCaption => '2 گوٹیاں · 1 یا 6 پر گھر سے باہر';

  @override
  String get playMatchmakingTitle => 'کھلاڑی تلاش کر رہے ہیں';

  @override
  String get playMatchmakingConnecting => 'گیم سرور سے رابطہ ہو رہا ہے…';

  @override
  String get playMatchmakingJoining => 'قطار میں شامل ہو رہے ہیں…';

  @override
  String get playMatchmakingSearching => 'مخالفین تلاش کر رہے ہیں…';

  @override
  String get playMatchmakingStarting => 'ٹیبل بھر گئی! شروع ہو رہا ہے…';

  @override
  String get playMatchmakingStartsSoon =>
      'تمام سیٹیں بھرنے یا ٹائمر ختم ہونے پر میچ شروع ہوگا۔';

  @override
  String get playMatchmakingStartsWhenFull =>
      'تمام سیٹیں بھرتے ہی میچ شروع ہو جائے گا۔';

  @override
  String playMatchmakingPlayers(int count, int capacity) {
    return '$capacity میں سے $count کھلاڑی شامل ہوئے';
  }

  @override
  String get playMatchmakingCancel => 'تلاش منسوخ کریں';

  @override
  String get playMatchmakingFeeNote =>
      'انٹری فیس میچ شروع ہونے پر لی جاتی ہے۔ پورا پاٹ جیتنے والے کو ملتا ہے۔';

  @override
  String get playMatchmakingTimeoutTitle => 'ابھی کوئی مخالف نہیں';

  @override
  String get playMatchmakingTimeoutMessage =>
      'وقت پر کوئی شامل نہیں ہوا۔ دوبارہ کوشش کریں یا دوستوں کو پرائیویٹ روم میں بلائیں۔';

  @override
  String get playMatchmakingErrorTitle => 'میچ نہیں مل سکا';

  @override
  String get playCreateRoomTitle => 'پرائیویٹ روم بنائیں';

  @override
  String get playCreateRoomAction => 'روم بنائیں';

  @override
  String get playCreatingRoom => 'آپ کا روم بن رہا ہے…';

  @override
  String get playLobbyTitle => 'پرائیویٹ روم';

  @override
  String get playRoomCodeLabel => 'روم کوڈ';

  @override
  String playRoomCodeA11y(String letters) {
    return 'روم کوڈ $letters';
  }

  @override
  String get playCopyCode => 'کوڈ کاپی کریں';

  @override
  String get playCodeCopied => 'روم کوڈ کاپی ہو گیا';

  @override
  String get playShareInvite => 'دعوت شیئر کریں';

  @override
  String playInviteShareText(String game, String code) {
    return 'Ludo Royale پر میرے ساتھ $game کھیلو! ایپ کھولو، \'کوڈ سے شامل ہوں\' پر ٹیپ کرو اور یہ کوڈ ڈالو: $code';
  }

  @override
  String get playInviteShareSubject => 'Ludo Royale کی دعوت';

  @override
  String playLobbyPlayers(int count, int capacity) {
    return 'کھلاڑی $count/$capacity';
  }

  @override
  String get playLobbyStart => 'گیم شروع کریں';

  @override
  String get playLobbyWaitingForHost => 'ہوسٹ کے شروع کرنے کا انتظار…';

  @override
  String playLobbyWaitingForNamedHost(String name) {
    return '$name (ہوسٹ) کے شروع کرنے کا انتظار…';
  }

  @override
  String get playStartBlockedNeedPlayers =>
      'شروع کرنے کے لیے کم از کم 2 کھلاڑی چاہییں۔';

  @override
  String get playStartBlockedConnections => 'سب کے دوبارہ جڑنے کا انتظار۔';

  @override
  String get playStartBlockedBots => 'بوٹس اپنی سیٹیں سنبھال رہے ہیں…';

  @override
  String get playAllowBots => 'بوٹس کی اجازت دیں';

  @override
  String get playAllowBotsHint =>
      'خالی سیٹوں پر کمپیوٹر کھلاڑی بٹھائیں۔ بوٹس والے میچ مفت ہیں اور ان میں سکے نہیں ملتے۔';

  @override
  String get playAddBot => 'بوٹ شامل کریں';

  @override
  String get playBotJoining => 'بوٹ شامل ہو رہا ہے…';

  @override
  String playRemoveBotA11y(String name) {
    return '$name کو ہٹائیں';
  }

  @override
  String get playBotsFreeNote =>
      'ایک بوٹ بیٹھا ہے: یہ میچ مفت ہے اور اس میں سکے نہیں ملیں گے۔';

  @override
  String get playInviteFriends => 'دوستوں کو بلائیں';

  @override
  String get playInviteSheetTitle => 'دوستوں کو بلائیں';

  @override
  String get playInviteSend => 'بلائیں';

  @override
  String get playInviteSent => 'بلا لیا';

  @override
  String get playFriendOnline => 'آن لائن';

  @override
  String get playFriendOffline => 'آف لائن';

  @override
  String get playInviteEmptyTitle => 'ابھی کوئی دوست نہیں';

  @override
  String get playInviteEmptyMessage =>
      'اس کے بجائے روم کوڈ شیئر کریں، یا دوست اسکرین سے دوست شامل کریں۔';

  @override
  String get playInviteError => 'آپ کے دوست لوڈ نہیں ہو سکے۔';

  @override
  String get playLeaveRoom => 'روم چھوڑیں';

  @override
  String get playLeaveRoomTitle => 'یہ روم چھوڑیں؟';

  @override
  String get playLeaveRoomHostMessage =>
      'آپ ہوسٹ ہیں۔ آپ کے جانے پر اگلا کھلاڑی ہوسٹ بن جائے گا۔';

  @override
  String get playLeaveRoomMessage =>
      'روم کھلا رہنے تک آپ روم کوڈ سے واپس آ سکتے ہیں۔';

  @override
  String get playStay => 'رکیں';

  @override
  String get playHostBadge => 'ہوسٹ';

  @override
  String get playJoinTitle => 'کوڈ سے شامل ہوں';

  @override
  String get playJoinHint => 'دوست کا شیئر کیا ہوا 6 حروف کا روم کوڈ درج کریں۔';

  @override
  String playJoinCodeIncomplete(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining حروف مزید',
      one: '1 حرف مزید',
    );
    return '$_temp0';
  }

  @override
  String get playJoinInvalidChars =>
      'روم کوڈ میں A–Z حروف اور 2–9 اعداد ہوتے ہیں (I، O، 0 یا 1 نہیں)۔';

  @override
  String get playJoinLookingUp => 'روم تلاش کر رہے ہیں…';

  @override
  String get playJoinAction => 'روم میں شامل ہوں';

  @override
  String get playJoining => 'شامل ہو رہے ہیں…';

  @override
  String playJoinPreviewHost(String name) {
    return 'ہوسٹ: $name';
  }

  @override
  String playJoinPreviewPlayers(int count, int capacity) {
    return '$count/$capacity کھلاڑی';
  }

  @override
  String get playJoinStatusOpen => 'کھلا';

  @override
  String get playJoinStatusFull => 'بھرا ہوا';

  @override
  String get playJoinStatusInProgress => 'جاری ہے';

  @override
  String get playJoinStatusClosed => 'بند';

  @override
  String get playPaste => 'پیسٹ کریں';

  @override
  String get playPracticeTitle => 'بوٹس کے ساتھ پریکٹس';

  @override
  String get playPracticeBotsLabel => 'بوٹس';

  @override
  String playPracticeBotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بوٹس',
      one: '1 بوٹ',
    );
    return '$_temp0';
  }

  @override
  String get playPracticeStart => 'پریکٹس شروع کریں';

  @override
  String get playPracticeNote =>
      'پریکٹس مفت ہے اور اس میں سکے نہیں ملتے۔ آپ کمپیوٹر کھلاڑیوں کے خلاف کھیلتے ہیں۔';

  @override
  String get playPracticeSettingUp => 'آپ کی پریکٹس ٹیبل تیار ہو رہی ہے…';

  @override
  String playPracticeBotsJoining(int seated, int total) {
    return 'بوٹس شامل ہو رہے ہیں… $seated/$total';
  }

  @override
  String get playPracticeBotsUnavailableTitle => 'بوٹس ابھی مصروف ہیں';

  @override
  String get playPracticeErrorTitle => 'پریکٹس شروع نہیں ہو سکی';

  @override
  String get playLeave => 'میچ چھوڑیں';

  @override
  String get playTurnYourRoll => 'آپ کی باری — پانسہ دبائیں!';

  @override
  String get playTurnPickToken => 'چلانے کے لیے چمکتی گوٹی چنیں';

  @override
  String get playTurnYours => 'آپ کی باری';

  @override
  String playTurnOther(String name) {
    return '$name کی باری';
  }

  @override
  String get playVoidedThreeSixes => 'لگاتار تین چھکے! باری آگے چلی گئی۔';

  @override
  String playAutoPlayed(String name) {
    return 'وقت ختم — $name کی چال خودکار چلی گئی';
  }

  @override
  String playForfeitLeft(String name) {
    return '$name نے میچ چھوڑ دیا';
  }

  @override
  String playForfeitTimeouts(String name) {
    return '3 باریاں چھوٹنے پر $name کو ہٹا دیا گیا';
  }

  @override
  String get playPlayerDisconnected => 'آف لائن';

  @override
  String get playPlayerForfeited => 'چلا گیا';

  @override
  String get playPanelTurnA11y => 'ابھی ان کی باری';

  @override
  String playStrikesA11y(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count باریاں چھوٹیں',
      one: '1 باری چھوٹی',
    );
    return '$_temp0';
  }

  @override
  String playTokensHome(int home, int total) {
    return '$total میں سے $home گوٹیاں گھر پہنچیں';
  }

  @override
  String playSquare(int square) {
    return 'خانہ $square';
  }

  @override
  String get playAtStart => 'آغاز پر';

  @override
  String get playReconnecting => 'دوبارہ جڑ رہے ہیں… آپ کا میچ جاری ہے';

  @override
  String get playSyncing => 'بورڈ سنک ہو رہا ہے…';

  @override
  String get playLeaveMatchTitle => 'میچ چھوڑیں؟';

  @override
  String get playLeaveMatchMessage =>
      'چھوڑنے پر ہار مانی جائے گی اور آپ کی انٹری فیس واپس نہیں ملے گی۔';

  @override
  String get playLeavePracticeMessage => 'آپ کا پریکٹس گیم ختم ہو جائے گا۔';

  @override
  String get playLeaveMatchConfirm => 'چھوڑیں';

  @override
  String get playKeepPlaying => 'کھیلتے رہیں';

  @override
  String playRoundLabel(int round) {
    return 'راؤنڈ $round';
  }

  @override
  String get playStartingNextRound => 'اگلا راؤنڈ شروع ہو رہا ہے…';

  @override
  String get playChatOpen => 'فوری چیٹ';

  @override
  String get playChatTitle => 'فوری چیٹ';

  @override
  String get playChatEmotes => 'ایموٹس';

  @override
  String get playChatMuteOthers => 'دوسرے کھلاڑیوں کو میوٹ کریں';

  @override
  String get playChatMutedBySettings => 'ترتیبات میں فوری چیٹ میوٹ ہے۔';

  @override
  String playChatCooldown(int seconds) {
    return 'اگلا پیغام $seconds سیکنڈ میں';
  }

  @override
  String get playChatGg => 'اچھا کھیل!';

  @override
  String get playChatNiceMove => 'زبردست چال!';

  @override
  String get playChatWellPlayed => 'بہت خوب کھیلے!';

  @override
  String get playChatRematch => 'ایک اور میچ؟';

  @override
  String get playChatAgain => 'چلو پھر سے کھیلیں۔';

  @override
  String get playChatGoodLuck => 'نیک خواہشات!';

  @override
  String get playChatOops => 'اوہو!';

  @override
  String get playChatThanks => 'شکریہ!';

  @override
  String get playResultYouWon => 'آپ جیت گئے!';

  @override
  String playResultWinnerIs(String name) {
    return '$name کی جیت!';
  }

  @override
  String get playResultGameOver => 'کھیل ختم';

  @override
  String get playResultYouForfeited => 'آپ نے میچ چھوڑ دیا';

  @override
  String get playResultByForfeit =>
      'باقی کھلاڑیوں نے ہار مان لی — جیت آپ کی ہے۔';

  @override
  String get playResultWellPlayed => 'بہت عمدہ کھیلے!';

  @override
  String playResultYouFinished(int place) {
    return 'آپ #$place نمبر پر رہے';
  }

  @override
  String get playResultFinishingOrder => 'حتمی ترتیب';

  @override
  String playResultPlaceShort(int place) {
    return '$place';
  }

  @override
  String playResultPlaceA11y(int place) {
    return 'پوزیشن $place';
  }

  @override
  String get playRewardsTitle => 'انعامات';

  @override
  String playRewardCoins(String amount) {
    return '+$amount سکے';
  }

  @override
  String playRewardCoinsBalance(String amount) {
    return 'والٹ: $amount سکے';
  }

  @override
  String get playRewardNoCoinsMatch => 'اس میچ میں سکے نہیں ملتے۔';

  @override
  String get playRewardNoCoins =>
      'اس بار سکے نہیں — پورا پاٹ جیتنے والے کو ملتا ہے۔';

  @override
  String playRewardXp(int xp) {
    return '+$xp XP';
  }

  @override
  String get playRewardXpPending => 'XP کا حساب ہو رہا ہے…';

  @override
  String get playRewardXpLater => 'آپ کا XP جلد ہی پروفائل پر نظر آئے گا۔';

  @override
  String playRewardLevelUp(int level) {
    return 'لیول اپ! آپ لیول $level پر پہنچ گئے';
  }

  @override
  String get playRewardUnlocked => 'ان لاک ہوئے';

  @override
  String get playRematchTitle => 'دوبارہ مقابلہ';

  @override
  String get playRematchRequest => 'دوبارہ مقابلہ مانگیں';

  @override
  String get playRematchAccept => 'قبول کریں';

  @override
  String get playRematchDecline => 'انکار کریں';

  @override
  String playRematchIncoming(String name) {
    return '$name نے دوبارہ مقابلہ مانگا ہے!';
  }

  @override
  String get playRematchWaiting => 'آپ تیار ہیں! باقیوں کا انتظار…';

  @override
  String get playRematchYouDeclined => 'آپ نے دوبارہ مقابلے سے انکار کیا۔';

  @override
  String get playRematchClosed => 'دوبارہ مقابلہ اب دستیاب نہیں۔';

  @override
  String get playRematchPublicNote =>
      'قبول کرنے والے کھلاڑی ایک ساتھ نئے پرائیویٹ روم میں جائیں گے۔';

  @override
  String get playRematchStatusAccepted => 'تیار';

  @override
  String get playRematchStatusDeclined => 'انکار کیا';

  @override
  String get playRematchStatusPending => 'سوچ رہے ہیں…';

  @override
  String get playRematchStatusOut => 'چلے گئے';

  @override
  String playRematchSeatA11y(String name, String status) {
    return '$name: $status';
  }

  @override
  String get playPlayAgain => 'دوبارہ کھیلیں';

  @override
  String playInviteIncoming(String name, String game) {
    return '$name نے آپ کو $game کھیلنے کی دعوت دی ہے';
  }

  @override
  String get playInviteJoin => 'شامل ہوں';

  @override
  String get playInviteDismiss => 'ابھی نہیں';

  @override
  String get playInviteSomeone => 'ایک دوست';

  @override
  String get profileTitle => 'پروفائل';

  @override
  String get profileFriendCode => 'فرینڈ کوڈ';

  @override
  String get profileFriendCodeHint =>
      'اسے شیئر کریں تاکہ دوست آپ کو شامل کر سکیں۔';

  @override
  String profileShareFriendCode(String code) {
    return 'لوڈو رائل پر مجھے شامل کریں! میرا فرینڈ کوڈ ہے $code';
  }

  @override
  String profileLevelProgress(String xp, int level) {
    return 'لیول $level کے لیے $xp XP باقی';
  }

  @override
  String get profileMaxLevel => 'سب سے اونچا لیول حاصل';

  @override
  String get profileTitleLabel => 'ٹائٹل';

  @override
  String get profileAccountSection => 'اکاؤنٹ';

  @override
  String get profileAccountType => 'اکاؤنٹ کی قسم';

  @override
  String get profileAccountGuest => 'مہمان (محفوظ نہیں)';

  @override
  String get profileAccountLinked => 'محفوظ اکاؤنٹ';

  @override
  String get profileLinkedAccounts => 'سائن اِن کے طریقے';

  @override
  String get profileLinked => 'منسلک';

  @override
  String get profileNotLinked => 'منسلک نہیں';

  @override
  String get profileSaveProgressCta => 'پیش رفت محفوظ کریں';

  @override
  String get profileTotalXp => 'کل XP';

  @override
  String get profileStatsSection => 'پیش رفت';

  @override
  String get profileEditNameTooltip => 'نام بدلیں';

  @override
  String get profileEditNameTitle => 'اپنا نام بدلیں';

  @override
  String get profileNameLabel => 'ظاہری نام';

  @override
  String get profileNameRules =>
      '3 سے 16 حروف۔ حروف، اعداد، اسپیس، _ . اور - کی اجازت ہے۔';

  @override
  String get profileNameNote =>
      'دوستوں، لیڈر بورڈ اور نئے گیمز میں آپ کا نیا نام دکھے گا۔ جاری گیم میں پرانا نام ہی رہے گا۔';

  @override
  String profileNameCounterSemantics(int count, int max) {
    return '$max میں سے $count حروف';
  }

  @override
  String profileNameSaved(String name) {
    return 'اب آپ کا نام $name ہے';
  }

  @override
  String get profileNameChangeLimit =>
      'آپ نے بہت بار نام بدلا ہے۔ براہِ کرم بعد میں دوبارہ کوشش کریں۔';

  @override
  String profileNameChangeLimitRetry(String wait) {
    return 'آپ نے بہت بار نام بدلا ہے۔ $wait بعد دوبارہ کوشش کریں۔';
  }

  @override
  String get settingsTitle => 'سیٹنگز';

  @override
  String get settingsAppearance => 'ظاہری شکل';

  @override
  String get settingsTheme => 'تھیم';

  @override
  String get settingsThemeLight => 'لائٹ';

  @override
  String get settingsThemeDark => 'ڈارک';

  @override
  String get settingsThemeSystem => 'سسٹم';

  @override
  String get settingsLanguage => 'زبان';

  @override
  String get settingsSoundAndHaptics => 'آواز اور وائبریشن';

  @override
  String get settingsSound => 'ساؤنڈ ایفیکٹس';

  @override
  String get settingsHaptics => 'وائبریشن';

  @override
  String get settingsReducedMotion => 'کم حرکت';

  @override
  String get settingsReducedMotionSubtitle => 'کم اینیمیشنز اور ایفیکٹس';

  @override
  String get settingsReducedMotionSystemOn =>
      'آپ کے ڈیوائس کی سیٹنگز میں بھی آن ہے';

  @override
  String get settingsGameplay => 'گیم پلے';

  @override
  String get settingsQuickChatMute => 'فوری چیٹ میوٹ کریں';

  @override
  String get settingsQuickChatMuteSubtitle =>
      'دوسرے کھلاڑیوں کے چیٹ پیغامات اور ایموٹس چھپائیں';

  @override
  String get settingsPrivacy => 'پرائیویسی';

  @override
  String get settingsAnalytics => 'گمنام استعمال کے اعداد و شمار شیئر کریں';

  @override
  String get settingsAnalyticsSubtitle =>
      'اس سے ہمیں گیم بہتر بنانے میں مدد ملتی ہے۔ اس میں کبھی آپ کا نام، چیٹ یا روم کوڈ شامل نہیں ہوتے۔';

  @override
  String get settingsAnalyticsNotConfigured => 'اس بلڈ میں دستیاب نہیں';

  @override
  String get settingsAccount => 'اکاؤنٹ';

  @override
  String settingsSignedInAs(String name) {
    return 'بطور $name سائن اِن';
  }

  @override
  String get settingsSaveProgress => 'پیش رفت محفوظ کریں';

  @override
  String get settingsSaveProgressSubtitle =>
      'اپنی پیش رفت محفوظ رکھنے کے لیے سائن اِن کا طریقہ جوڑیں';

  @override
  String get settingsSwitchToGuest => 'مہمان اکاؤنٹ پر واپس جائیں';

  @override
  String get settingsSwitchToGuestSubtitle =>
      'اس ڈیوائس پر محفوظ مہمان اکاؤنٹ پر واپس جائیں';

  @override
  String get settingsSignOut => 'سائن آؤٹ';

  @override
  String get settingsAbout => 'ایپ کے بارے میں';

  @override
  String get settingsVersion => 'ورژن';

  @override
  String get settingsLegalNotices => 'قانونی نوٹس';

  @override
  String get settingsLegalNoticesSubtitle =>
      'اوپن سورس لائسنس · آپ کے براؤزر میں کھلے گا';

  @override
  String get settingsLegalNoticesOpenFailed =>
      'صفحہ نہیں کھل سکا۔ براہ کرم بعد میں دوبارہ کوشش کریں۔';

  @override
  String get settingsConsentTitle =>
      'لوڈو رائل کو بہتر بنانے میں ہماری مدد کریں';

  @override
  String get settingsConsentMessage =>
      'کیا ہم گمنام استعمال کے اعداد و شمار جمع کر سکتے ہیں، جیسے کون سے گیم موڈ مقبول ہیں؟ ہم کبھی آپ کا نام، چیٹ، روم کوڈ یا رابطے کی تفصیلات جمع نہیں کرتے۔ آپ اسے کسی بھی وقت سیٹنگز میں بدل سکتے ہیں۔';

  @override
  String get settingsConsentAllow => 'گمنام اعداد و شمار شیئر کریں';

  @override
  String get settingsConsentDeny => 'نہیں، شکریہ';

  @override
  String get socialPodOptionsHint => 'کھلاڑی کے اختیارات دیکھیں';

  @override
  String get socialRequestSent => 'درخواست بھیج دی گئی';

  @override
  String get socialAcceptRequest => 'درخواست قبول کریں';

  @override
  String get socialReportPlayer => 'کھلاڑی کی رپورٹ کریں';

  @override
  String get socialReported => 'رپورٹ کی گئی';

  @override
  String get socialAlreadyReported =>
      'آپ نے پچھلے 24 گھنٹوں میں اس کھلاڑی کی رپورٹ کی ہے۔';

  @override
  String socialReportsLeft(int remaining, int total) {
    return 'آج باقی رپورٹس: $total میں سے $remaining';
  }

  @override
  String socialReportLimitAt(int total, String time) {
    return 'آپ نے آج کی $total رپورٹس استعمال کر لی ہیں۔ آپ $time پر دوبارہ رپورٹ کر سکتے ہیں۔';
  }

  @override
  String socialReportLimitLater(int total) {
    return 'آپ نے آج کی $total رپورٹس استعمال کر لی ہیں۔ بعد میں دوبارہ کوشش کریں۔';
  }

  @override
  String socialReportTitle(String name) {
    return '$name کی رپورٹ کریں';
  }

  @override
  String get socialReportWhy => 'کیا ہوا؟';

  @override
  String get socialReasonCheating => 'دھوکا دہی';

  @override
  String get socialReasonOffensiveName => 'نامناسب نام';

  @override
  String get socialReasonAbusiveBehavior => 'بدسلوکی';

  @override
  String get socialReasonLeavingOrStalling =>
      'گیم چھوڑنا یا جان بوجھ کر دیر کرنا';

  @override
  String get socialReasonOther => 'کچھ اور';

  @override
  String get socialReportReviewNote =>
      'ہماری ٹیم ہر رپورٹ کا جائزہ لیتی ہے۔ اس کی صورتحال دوستوں کی اسکرین کے رپورٹ ٹیب میں دیکھیں۔';

  @override
  String get socialSendReport => 'رپورٹ بھیجیں';

  @override
  String socialReportSent(int remaining, int total) {
    return 'رپورٹ بھیج دی گئی۔ آج $total میں سے $remaining رپورٹس باقی ہیں۔';
  }

  @override
  String socialFriendLimitNote(int max) {
    return 'آپ کے زیادہ سے زیادہ $max دوست ہو سکتے ہیں — نیا شامل کرنے کے لیے کسی ایک کو ہٹائیں۔';
  }

  @override
  String get socialErrorCannotReportSelf => 'آپ اپنی رپورٹ نہیں کر سکتے۔';

  @override
  String get socialErrorCannotReportBot =>
      'اس کھلاڑی کی رپورٹ نہیں کی جا سکتی۔';

  @override
  String get socialErrorNotInRoom =>
      'آپ صرف اسی میچ کے کھلاڑیوں کی رپورٹ کر سکتے ہیں جس میں آپ ہیں۔';

  @override
  String get socialErrorRoomNotFound =>
      'یہ میچ اب نہیں مل رہا، اس لیے رپورٹ نہیں بھیجی جا سکی۔';

  @override
  String get socialErrorPlayerNotFound => 'یہ کھلاڑی نہیں ملا۔';

  @override
  String get socialTabReported => 'رپورٹ کی گئی';

  @override
  String socialOnlineNow(int count) {
    return 'ابھی آن لائن ($count)';
  }

  @override
  String socialOfflineCount(int count) {
    return 'آف لائن ($count)';
  }

  @override
  String socialFriendsCount(int count, int max) {
    return 'دوست $count/$max';
  }

  @override
  String socialReportsResetAt(String time) {
    return 'آپ $time پر دوبارہ رپورٹ کر سکتے ہیں۔';
  }

  @override
  String socialReportsInfo(int total) {
    return 'آپ ایک دن میں زیادہ سے زیادہ $total کھلاڑیوں کی رپورٹ کر سکتے ہیں۔ ہماری ٹیم ہر رپورٹ کا جائزہ لیتی ہے۔';
  }

  @override
  String get socialNoReportsTitle => 'کوئی رپورٹ نہیں';

  @override
  String get socialNoReportsMessage =>
      'میچ سے جن کھلاڑیوں کی آپ رپورٹ کریں گے، وہ یہاں ہر رپورٹ کی صورتحال کے ساتھ نظر آئیں گے۔';

  @override
  String get socialStatusSubmitted => 'بھیجی گئی';

  @override
  String get socialStatusReviewing => 'زیرِ جائزہ';

  @override
  String get socialStatusActionTaken => 'کارروائی ہوئی';

  @override
  String get socialStatusDismissed => 'مسترد';

  @override
  String get socialJustNow => 'ابھی ابھی';

  @override
  String socialMinutesAgo(int minutes) {
    return '$minutes منٹ پہلے';
  }

  @override
  String socialHoursAgo(int hours) {
    return '$hours گھنٹے پہلے';
  }

  @override
  String get socialYesterday => 'کل';

  @override
  String socialReportStatusA11y(String status) {
    return 'صورتحال: $status';
  }

  @override
  String get walletTitle => 'آپ کا والٹ';

  @override
  String get walletCoinsCaption =>
      'میچ کی انٹری فیس کے لیے — جیتنے والے کو پورا پاٹ ملتا ہے۔';

  @override
  String get walletDiamondsCaption => 'کلیکشن روم میں پریمیم کاسمیٹکس کے لیے۔';

  @override
  String walletExactBalance(String amount) {
    return 'درست بیلنس: $amount';
  }

  @override
  String get walletVirtualTitle => 'ورچوئل کرنسی';

  @override
  String get walletVirtualNotice =>
      'سکے اور ہیرے صرف تفریح کے لیے ورچوئل آئٹمز ہیں۔ ان کی کوئی حقیقی قیمت نہیں اور انہیں بیچا، منتقل، نکالا یا رقم میں تبدیل نہیں کیا جا سکتا۔';

  @override
  String get walletEarnTitle => 'مزید کیسے کمائیں';

  @override
  String get walletEarnWins => 'میچ جیتیں اور پاٹ حاصل کریں';

  @override
  String get walletEarnMissions => 'روزانہ اور ہفتہ وار مشن مکمل کریں';

  @override
  String get walletEarnLevels => 'لیول بڑھائیں اور سنگ میل انعامات پائیں';

  @override
  String get walletRefresh => 'بیلنس ریفریش کریں';

  @override
  String widgetsCoinsBalance(String amount) {
    return 'سکے: $amount';
  }

  @override
  String widgetsDiamondsBalance(String amount) {
    return 'ہیرے: $amount';
  }

  @override
  String widgetsXpLabel(String current, String total) {
    return 'تجربہ: $total میں سے $current';
  }

  @override
  String get widgetsAvatarLabel => 'کھلاڑی کا اوتار';

  @override
  String widgetsTitleLabel(String title) {
    return 'خطاب: $title';
  }

  @override
  String widgetsEmoteLabel(String name) {
    return 'ایموٹ: $name';
  }

  @override
  String widgetsBadgeLabel(String name) {
    return 'بیج: $name';
  }

  @override
  String widgetsSecondsLeft(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds سیکنڈ باقی',
      one: '1 سیکنڈ باقی',
    );
    return '$_temp0';
  }

  @override
  String widgetsConnectionLabel(String status) {
    return 'کنکشن: $status';
  }

  @override
  String widgetsNewItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نئے',
      one: '1 نیا',
    );
    return '$_temp0';
  }

  @override
  String get widgetsSelected => 'منتخب';

  @override
  String widgetsLogoLabel(String appName) {
    return '$appName کا شاہی نشان';
  }
}
