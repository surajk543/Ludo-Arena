// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get authWelcomeTitle => 'बोर्ड पर राज करने को तैयार?';

  @override
  String get authWelcomeSubtitle =>
      'दोस्तों और दुनिया भर के खिलाड़ियों के साथ लूडो और साँप-सीढ़ी खेलें।';

  @override
  String get authContinueWithGoogle => 'Google के साथ जारी रखें';

  @override
  String get authContinueWithFacebook => 'Facebook के साथ जारी रखें';

  @override
  String get authContinueWithApple => 'Apple से साइन इन करें';

  @override
  String get authPlayAsGuest => 'मेहमान के रूप में खेलें';

  @override
  String get authGuestHint =>
      'तुरंत शुरू करें — आप कभी भी अपनी प्रोग्रेस सेव कर सकते हैं।';

  @override
  String get authOrDivider => 'या';

  @override
  String get authFairPlayNote =>
      'सिक्के और हीरे वर्चुअल हैं और असली पैसों में नहीं बदले जा सकते।';

  @override
  String get authSessionExpiredBanner =>
      'आप साइन आउट हो गए थे। कृपया फिर से साइन इन करें।';

  @override
  String get authSignedInElsewhereTitle =>
      'किसी दूसरे डिवाइस पर साइन इन किया गया';

  @override
  String get authSignedInElsewhereMessage =>
      'किसी ने आपके अकाउंट से दूसरे डिवाइस पर साइन इन किया है, इसलिए आपको यहाँ से साइन आउट कर दिया गया है। एक समय में केवल एक डिवाइस पर साइन इन किया जा सकता है। यहाँ खेलने के लिए फिर से साइन इन करें — दूसरा डिवाइस साइन आउट हो जाएगा।';

  @override
  String get authSignedInElsewhereBanner =>
      'आपके अकाउंट से किसी दूसरे डिवाइस पर साइन इन किया गया।';

  @override
  String get authChangeLanguage => 'भाषा बदलें';

  @override
  String get authProviderGoogle => 'Google';

  @override
  String get authProviderFacebook => 'Facebook';

  @override
  String get authProviderApple => 'Apple';

  @override
  String get authProviderGuest => 'मेहमान';

  @override
  String get authSaveProgressTitle => 'अपनी प्रोग्रेस सेव करें';

  @override
  String get authSaveProgressSubtitle =>
      'कोई साइन-इन तरीका जोड़ें ताकि आपके सिक्के, लेवल और कलेक्शन कभी न खोएँ — नए फ़ोन पर भी।';

  @override
  String get authSaveBenefitKeep => 'अपने सारे सिक्के, XP और कॉस्मेटिक्स रखें';

  @override
  String get authSaveBenefitDevices => 'किसी भी डिवाइस पर साइन इन करें';

  @override
  String get authSaveBenefitSame =>
      'वही अकाउंट — कुछ भी रीसेट या ट्रांसफ़र नहीं होता';

  @override
  String get authSaveWithGoogle => 'Google से सेव करें';

  @override
  String get authSaveWithFacebook => 'Facebook से सेव करें';

  @override
  String get authSaveWithApple => 'Apple से सेव करें';

  @override
  String get authSaveNoProviders =>
      'इस बिल्ड में कोई साइन-इन तरीका उपलब्ध नहीं है।';

  @override
  String get authLinkSuccessTitle => 'प्रोग्रेस सेव हो गई!';

  @override
  String authLinkSuccessMessage(String provider) {
    return 'आपका अकाउंट अब $provider से जुड़ गया है। किसी भी डिवाइस पर $provider से साइन इन करके खेल जारी रखें।';
  }

  @override
  String get authAlreadySavedTitle => 'आपकी प्रोग्रेस सेव है';

  @override
  String get authAlreadySavedMessage =>
      'यह अकाउंट एक साइन-इन तरीके से जुड़ा है, इसलिए आपकी प्रोग्रेस सुरक्षित है।';

  @override
  String authConflictTitle(String provider) {
    return 'यह $provider अकाउंट पहले से इस्तेमाल में है';
  }

  @override
  String authConflictMessage(String provider) {
    return 'उस $provider अकाउंट का अपना अलग लूडो रॉयल अकाउंट पहले से है। दोनों अकाउंट के बीच कुछ भी मर्ज या ट्रांसफ़र नहीं होगा।';
  }

  @override
  String get authConflictSignIn => 'उस अकाउंट में साइन इन करें';

  @override
  String get authConflictGuestNote =>
      'आपका मेहमान अकाउंट इसी डिवाइस पर रहेगा — आप सेटिंग्स से उस पर वापस जा सकते हैं।';

  @override
  String get authAlreadyLinkedTitle => 'पहले से जुड़ा है';

  @override
  String authAlreadyLinkedMessage(String provider) {
    return 'यह अकाउंट पहले से किसी दूसरे $provider अकाउंट से जुड़ा है।';
  }

  @override
  String get authLogoutTitle => 'साइन आउट करें?';

  @override
  String get authLogoutMessage =>
      'आप कभी भी उसी तरीके से फिर से साइन इन कर सकते हैं।';

  @override
  String get authLogoutConfirm => 'साइन आउट करें';

  @override
  String get authGuestLogoutTitle => 'मेहमान अकाउंट से साइन आउट करें?';

  @override
  String get authGuestLogoutMessage =>
      'आप मेहमान के रूप में खेल रहे हैं। अगर आप अभी साइन आउट करते हैं, तो पहले प्रोग्रेस सेव किए बिना आपके सिक्के, लेवल और कलेक्शन खो जाएँगे।';

  @override
  String get authGuestLogoutConfirm => 'साइन आउट करें और प्रोग्रेस खोएँ';

  @override
  String get authSaveProgressFirst => 'पहले प्रोग्रेस सेव करें';

  @override
  String get authSwitchToGuestTitle => 'मेहमान अकाउंट पर वापस जाएँ?';

  @override
  String get authSwitchToGuestMessage =>
      'आप इस अकाउंट से बाहर निकलकर इस डिवाइस पर सेव मेहमान अकाउंट से खेलना जारी रखेंगे।';

  @override
  String get authSwitchToGuestConfirm => 'मेहमान पर जाएँ';

  @override
  String get authGuestUnavailable => 'वह मेहमान अकाउंट अब उपलब्ध नहीं है।';

  @override
  String authWelcomeBack(String name) {
    return 'स्वागत है, $name!';
  }

  @override
  String get boardsColorRed => 'लाल';

  @override
  String get boardsColorGreen => 'हरी';

  @override
  String get boardsColorYellow => 'पीली';

  @override
  String get boardsColorBlue => 'नीली';

  @override
  String get boardsLudoBoardLabel => 'लूडो बोर्ड';

  @override
  String get boardsSnakesBoardLabel => 'साँप-सीढ़ी बोर्ड';

  @override
  String boardsTokenInBase(String color, int number) {
    return '$color गोटी $number, शुरुआती घर में';
  }

  @override
  String boardsTokenStepsFromHome(String color, int number, int steps) {
    String _temp0 = intl.Intl.pluralLogic(
      steps,
      locale: localeName,
      other: 'मंज़िल से $steps खाने दूर',
      one: 'मंज़िल से 1 खाना दूर',
    );
    return '$color गोटी $number, $_temp0';
  }

  @override
  String boardsTokenHome(String color, int number) {
    return '$color गोटी $number, मंज़िल पर पहुँच गई';
  }

  @override
  String get boardsTokenCanMove => 'चल सकती है';

  @override
  String get boardsTokenMoveHint => 'यह गोटी चलें';

  @override
  String get boardsCurrentTurn => 'अभी इसकी बारी है';

  @override
  String boardsSnakesTokenOnSquare(String color, int square) {
    return '$color गोटी खाना $square पर';
  }

  @override
  String boardsSnakesTokenAtStart(String color) {
    return '$color गोटी शुरुआत में';
  }

  @override
  String boardsDiceShowing(int value) {
    return 'पासे पर $value है';
  }

  @override
  String get boardsDiceRolling => 'पासा घूम रहा है';

  @override
  String get boardsDiceRollHint => 'पासा फेंकें';

  @override
  String get boardsVictoryCelebration => 'जीत का जश्न';

  @override
  String get boardsLevelUp => 'लेवल बढ़ गया';

  @override
  String get commonOk => 'ठीक है';

  @override
  String get commonCancel => 'रद्द करें';

  @override
  String get commonRetry => 'फिर कोशिश करें';

  @override
  String get commonClose => 'बंद करें';

  @override
  String get commonContinue => 'आगे बढ़ें';

  @override
  String get commonBack => 'वापस';

  @override
  String get commonDone => 'हो गया';

  @override
  String get commonSave => 'सेव करें';

  @override
  String get commonLater => 'बाद में';

  @override
  String get commonLoading => 'लोड हो रहा है…';

  @override
  String get commonCopy => 'कॉपी करें';

  @override
  String get commonCopied => 'कॉपी हो गया!';

  @override
  String get commonShare => 'शेयर करें';

  @override
  String get commonYes => 'हाँ';

  @override
  String get commonNo => 'नहीं';

  @override
  String get commonSomethingWentWrong => 'कुछ गड़बड़ हो गई।';

  @override
  String get commonNothingHereYet => 'यहाँ अभी कुछ नहीं है';

  @override
  String get commonYou => 'आप';

  @override
  String get commonGuest => 'मेहमान';

  @override
  String get commonCoins => 'सिक्के';

  @override
  String get commonDiamonds => 'हीरे';

  @override
  String commonLevel(int level) {
    return 'लेवल $level';
  }

  @override
  String commonLevelShort(int level) {
    return 'लेवल $level';
  }

  @override
  String commonXpProgress(String current, String total) {
    return '$current / $total XP';
  }

  @override
  String get commonConnectionConnected => 'ऑनलाइन';

  @override
  String get commonConnectionConnecting => 'कनेक्ट हो रहा है…';

  @override
  String get commonConnectionReconnecting => 'फिर से कनेक्ट हो रहा है…';

  @override
  String get commonConnectionOffline => 'ऑफ़लाइन';

  @override
  String get commonConnectionReplaced => 'यह गेम कहीं और खुला है';

  @override
  String get commonReconnect => 'फिर से कनेक्ट करें';

  @override
  String commonSecondsShort(int seconds) {
    return '$seconds से.';
  }

  @override
  String get commonGameLudo => 'लूडो';

  @override
  String get commonGameSnakesLadders => 'साँप-सीढ़ी';

  @override
  String get commonVariantClassic => 'क्लासिक';

  @override
  String get commonVariantQuick => 'क्विक';

  @override
  String commonPlayerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count खिलाड़ी',
      one: '1 खिलाड़ी',
    );
    return '$_temp0';
  }

  @override
  String get commonOfflineHint =>
      'आप ऑफ़लाइन हैं। अपना कनेक्शन जाँचें और फिर कोशिश करें।';

  @override
  String commonEntryFee(String amount) {
    return 'एंट्री $amount';
  }

  @override
  String get commonFree => 'मुफ़्त';

  @override
  String get appTitle => 'लूडो रॉयल';

  @override
  String get languageNameNative => 'हिन्दी';

  @override
  String get cosmeticDiceClassic => 'क्लासिक आइवरी';

  @override
  String get cosmeticDiceNeon => 'नियॉन पल्स';

  @override
  String get cosmeticDiceGolden => 'शाही सोना';

  @override
  String get cosmeticDiceAutumn => 'पतझड़ का पत्ता';

  @override
  String get cosmeticTokenClassic => 'क्लासिक गोटी';

  @override
  String get cosmeticTokenGem => 'रत्न';

  @override
  String get cosmeticTokenRoyal => 'शाही गोटी';

  @override
  String get cosmeticTokenCrown => 'ताज वाली गोटी';

  @override
  String get cosmeticLudoBoardClassic => 'क्लासिक';

  @override
  String get cosmeticLudoBoardMidnight => 'आधी रात का संगमरमर';

  @override
  String get cosmeticLudoBoardRoyal => 'शाही दरबार';

  @override
  String get cosmeticSnakesBoardClassic => 'क्लासिक मैदान';

  @override
  String get cosmeticSnakesBoardJungle => 'जंगल का मंदिर';

  @override
  String get cosmeticSnakesBoardCandy => 'कैंडी लैंड';

  @override
  String get cosmeticTrailNone => 'कोई ट्रेल नहीं';

  @override
  String get cosmeticTrailSparkle => 'चमक';

  @override
  String get cosmeticTrailComet => 'धूमकेतु';

  @override
  String get cosmeticVictoryConfetti => 'कंफ़ेटी';

  @override
  String get cosmeticVictoryFireworks => 'आतिशबाज़ी';

  @override
  String get cosmeticVictoryCrown => 'सुनहरा ताज';

  @override
  String get cosmeticFrameNone => 'कोई फ़्रेम नहीं';

  @override
  String get cosmeticFrameBronze => 'कांसे की अंगूठी';

  @override
  String get cosmeticFrameSilver => 'चाँदी की विजय माला';

  @override
  String get cosmeticFrameGold => 'सोने की विजय माला';

  @override
  String get cosmeticFrameRoyal => 'शाही चिह्न';

  @override
  String get cosmeticTitleRookie => 'नौसिखिया';

  @override
  String get cosmeticTitleStrategist => 'रणनीतिकार';

  @override
  String get cosmeticTitleDiceMaster => 'पासा उस्ताद';

  @override
  String get cosmeticTitleRoyal => 'महामहिम';

  @override
  String get cosmeticTitleWeeklyChampion => 'साप्ताहिक चैंपियन';

  @override
  String get cosmeticBadgeFirstWin => 'पहली जीत';

  @override
  String get cosmeticBadgeFriendly => 'अच्छी संगत';

  @override
  String get cosmeticEmoteWave => 'हाथ हिलाना';

  @override
  String get cosmeticEmoteThumbs => 'शाबाश';

  @override
  String get cosmeticEmoteLaugh => 'हँसी';

  @override
  String get cosmeticEmoteWow => 'वाह';

  @override
  String get cosmeticEmoteCrown => 'ताज';

  @override
  String get cosmeticRarityCommon => 'साधारण';

  @override
  String get cosmeticRarityRare => 'दुर्लभ';

  @override
  String get cosmeticRarityEpic => 'एपिक';

  @override
  String get cosmeticRarityLegendary => 'लेजेंडरी';

  @override
  String get cosmeticKindDice => 'पासा';

  @override
  String get cosmeticKindToken => 'गोटियाँ';

  @override
  String get cosmeticKindLudoBoard => 'लूडो बोर्ड';

  @override
  String get cosmeticKindSnakesBoard => 'साँप-सीढ़ी बोर्ड';

  @override
  String get cosmeticKindFrame => 'अवतार फ़्रेम';

  @override
  String get cosmeticKindTitle => 'उपाधि';

  @override
  String get cosmeticKindBadge => 'बैज';

  @override
  String get cosmeticKindEmote => 'इमोट';

  @override
  String get cosmeticKindVictory => 'जीत का जश्न';

  @override
  String get cosmeticKindTrail => 'गोटी की ट्रेल';

  @override
  String get errorGeneric => 'कुछ गड़बड़ हो गई। कृपया फिर कोशिश करें।';

  @override
  String get errorBadRequest => 'यह अनुरोध पूरा नहीं हो सका।';

  @override
  String get errorUnknownType =>
      'यह सुविधा उपलब्ध नहीं है। कृपया ऐप अपडेट करें।';

  @override
  String get errorRateLimited => 'थोड़ा धीरे! कुछ पल रुककर फिर कोशिश करें।';

  @override
  String get errorUnauthorized =>
      'आपका सेशन खत्म हो गया है। कृपया फिर से साइन इन करें।';

  @override
  String get errorUpdateRequired => 'ऐप का नया वर्शन ज़रूरी है।';

  @override
  String get errorMaintenance =>
      'गेम सर्वर पर मेंटेनेंस चल रहा है। थोड़ी देर बाद फिर कोशिश करें।';

  @override
  String get errorNotInRoom => 'अब आप इस रूम में नहीं हैं।';

  @override
  String get errorRoomNotFound => 'यह रूम अब मौजूद नहीं है।';

  @override
  String get errorRoomFull => 'यह रूम पहले से भरा हुआ है।';

  @override
  String get errorRoomInProgress => 'यह गेम पहले ही शुरू हो चुका है।';

  @override
  String get errorRoomClosed => 'यह रूम बंद हो गया है।';

  @override
  String get errorAlreadyInRoom =>
      'आप पहले से एक रूम में हैं। दूसरे में जाने के लिए पहले उसे छोड़ें।';

  @override
  String get errorNotHost => 'यह सिर्फ़ होस्ट कर सकता है।';

  @override
  String get errorNotEnoughPlayers =>
      'शुरू करने के लिए कम से कम 2 खिलाड़ी चाहिए।';

  @override
  String get errorPlayersNotReady =>
      'सभी खिलाड़ियों के तैयार होने का इंतज़ार है।';

  @override
  String get errorNotYourTurn => 'अभी आपकी बारी नहीं है।';

  @override
  String get errorInvalidPhase => 'अभी यह नहीं कर सकते।';

  @override
  String get errorIllegalMove => 'यह चाल मान्य नहीं है।';

  @override
  String get errorStaleState => 'बोर्ड अभी बदला है। फिर से कोशिश करें।';

  @override
  String get errorInsufficientFunds =>
      'इसके लिए आपके पास पर्याप्त सिक्के नहीं हैं।';

  @override
  String get errorInvalidCode =>
      'यह रूम कोड सही नहीं है। जाँचकर फिर कोशिश करें।';

  @override
  String get errorRematchClosed => 'रीमैच का समय खत्म हो गया।';

  @override
  String get errorNotFriends => 'आप सिर्फ़ दोस्तों को बुला सकते हैं।';

  @override
  String get errorItemNotOwned => 'यह आइटम अभी आपके पास नहीं है।';

  @override
  String get errorBotsUnavailable =>
      'अभी कोई कंप्यूटर खिलाड़ी उपलब्ध नहीं है। थोड़ी देर में फिर कोशिश करें।';

  @override
  String get errorBotsNotAllowed =>
      'इस रूम में कंप्यूटर खिलाड़ियों की अनुमति नहीं है।';

  @override
  String get errorInternal =>
      'हमारी तरफ़ से कुछ गड़बड़ हुई। कृपया फिर कोशिश करें।';

  @override
  String get errorClientVersionRequired =>
      'ऐप अपना वर्शन नहीं पहचान पाया। कृपया ऐप अपडेट या दोबारा इंस्टॉल करें।';

  @override
  String get errorEnvironmentMismatch => 'यह ऐप बिल्ड गलत सर्वर से जुड़ा है।';

  @override
  String get errorInvalidCredential =>
      'साइन इन नहीं हो सका। कृपया फिर कोशिश करें।';

  @override
  String get errorRefreshReused =>
      'आपकी सुरक्षा के लिए आपको साइन आउट कर दिया गया है। कृपया फिर से साइन इन करें।';

  @override
  String get errorSessionReplaced =>
      'आपके अकाउंट से किसी दूसरे डिवाइस पर साइन इन किया गया। कृपया फिर से साइन इन करें।';

  @override
  String get errorForbidden => 'आपको यह करने की अनुमति नहीं है।';

  @override
  String get errorNotFound => 'जो आप ढूँढ रहे थे, वह नहीं मिला।';

  @override
  String get errorIdentityConflict =>
      'यह साइन-इन अकाउंट पहले से किसी दूसरी प्लेयर प्रोफ़ाइल का है।';

  @override
  String get errorProviderAlreadyLinked =>
      'आपकी प्रोफ़ाइल से इस तरह का एक दूसरा अकाउंट पहले से जुड़ा है।';

  @override
  String get errorAlreadyOwned => 'यह आइटम पहले से आपके पास है।';

  @override
  String get errorAlreadyClaimed => 'आप यह इनाम पहले ही ले चुके हैं।';

  @override
  String get errorAlreadyFriends => 'आप पहले से दोस्त हैं।';

  @override
  String get errorNotCompleted => 'इनाम लेने के लिए पहले यह मिशन पूरा करें।';

  @override
  String get errorItemLocked => 'यह आइटम अभी लॉक है।';

  @override
  String get errorProviderUnavailable =>
      'साइन-इन सेवा अभी उपलब्ध नहीं है। कृपया बाद में कोशिश करें।';

  @override
  String get errorNetwork =>
      'गेम सर्विस से कनेक्ट नहीं हो पा रहा। अपना इंटरनेट कनेक्शन जाँचें।';

  @override
  String get errorTimeout => 'कनेक्शन टाइम आउट हो गया। कृपया फिर कोशिश करें।';

  @override
  String get errorBadResponse =>
      'सर्वर से अनपेक्षित जवाब मिला। कृपया फिर कोशिश करें।';

  @override
  String get errorCancelled => 'रद्द किया गया।';

  @override
  String get errorNotConnected =>
      'अभी आप कनेक्ट नहीं हैं। फिर से कनेक्ट हो रहा है…';

  @override
  String errorRateLimitedRetry(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'बहुत ज़्यादा कोशिशें। $seconds सेकंड बाद फिर कोशिश करें।',
      one: 'बहुत ज़्यादा कोशिशें। 1 सेकंड बाद फिर कोशिश करें।',
    );
    return '$_temp0';
  }

  @override
  String get errorInvalidName =>
      'यह नाम इस्तेमाल नहीं किया जा सकता। कृपया कोई दूसरा नाम चुनें।';

  @override
  String get errorInvalidNameTooShort => 'नाम में कम से कम 3 अक्षर होने चाहिए।';

  @override
  String get errorInvalidNameTooLong =>
      'नाम में ज़्यादा से ज़्यादा 16 अक्षर हो सकते हैं।';

  @override
  String get errorInvalidNameCharacters =>
      'सिर्फ़ अक्षर, अंक, स्पेस, _ . या - इस्तेमाल करें (कम से कम एक अक्षर)। इमोजी या चिह्न नहीं।';

  @override
  String get errorInvalidNameReserved =>
      'यह नाम आरक्षित है। कृपया कोई दूसरा नाम चुनें।';

  @override
  String get errorInvalidNameInappropriate =>
      'इस नाम की अनुमति नहीं है। कृपया कोई अच्छा-सा नाम चुनें।';

  @override
  String get gateSplashTagline => 'पासा फेंको। दौड़ लगाओ। राज करो।';

  @override
  String get gateStatusChecking => 'गेम सर्वर जाँचे जा रहे हैं…';

  @override
  String get gateStatusSigningIn => 'आपको साइन इन किया जा रहा है…';

  @override
  String get gateStatusLoadingProfile => 'आपकी प्रोफ़ाइल लोड हो रही है…';

  @override
  String get gateUpdateNow => 'अभी अपडेट करें';

  @override
  String get gateForceUpdateTitle => 'अपडेट ज़रूरी है';

  @override
  String get gateForceUpdateMessage =>
      'लूडो रॉयल का यह वर्ज़न अब सपोर्ट नहीं होता। ऑनलाइन खेलते रहने के लिए अपडेट करें — आपके सिक्के और प्रोग्रेस सुरक्षित हैं।';

  @override
  String get gateInstalledVersion => 'इंस्टॉल वर्ज़न';

  @override
  String get gateRequiredVersion => 'ज़रूरी वर्ज़न';

  @override
  String get gateStoreNotReadyTitle => 'अपडेट अभी स्टोर में उपलब्ध नहीं है';

  @override
  String get gateStoreNotReadyMessage =>
      'नया वर्ज़न जल्द ही आपके ऐप स्टोर में आ रहा है। थोड़ी देर बाद फिर से जाँचें।';

  @override
  String get gateCheckAgain => 'फिर से जाँचें';

  @override
  String get gateOptionalUpdateTitle => 'नया वर्ज़न उपलब्ध है';

  @override
  String gateOptionalUpdateMessage(String version) {
    return 'वर्ज़न $version में सुधार और बेहतरियाँ हैं। सबसे स्मूद गेम के लिए अभी अपडेट करें।';
  }

  @override
  String get gateMaintenanceTitle => 'हम बोर्ड चमका रहे हैं';

  @override
  String get gateMaintenanceMessage =>
      'लूडो रॉयल पर मेंटेनेंस चल रहा है। आपके सिक्के, प्रोग्रेस और चल रहे मैच सुरक्षित हैं — हमारे लौटते ही मैच फिर से शुरू होंगे।';

  @override
  String gateMaintenanceEstimatedEnd(String time) {
    return 'अनुमानित समाप्ति: $time';
  }

  @override
  String get gateMaintenanceEstimateNote =>
      'यह सिर्फ़ एक अनुमान है और बदल सकता है।';

  @override
  String get gateMaintenanceAutoCheck =>
      'हम हर 30 सेकंड में अपने-आप फिर से जाँचेंगे।';

  @override
  String gateLastChecked(String time) {
    return 'आख़िरी बार $time पर जाँचा गया';
  }

  @override
  String get gateCheckingNow => 'जाँच हो रही है…';

  @override
  String get gateServiceReachable => 'गेम सर्विस से कनेक्शन है';

  @override
  String get gateServiceUnreachableShort => 'गेम सर्विस से कनेक्शन नहीं है';

  @override
  String get gateUnreachableTitle => 'गेम सर्विस तक नहीं पहुँच पा रहे';

  @override
  String get gateUnreachableMessage =>
      'ऑनलाइन खेलने के लिए लूडो रॉयल को इंटरनेट कनेक्शन चाहिए। अपना वाई-फ़ाई या मोबाइल डेटा जाँचें और फिर कोशिश करें।';

  @override
  String get gateUnreachableLastKnownMaintenance =>
      'हमें मिली आख़िरी जानकारी के अनुसार सर्वर पर मेंटेनेंस चल रहा था।';

  @override
  String get gateUnreachableLastKnownUpdate =>
      'हमें मिली आख़िरी जानकारी के अनुसार इस वर्ज़न को अपडेट करना ज़रूरी है।';

  @override
  String get gateNotFoundTitle => 'अभी उपलब्ध नहीं';

  @override
  String get gateNotFoundMessage =>
      'लूडो रॉयल का यह हिस्सा इस वर्ज़न में अभी उपलब्ध नहीं है।';

  @override
  String get gateGoHome => 'होम पर वापस जाएँ';

  @override
  String homeGreeting(String name) {
    return 'नमस्ते, $name';
  }

  @override
  String get homeQuickPlay => 'क्विक प्ले';

  @override
  String homeQuickPlayDetails(String game, String variant, String players) {
    return '$game · $variant · $players';
  }

  @override
  String get homePrivateRoom => 'प्राइवेट रूम';

  @override
  String get homePrivateRoomSubtitle => 'दोस्तों के लिए रूम बनाएँ';

  @override
  String get homeJoinWithCode => 'कोड से जुड़ें';

  @override
  String get homeJoinWithCodeSubtitle => 'रूम कोड डालें';

  @override
  String get homePlayOnline => 'ऑनलाइन खेलें';

  @override
  String get homePlayWithFriends => 'दोस्तों के साथ खेलें';

  @override
  String get homePracticeVsBots => 'बॉट्स के साथ प्रैक्टिस';

  @override
  String get homeLudoTagline => 'चारों गोटियाँ घर पहुँचाओ';

  @override
  String get homeSnakesTagline => 'सीढ़ी चढ़ो, साँप से बचो';

  @override
  String get homeMissions => 'मिशन';

  @override
  String get homeMissionsSubtitle => 'रोज़ाना और साप्ताहिक लक्ष्य';

  @override
  String get homeCollection => 'कलेक्शन रूम';

  @override
  String get homeCollectionSubtitle => 'पासे, गोटियाँ और फ़्रेम';

  @override
  String get homeFriends => 'दोस्त';

  @override
  String get homeFriendsSubtitle => 'अपनी टोली के साथ खेलें';

  @override
  String get homeEvents => 'इवेंट्स';

  @override
  String get homeEventsSubtitle => 'सीमित समय के कप';

  @override
  String get homeExploreHeader => 'एक्सप्लोर करें';

  @override
  String get homeGamesHeader => 'गेम्स';

  @override
  String get homeSaveProgressTooltip => 'प्रोग्रेस सेव करें';

  @override
  String get homeProfileTooltip => 'प्रोफ़ाइल';

  @override
  String get homeSettingsTooltip => 'सेटिंग्स';

  @override
  String get homeThemeTooltip => 'लाइट/डार्क थीम बदलें';

  @override
  String get homeWalletTooltip => 'वॉलेट';

  @override
  String homeOptionsOnlineTitle(String game) {
    return '$game ऑनलाइन';
  }

  @override
  String homeOptionsFriendsTitle(String game) {
    return 'दोस्तों के साथ $game';
  }

  @override
  String homeOptionsPracticeTitle(String game) {
    return '$game की प्रैक्टिस';
  }

  @override
  String get homeOptionsPrivateRoomTitle => 'प्राइवेट रूम बनाएँ';

  @override
  String get homeGameLabel => 'गेम';

  @override
  String get homePlayersLabel => 'खिलाड़ी';

  @override
  String get homeModeLabel => 'मोड';

  @override
  String get homeBotsLabel => 'बॉट्स';

  @override
  String get homeModeClassicCaption => 'पूरे नियम';

  @override
  String get homeModeQuickCaption => 'छोटे गेम';

  @override
  String homeBotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बॉट',
      one: '1 बॉट',
    );
    return '$_temp0';
  }

  @override
  String get homeFindMatch => 'मैच ढूँढें';

  @override
  String get homeCreateRoom => 'रूम बनाएँ';

  @override
  String get homeStartPractice => 'प्रैक्टिस शुरू करें';

  @override
  String get homeHaveACode => 'कोड है? रूम से जुड़ें';

  @override
  String homeEntryFeeNote(String fee) {
    return 'एंट्री फ़ीस $fee सिक्के · जीतने वाले को पूरा पॉट';
  }

  @override
  String get homePracticeNote =>
      'प्रैक्टिस मुफ़्त है: सिक्के नहीं लगते, फिर भी XP और मिशन प्रोग्रेस मिलती है।';

  @override
  String homeNotEnoughCoins(String fee) {
    return 'इस मैच के लिए कम से कम $fee सिक्के चाहिए।';
  }

  @override
  String get homeJoinCodeTitle => 'प्राइवेट रूम से जुड़ें';

  @override
  String get homeJoinCodeLabel => 'रूम कोड';

  @override
  String get homeJoinCodeHelper => 'होस्ट से 6 अक्षरों वाला कोड माँगें।';

  @override
  String get homeJoinCodeInvalid => 'रूम कोड में 6 अक्षर या अंक होते हैं।';

  @override
  String get homeJoinCodeAction => 'रूम से जुड़ें';

  @override
  String homeLevelUpToast(int level) {
    return 'लेवल अप! आप लेवल $level पर पहुँच गए।';
  }

  @override
  String homeCoinsGainedToast(String amount) {
    return '+$amount सिक्के';
  }

  @override
  String get metaMissionsTitle => 'मिशन';

  @override
  String get metaEventsTitle => 'इवेंट्स';

  @override
  String get metaCollectionTitle => 'कलेक्शन रूम';

  @override
  String get metaFriendsTitle => 'दोस्त';

  @override
  String get metaLeaderboardTitle => 'साप्ताहिक रैंकिंग';

  @override
  String get metaLevelRoadTitle => 'लेवल रोड';

  @override
  String get metaDailyTitle => 'रोज़ाना मिशन';

  @override
  String get metaWeeklyTitle => 'साप्ताहिक चुनौती';

  @override
  String get metaClaim => 'इनाम लें';

  @override
  String get metaStatusInProgress => 'जारी है';

  @override
  String get metaStatusReady => 'इनाम लेने के लिए तैयार';

  @override
  String get metaStatusClaimed => 'इनाम लिया जा चुका';

  @override
  String get metaCollected => 'इनाम मिल गया — आपके खाते में जोड़ दिया गया';

  @override
  String metaProgressCount(String progress, String target) {
    return '$progress / $target';
  }

  @override
  String metaMissionSemantics(String title, String progress, String state) {
    return '$title। प्रगति $progress। $state';
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
    return '$amount सिक्के';
  }

  @override
  String metaRewardDiamondsLabel(String amount) {
    return '$amount हीरे';
  }

  @override
  String metaRewardXpLabel(String amount) {
    return '$amount अनुभव अंक';
  }

  @override
  String metaRewardItemLabel(String name, String kind) {
    return '$name ($kind)';
  }

  @override
  String get metaGameAny => 'कोई भी गेम';

  @override
  String metaResetsDailyAt(String time) {
    return 'नए मिशन $time बजे';
  }

  @override
  String metaResetsWeeklyAt(String day, String time) {
    return '$day को $time बजे रीसेट';
  }

  @override
  String metaEventEndsAt(String date) {
    return '$date को ख़त्म';
  }

  @override
  String metaWhenWithCountdown(String when, String duration) {
    return '$when · $duration में';
  }

  @override
  String metaDurationDaysHours(int days, int hours) {
    return '$days दिन $hours घंटे';
  }

  @override
  String metaDurationHoursMinutes(int hours, int minutes) {
    return '$hours घंटे $minutes मिनट';
  }

  @override
  String metaDurationMinutes(int minutes) {
    return '$minutes मिनट';
  }

  @override
  String get metaNoPenaltyNote =>
      'कोई दिन छूट गया? कोई बात नहीं — आपका XP, लेवल और कलेक्शन हमेशा सुरक्षित रहते हैं।';

  @override
  String get metaMissionsEmptyTitle => 'अभी कोई मिशन नहीं';

  @override
  String get metaMissionsEmptyMessage =>
      'हर दिन नए मिशन आते हैं। रीफ़्रेश करने के लिए नीचे खींचें।';

  @override
  String metaRetryHint(String message) {
    return '$message दोबारा कोशिश करने के लिए फिर से टैप करें।';
  }

  @override
  String get metaNewItemsTitle => 'आपके कलेक्शन में नया!';

  @override
  String metaNewItemsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ये $count आइटम अब आपके हैं — इन्हें लगाइए और मज़े कीजिए।',
      one: 'यह आइटम अब आपका है — इसे लगाइए और मज़े कीजिए।',
    );
    return '$_temp0';
  }

  @override
  String get metaNice => 'बढ़िया!';

  @override
  String get metaViewCollection => 'कलेक्शन देखें';

  @override
  String get metaEventDetails => 'विवरण';

  @override
  String get metaMissionLudoTimeTitle => 'लूडो टाइम';

  @override
  String get metaMissionClimbTitle => 'सीढ़ी चढ़ो';

  @override
  String get metaMissionWarmUpTitle => 'वॉर्म-अप';

  @override
  String get metaMissionFriendlyTableTitle => 'दोस्तों की महफ़िल';

  @override
  String get metaMissionStayToEndTitle => 'आख़िर तक डटे रहो';

  @override
  String get metaMissionTasteOfVictoryTitle => 'जीत का स्वाद';

  @override
  String get metaMissionQuickDrawTitle => 'फटाफट चाल';

  @override
  String get metaMissionWeeklyChallengeTitle => 'साप्ताहिक चुनौती';

  @override
  String get metaMissionAutumnSprintTitle => 'पतझड़ की दौड़';

  @override
  String get metaMissionFallbackTitle => 'मिशन';

  @override
  String metaMissionLudoMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count लूडो मैच पूरे करें।',
      one: '1 लूडो मैच पूरा करें।',
    );
    return '$_temp0';
  }

  @override
  String metaMissionSnakesMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count साँप-सीढ़ी मैच पूरे करें।',
      one: '1 साँप-सीढ़ी मैच पूरा करें।',
    );
    return '$_temp0';
  }

  @override
  String metaMissionAnyMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'किसी भी गेम में $count मैच पूरे करें।',
      one: 'किसी भी गेम में 1 मैच पूरा करें।',
    );
    return '$_temp0';
  }

  @override
  String metaMissionFriendPrivateDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'दोस्तों के साथ $count प्राइवेट मैच पूरे करें।',
      one: 'किसी दोस्त के साथ एक प्राइवेट मैच पूरा करें।',
    );
    return '$_temp0';
  }

  @override
  String metaMissionNoLeavingDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'बीच में छोड़े बिना $count मैच पूरे करें।',
      one: 'बीच में छोड़े बिना एक मैच पूरा करें।',
    );
    return '$_temp0';
  }

  @override
  String metaMissionWinDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count मैच जीतें।',
      one: '1 मैच जीतें।',
    );
    return '$_temp0';
  }

  @override
  String metaMissionQuickLudoDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count क्विक लूडो मैच पूरे करें।',
      one: '1 क्विक लूडो मैच पूरा करें।',
    );
    return '$_temp0';
  }

  @override
  String metaMissionWeeklyDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'लूडो और साँप-सीढ़ी में कुल $count मैच पूरे करें।',
      one: 'लूडो या साँप-सीढ़ी में 1 मैच पूरा करें।',
    );
    return '$_temp0';
  }

  @override
  String get metaEventAutumnCupTitle => 'ऑटम कप';

  @override
  String get metaEventAutumnCupDesc =>
      'क्विक लूडो के साथ मौसम का जश्न मनाइए और पतझड़ का पत्ता पासा जीतिए।';

  @override
  String metaEventWindow(String start, String end) {
    return '$start – $end';
  }

  @override
  String get metaEventLiveBadge => 'इवेंट चल रहा है';

  @override
  String get metaEventMissionsTitle => 'इवेंट मिशन';

  @override
  String get metaEventRulesTitle => 'यह कैसे काम करता है';

  @override
  String get metaEventRuleComplete =>
      'इवेंट चलने के दौरान इवेंट मिशन पूरे करें।';

  @override
  String get metaEventRuleEligible =>
      'मैच तभी गिना जाता है जब आप उसे आख़िर तक खेलें, कम से कम 3 चालें चलें और वह कम से कम 30 सेकंड चले।';

  @override
  String get metaEventRuleClaim =>
      'हर इनाम यहीं लें — वह तुरंत आपके खाते में जुड़ जाता है।';

  @override
  String get metaEventRuleEnd =>
      'इवेंट ख़त्म होने से पहले न लिए गए इनाम फिर उपलब्ध नहीं रहते। आपके XP, लेवल और कलेक्शन पर कभी असर नहीं पड़ता।';

  @override
  String get metaNoEventsTitle => 'अभी कोई इवेंट नहीं';

  @override
  String get metaNoEventsMessage =>
      'नए इवेंट यहाँ दिखेंगे। आपके रोज़ाना मिशन हमेशा उपलब्ध हैं।';

  @override
  String get metaGoToMissions => 'मिशन पर जाएँ';

  @override
  String metaXpToNextLevel(String xp, int level) {
    return 'लेवल $level के लिए $xp XP बाकी';
  }

  @override
  String get metaMaxLevelReached =>
      'अधिकतम लेवल पूरा — XP अब भी साप्ताहिक रैंकिंग में गिना जाता है';

  @override
  String get metaMaxBadge => 'MAX';

  @override
  String metaTotalXp(String xp) {
    return 'कुल XP: $xp';
  }

  @override
  String get metaHowToEarnXp => 'XP कैसे कमाएँ';

  @override
  String metaXpForMatch(int xp) {
    return 'हर पूरे मैच पर +$xp XP';
  }

  @override
  String metaXpForWin(int xp) {
    return 'जीत पर +$xp XP बोनस';
  }

  @override
  String metaXpForFriend(int xp) {
    return 'किसी दोस्त के साथ खेलने पर +$xp XP';
  }

  @override
  String get metaXpForMissions => 'मिशन के इनाम में भी XP मिलता है';

  @override
  String get metaXpFairPlayNote =>
      'मैच तभी गिने जाते हैं जब आख़िर तक खेले जाएँ (कम से कम 3 चालें और 30 सेकंड)। बॉट्स को कभी XP नहीं मिलता।';

  @override
  String get metaMilestonesTitle => 'माइलस्टोन';

  @override
  String get metaMilestoneUnlocked => 'अनलॉक हो गया';

  @override
  String metaMilestoneNext(String xp) {
    return 'अगला माइलस्टोन · $xp XP बाकी';
  }

  @override
  String metaMilestoneLocked(String xp) {
    return '$xp XP बाकी';
  }

  @override
  String get metaNoMilestones => 'माइलस्टोन यहाँ दिखेंगे।';

  @override
  String get metaLevelUpTitle => 'लेवल अप!';

  @override
  String metaLevelUpMessage(int level) {
    return 'आप लेवल $level पर पहुँच गए।';
  }

  @override
  String get metaUnlockedHeader => 'आपके लिए अनलॉक हुआ';

  @override
  String get metaLevelUpContinue => 'शानदार!';

  @override
  String get metaYourLook => 'आपका लुक';

  @override
  String metaCollectedCount(String owned, String total) {
    return '$total में से $owned जमा';
  }

  @override
  String get metaTabDice => 'पासे';

  @override
  String get metaTabTokens => 'गोटियाँ';

  @override
  String get metaTabLudoBoards => 'लूडो बोर्ड';

  @override
  String get metaTabSnakesBoards => 'साँप-सीढ़ी बोर्ड';

  @override
  String get metaTabTrails => 'ट्रेल';

  @override
  String get metaTabVictory => 'जीत का जश्न';

  @override
  String get metaTabFrames => 'फ़्रेम';

  @override
  String get metaTabTitles => 'टाइटल';

  @override
  String get metaTabBadges => 'बैज';

  @override
  String get metaTabEmotes => 'इमोट';

  @override
  String get metaFilterAll => 'सभी';

  @override
  String get metaFilterOwned => 'आपके पास';

  @override
  String get metaFilterLocked => 'अनलॉक करना है';

  @override
  String get metaEquipped => 'लगाया हुआ';

  @override
  String get metaOwned => 'आपके पास है';

  @override
  String get metaLocked => 'लॉक';

  @override
  String get metaNewBadge => 'नया';

  @override
  String metaItemSemantics(
    String name,
    String rarity,
    String state,
    String how,
  ) {
    return '$name, $rarity, $state। $how';
  }

  @override
  String get metaAcqStarter => 'शुरुआती आइटम';

  @override
  String metaAcqLevel(int level) {
    return 'लेवल $level तक पहुँचें';
  }

  @override
  String get metaAcqMission => 'मिशन इनाम';

  @override
  String get metaAcqWeeklyChallenge => 'साप्ताहिक चुनौती का इनाम';

  @override
  String get metaAcqFirstWin => 'अपना पहला मैच जीतें';

  @override
  String get metaAcqEvent => 'इवेंट इनाम';

  @override
  String get metaAcqAutumnCup => 'ऑटम कप का इनाम';

  @override
  String metaPriceCoins(String amount) {
    return '$amount सिक्के';
  }

  @override
  String metaPriceDiamonds(String amount) {
    return '$amount हीरे';
  }

  @override
  String get metaEquip => 'लगाएँ';

  @override
  String get metaEquipDefault => 'डिफ़ॉल्ट लगाएँ';

  @override
  String get metaEquippedToast => 'लगा दिया!';

  @override
  String get metaDefaultEquippedToast => 'डिफ़ॉल्ट लुक वापस लगा दिया';

  @override
  String get metaEmoteHint => 'मैच के दौरान इमोट बटन से अपने इमोट भेजें।';

  @override
  String get metaBadgeHint =>
      'बैज आपकी उपलब्धियों का जश्न हैं। ये हमेशा आपके रहेंगे।';

  @override
  String metaBuyFor(String price) {
    return '$price में ख़रीदें';
  }

  @override
  String get metaBuy => 'ख़रीदें';

  @override
  String metaPurchaseTitle(String item) {
    return '$item ख़रीदें?';
  }

  @override
  String get metaPrice => 'क़ीमत';

  @override
  String get metaYourBalance => 'आपका बैलेंस';

  @override
  String get metaBalanceAfter => 'ख़रीद के बाद';

  @override
  String metaNeedMore(String amount) {
    return 'आपको $amount और चाहिए। मैच जीतकर और मिशन पूरे करके और कमाएँ।';
  }

  @override
  String get metaCosmeticOnlyNote =>
      'सिर्फ़ सजावट के लिए — इससे पासे, नियम या मैचमेकिंग कभी नहीं बदलते।';

  @override
  String metaPurchaseSuccess(String item) {
    return '$item अब आपके कलेक्शन में है!';
  }

  @override
  String get metaNotEnoughCoins => 'इस आइटम के लिए सिक्के कम हैं।';

  @override
  String get metaNotEnoughDiamonds => 'इस आइटम के लिए हीरे कम हैं।';

  @override
  String get metaAlreadyOwned => 'यह आइटम पहले से आपके पास है।';

  @override
  String get metaItemNotForSale =>
      'यह आइटम ख़रीदा नहीं जाता, खेलकर अनलॉक होता है।';

  @override
  String metaUnlocksAtLevel(int level) {
    return 'लेवल $level पर पहुँचते ही अपने आप अनलॉक हो जाएगा।';
  }

  @override
  String get metaEarnFromMissionsHint =>
      'इसे संबंधित मिशन या इवेंट पूरा करके पाएँ — कुछ ख़रीदने की ज़रूरत नहीं।';

  @override
  String get metaAllOwnedInKind =>
      'आपने यहाँ सब कुछ अनलॉक कर लिया है। बहुत बढ़िया!';

  @override
  String get metaNothingOwnedInKind =>
      'यहाँ अभी कुछ नहीं — और अनलॉक करने के लिए खेलते रहें।';

  @override
  String get metaCollectionFairNote =>
      'हर आइटम सिर्फ़ सजावट के लिए है और उसे पाने का तरीका तय है — कोई रैंडम बॉक्स नहीं, खेल में कोई फ़ायदा नहीं।';

  @override
  String get metaDescDiceClassic =>
      'साफ़ काले बिंदुओं वाले सदाबहार आइवरी पासे।';

  @override
  String get metaDescDiceNeon => 'चमकते पासे जो हर थ्रो के साथ धड़कते हैं।';

  @override
  String get metaDescDiceGolden => 'शाही ठाठ वाले चमचमाते सुनहरे पासे।';

  @override
  String get metaDescDiceAutumn => 'ऑटम कप के गर्म अंबर रंग के पासे।';

  @override
  String get metaDescTokenClassic => 'वह गोटी जिसे हर कोई जानता है।';

  @override
  String get metaDescTokenGem =>
      'तराशे हुए रत्न जैसी गोटियाँ जो रोशनी में चमकती हैं।';

  @override
  String get metaDescTokenRoyal => 'छोटे-छोटे मुकुट पहने गोटियाँ।';

  @override
  String get metaDescTokenCrown => 'मुकुट के आकार की एक लेजेंडरी गोटी।';

  @override
  String get metaDescLudoBoardClassic => 'पारंपरिक चार रंगों वाला लूडो बोर्ड।';

  @override
  String get metaDescLudoBoardMidnight => 'चाँदी की नक्काशी वाला गहरा संगमरमर।';

  @override
  String get metaDescLudoBoardRoyal =>
      'सुनहरे और गहरे लाल रंग में महल का आँगन।';

  @override
  String get metaDescSnakesBoardClassic =>
      'हरे घास के मैदान, दोस्ताना साँप, मज़बूत सीढ़ियाँ।';

  @override
  String get metaDescSnakesBoardJungle => 'बेलें, खंडहर और मंदिर की सीढ़ियाँ।';

  @override
  String get metaDescSnakesBoardCandy =>
      'मुलेठी कैंडी के साँप और कैंडी-केन की सीढ़ियाँ।';

  @override
  String get metaDescTrailNone => 'साफ़ चालें, कोई निशान नहीं।';

  @override
  String get metaDescTrailSparkle => 'हर चाल के पीछे चमक की बौछार।';

  @override
  String get metaDescTrailComet => 'धधकती धूमकेतु जैसी पूँछ।';

  @override
  String get metaDescVictoryConfetti => 'कंफ़ेटी के साथ क्लासिक जश्न।';

  @override
  String get metaDescVictoryFireworks => 'जीतने पर आसमान रोशन कर दें।';

  @override
  String get metaDescVictoryCrown => 'विजेता पर सुनहरा मुकुट उतरता है।';

  @override
  String get metaDescFrameNone => 'आपका अवतार, बिना फ़्रेम के।';

  @override
  String get metaDescFrameBronze =>
      'आपके अवतार के चारों ओर एक सादा काँसे का घेरा।';

  @override
  String get metaDescFrameSilver => 'चाँदी की लॉरेल माला।';

  @override
  String get metaDescFrameGold => 'अनुभवी खिलाड़ियों के लिए सुनहरी लॉरेल माला।';

  @override
  String get metaDescFrameRoyal => 'एक सजीला शाही चिह्न।';

  @override
  String get metaDescTitleRookie => 'हर कोई कहीं से शुरुआत करता है।';

  @override
  String get metaDescTitleStrategist =>
      'उन खिलाड़ियों के लिए जो तीन चाल आगे सोचते हैं।';

  @override
  String get metaDescTitleDiceMaster => 'लगता है पासे आपकी बात सुनते हैं।';

  @override
  String get metaDescTitleRoyal => 'सच्चे शाही खिलाड़ियों के लिए।';

  @override
  String get metaDescTitleWeeklyChampion => 'साप्ताहिक चुनौती पूरी की।';

  @override
  String get metaDescBadgeFirstWin => 'आपने अपना पहला मैच जीता।';

  @override
  String get metaDescBadgeFriendly => 'साप्ताहिक चुनौती पूरी की।';

  @override
  String get metaDescEmoteWave => 'नमस्ते कहें।';

  @override
  String get metaDescEmoteThumbs => 'बहुत खूब!';

  @override
  String get metaDescEmoteLaugh => 'साथ में हँसिए।';

  @override
  String get metaDescEmoteWow => 'क्या सच में ऐसा हुआ?';

  @override
  String get metaDescEmoteCrown => 'दिखाइए कि बोर्ड पर किसका राज है।';

  @override
  String get metaYourFriendCode => 'आपका फ़्रेंड कोड';

  @override
  String get metaFriendCodeHint => 'इसे शेयर करें ताकि दोस्त आपको जोड़ सकें।';

  @override
  String metaFriendCodeSemantics(String code) {
    return 'फ़्रेंड कोड: $code';
  }

  @override
  String metaShareFriendCodeMessage(String code) {
    return 'चलो साथ में लूडो रॉयल खेलें! मेरे कोड से मुझे दोस्त बनाएँ: $code';
  }

  @override
  String get metaAddFriend => 'दोस्त जोड़ें';

  @override
  String get metaAdd => 'जोड़ें';

  @override
  String get metaAddFriendTitle => 'दोस्त जोड़ें';

  @override
  String get metaAddFriendHelp =>
      'अपने दोस्त का कोड डालें। उन्हें यह अपनी दोस्त स्क्रीन पर मिलेगा।';

  @override
  String get metaFriendCodeLabel => 'फ़्रेंड कोड';

  @override
  String get metaFriendCodeHintExample => 'u_abcd 2345 wxyz';

  @override
  String get metaPaste => 'पेस्ट करें';

  @override
  String get metaSendRequest => 'रिक्वेस्ट भेजें';

  @override
  String get metaFriendCodeRequired => 'फ़्रेंड कोड डालें।';

  @override
  String get metaInvalidFriendCode =>
      'यह फ़्रेंड कोड जैसा नहीं लगता। यह u_ से शुरू होता है और उसके बाद अक्षर व अंक होते हैं।';

  @override
  String metaRequestSent(String name) {
    return '$name को फ़्रेंड रिक्वेस्ट भेज दी गई';
  }

  @override
  String metaNowFriends(String name) {
    return 'आप और $name अब दोस्त हैं!';
  }

  @override
  String get metaAlreadyFriends => 'आप पहले से दोस्त हैं।';

  @override
  String get metaTabFriends => 'दोस्त';

  @override
  String get metaTabRequests => 'रिक्वेस्ट';

  @override
  String get metaTabRecent => 'हाल के';

  @override
  String get metaOnline => 'ऑनलाइन';

  @override
  String get metaOffline => 'ऑफ़लाइन';

  @override
  String get metaMoreActions => 'और विकल्प';

  @override
  String get metaRemoveFriend => 'दोस्त हटाएँ';

  @override
  String metaRemoveFriendTitle(String name) {
    return '$name को हटाएँ?';
  }

  @override
  String get metaRemoveFriendMessage =>
      'आप फ़्रेंड कोड से कभी भी एक-दूसरे को फिर जोड़ सकते हैं।';

  @override
  String get metaRemove => 'हटाएँ';

  @override
  String metaFriendRemoved(String name) {
    return '$name को आपके दोस्तों से हटा दिया गया';
  }

  @override
  String get metaIncomingRequests => 'मिली रिक्वेस्ट';

  @override
  String get metaOutgoingRequests => 'भेजी गई रिक्वेस्ट';

  @override
  String get metaWantsToBeFriends => 'आपका दोस्त बनना चाहते हैं';

  @override
  String get metaRequestPending => 'जवाब का इंतज़ार';

  @override
  String get metaAccept => 'स्वीकारें';

  @override
  String get metaDecline => 'मना करें';

  @override
  String get metaRequestDeclined => 'रिक्वेस्ट अस्वीकार की गई';

  @override
  String get metaRequestCancelled => 'रिक्वेस्ट रद्द की गई';

  @override
  String get metaRequested => 'भेज दी';

  @override
  String get metaFriendsLabel => 'दोस्त';

  @override
  String get metaNoFriendsTitle => 'अभी कोई दोस्त नहीं';

  @override
  String get metaNoFriendsMessage =>
      'साथ खेलने के लिए अपना कोड शेयर करें या किसी दोस्त को जोड़ें।';

  @override
  String get metaNoRequestsTitle => 'कोई लंबित रिक्वेस्ट नहीं';

  @override
  String get metaNoRequestsMessage =>
      'आपकी भेजी और मिली फ़्रेंड रिक्वेस्ट यहाँ दिखती हैं।';

  @override
  String get metaRecentHint =>
      'पिछले 14 दिनों में ऑनलाइन मैचों में मिले खिलाड़ी।';

  @override
  String get metaNoRecentTitle => 'हाल में कोई प्रतिद्वंद्वी नहीं';

  @override
  String get metaNoRecentMessage =>
      'कोई ऑनलाइन मैच खेलें — जिनसे मिलेंगे वे यहाँ दिखेंगे।';

  @override
  String metaFriendRequestBanner(String name) {
    return '$name आपका दोस्त बनना चाहते हैं';
  }

  @override
  String get metaView => 'देखें';

  @override
  String get metaErrorCannotFriendSelf => 'यह आपका अपना फ़्रेंड कोड है।';

  @override
  String metaErrorFriendLimit(int max) {
    return 'आपके ज़्यादा से ज़्यादा $max दोस्त हो सकते हैं। किसी नए को जोड़ने के लिए एक दोस्त हटाएँ।';
  }

  @override
  String get metaErrorUnknownFriendCode =>
      'इस फ़्रेंड कोड वाला कोई खिलाड़ी नहीं है। जाँचकर फिर कोशिश करें।';

  @override
  String get metaErrorRequestInProgress =>
      'अभी प्रक्रिया जारी है — कृपया थोड़ी देर में फिर कोशिश करें।';

  @override
  String get metaErrorMissionEnded =>
      'यह मिशन ख़त्म हो चुका है। मौजूदा मिशन देखने के लिए नीचे खींचें।';

  @override
  String get metaLeaderboardSubtitle =>
      'आप और आपके दोस्त, इस हफ़्ते कमाए XP के अनुसार।';

  @override
  String get metaLeaderboardTeaser =>
      'देखें इस हफ़्ते आप और आपके दोस्त कैसा कर रहे हैं।';

  @override
  String metaWeeklyXp(String xp) {
    return '$xp XP';
  }

  @override
  String metaYouName(String name) {
    return '$name (आप)';
  }

  @override
  String metaLeaderboardRowSemantics(int rank, String name, String xp) {
    return 'रैंक $rank: $name, $xp';
  }

  @override
  String get metaLeaderboardAlone =>
      'तुलना देखने के लिए दोस्त जोड़ें। दोस्ताना मुक़ाबला, कोई दबाव नहीं।';

  @override
  String numberLakh(String value) {
    return '$value लाख';
  }

  @override
  String numberCrore(String value) {
    return '$value करोड़';
  }

  @override
  String get onboardingLanguageTitle => 'अपनी भाषा चुनें';

  @override
  String get onboardingLanguageSubtitle =>
      'आप इसे कभी भी सेटिंग्स में बदल सकते हैं।';

  @override
  String get onboardingPreviewLabel => 'झलक';

  @override
  String get onboardingPreviewTitle => 'लूडो रॉयल में आपका स्वागत है!';

  @override
  String get onboardingPreviewBody =>
      'पासा फेंकिए, अपनी गोटियाँ घर पहुँचाइए और ताज जीतिए।';

  @override
  String playGameVariantTitle(String game, String variant) {
    return '$game · $variant';
  }

  @override
  String get playModeOnline => 'ऑनलाइन';

  @override
  String get playModePrivate => 'प्राइवेट रूम';

  @override
  String get playModePractice => 'प्रैक्टिस';

  @override
  String playSeatPlayer(int seat) {
    return 'खिलाड़ी $seat';
  }

  @override
  String playNameYou(String name) {
    return '$name (आप)';
  }

  @override
  String get playHome => 'होम';

  @override
  String get playBackHome => 'होम पर वापस जाएँ';

  @override
  String get playTryAgain => 'फिर से कोशिश करें';

  @override
  String playEntryFee(String fee) {
    return 'एंट्री $fee';
  }

  @override
  String playEntryFeeNote(String fee) {
    return 'एंट्री फ़ीस: हर खिलाड़ी से $fee सिक्के, गेम शुरू होने पर लिए जाएँगे। पूरा पॉट विजेता को मिलेगा। बॉट होने पर मुफ़्त।';
  }

  @override
  String get playNotEnoughCoinsTitle => 'पर्याप्त सिक्के नहीं';

  @override
  String playNotEnoughCoinsHint(String fee) {
    return 'खेलने के लिए $fee सिक्के चाहिए। मिशन से सिक्के कमाएँ और फिर आएँ!';
  }

  @override
  String get playSeatOpen => 'खाली सीट';

  @override
  String get playLoadingMatch => 'मैच में जुड़ रहे हैं…';

  @override
  String get playMatchUnavailable => 'यह मैच अब उपलब्ध नहीं है।';

  @override
  String get playRoomClosed => 'रूम बंद कर दिया गया।';

  @override
  String get playRemovedFromRoom => 'आप अब इस रूम में नहीं हैं।';

  @override
  String get playRoomUnavailable => 'यह रूम अब उपलब्ध नहीं है।';

  @override
  String get playLoadingRoom => 'रूम खुल रहा है…';

  @override
  String get playGameLabel => 'गेम';

  @override
  String get playModeLabel => 'नियम';

  @override
  String get playPlayersLabel => 'खिलाड़ी';

  @override
  String get playVariantClassicCaption => '4 गोटियाँ · 6 पर घर से बाहर';

  @override
  String get playVariantQuickCaption => '2 गोटियाँ · 1 या 6 पर घर से बाहर';

  @override
  String get playMatchmakingTitle => 'खिलाड़ी ढूँढ रहे हैं';

  @override
  String get playMatchmakingConnecting => 'गेम सर्वर से जुड़ रहे हैं…';

  @override
  String get playMatchmakingJoining => 'कतार में जुड़ रहे हैं…';

  @override
  String get playMatchmakingSearching => 'प्रतिद्वंद्वी ढूँढ रहे हैं…';

  @override
  String get playMatchmakingStarting => 'टेबल भर गई! शुरू हो रहा है…';

  @override
  String get playMatchmakingStartsSoon =>
      'सभी सीटें भरने पर या टाइमर खत्म होने पर मैच शुरू होगा।';

  @override
  String get playMatchmakingStartsWhenFull =>
      'सभी सीटें भरते ही मैच शुरू हो जाएगा।';

  @override
  String playMatchmakingPlayers(int count, int capacity) {
    return '$capacity में से $count खिलाड़ी जुड़े';
  }

  @override
  String get playMatchmakingCancel => 'खोज रद्द करें';

  @override
  String get playMatchmakingFeeNote =>
      'एंट्री फ़ीस मैच शुरू होने पर ली जाती है। पूरा पॉट विजेता को मिलता है।';

  @override
  String get playMatchmakingTimeoutTitle => 'अभी कोई प्रतिद्वंद्वी नहीं';

  @override
  String get playMatchmakingTimeoutMessage =>
      'समय पर कोई नहीं जुड़ा। फिर से कोशिश करें या दोस्तों को प्राइवेट रूम में बुलाएँ।';

  @override
  String get playMatchmakingErrorTitle => 'मैच नहीं मिल सका';

  @override
  String get playCreateRoomTitle => 'प्राइवेट रूम बनाएँ';

  @override
  String get playCreateRoomAction => 'रूम बनाएँ';

  @override
  String get playCreatingRoom => 'आपका रूम बन रहा है…';

  @override
  String get playLobbyTitle => 'प्राइवेट रूम';

  @override
  String get playRoomCodeLabel => 'रूम कोड';

  @override
  String playRoomCodeA11y(String letters) {
    return 'रूम कोड $letters';
  }

  @override
  String get playCopyCode => 'कोड कॉपी करें';

  @override
  String get playCodeCopied => 'रूम कोड कॉपी हो गया';

  @override
  String get playShareInvite => 'न्योता भेजें';

  @override
  String playInviteShareText(String game, String code) {
    return 'Ludo Royale पर मेरे साथ $game खेलो! ऐप खोलो, \'कोड से जुड़ें\' पर टैप करो और यह कोड डालो: $code';
  }

  @override
  String get playInviteShareSubject => 'Ludo Royale का न्योता';

  @override
  String playLobbyPlayers(int count, int capacity) {
    return 'खिलाड़ी $count/$capacity';
  }

  @override
  String get playLobbyStart => 'गेम शुरू करें';

  @override
  String get playLobbyWaitingForHost => 'होस्ट के शुरू करने का इंतज़ार…';

  @override
  String playLobbyWaitingForNamedHost(String name) {
    return '$name (होस्ट) के शुरू करने का इंतज़ार…';
  }

  @override
  String get playStartBlockedNeedPlayers =>
      'शुरू करने के लिए कम से कम 2 खिलाड़ी चाहिए।';

  @override
  String get playStartBlockedConnections => 'सबके फिर से जुड़ने का इंतज़ार।';

  @override
  String get playStartBlockedBots => 'बॉट अपनी सीट ले रहे हैं…';

  @override
  String get playAllowBots => 'बॉट की अनुमति दें';

  @override
  String get playAllowBotsHint =>
      'खाली सीटों पर कंप्यूटर खिलाड़ी बैठाएँ। बॉट वाले मैच मुफ़्त हैं और इनमें सिक्के नहीं मिलते।';

  @override
  String get playAddBot => 'बॉट जोड़ें';

  @override
  String get playBotJoining => 'बॉट जुड़ रहा है…';

  @override
  String playRemoveBotA11y(String name) {
    return '$name को हटाएँ';
  }

  @override
  String get playBotsFreeNote =>
      'एक बॉट बैठा है: यह मैच मुफ़्त है और इसमें सिक्के नहीं मिलेंगे।';

  @override
  String get playInviteFriends => 'दोस्तों को बुलाएँ';

  @override
  String get playInviteSheetTitle => 'दोस्तों को बुलाएँ';

  @override
  String get playInviteSend => 'बुलाएँ';

  @override
  String get playInviteSent => 'बुला लिया';

  @override
  String get playFriendOnline => 'ऑनलाइन';

  @override
  String get playFriendOffline => 'ऑफ़लाइन';

  @override
  String get playInviteEmptyTitle => 'अभी कोई दोस्त नहीं';

  @override
  String get playInviteEmptyMessage =>
      'इसके बजाय रूम कोड शेयर करें, या दोस्त स्क्रीन से दोस्त जोड़ें।';

  @override
  String get playInviteError => 'आपके दोस्त लोड नहीं हो सके।';

  @override
  String get playLeaveRoom => 'रूम छोड़ें';

  @override
  String get playLeaveRoomTitle => 'यह रूम छोड़ें?';

  @override
  String get playLeaveRoomHostMessage =>
      'आप होस्ट हैं। आपके जाने पर अगला खिलाड़ी होस्ट बन जाएगा।';

  @override
  String get playLeaveRoomMessage =>
      'रूम खुला रहने तक आप रूम कोड से वापस आ सकते हैं।';

  @override
  String get playStay => 'रुकें';

  @override
  String get playHostBadge => 'होस्ट';

  @override
  String get playJoinTitle => 'कोड से जुड़ें';

  @override
  String get playJoinHint => 'दोस्त का शेयर किया 6 अक्षरों का रूम कोड डालें।';

  @override
  String playJoinCodeIncomplete(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining अक्षर और',
      one: '1 अक्षर और',
    );
    return '$_temp0';
  }

  @override
  String get playJoinInvalidChars =>
      'रूम कोड में A–Z अक्षर और 2–9 अंक होते हैं (I, O, 0 या 1 नहीं)।';

  @override
  String get playJoinLookingUp => 'रूम ढूँढ रहे हैं…';

  @override
  String get playJoinAction => 'रूम में जुड़ें';

  @override
  String get playJoining => 'जुड़ रहे हैं…';

  @override
  String playJoinPreviewHost(String name) {
    return 'होस्ट: $name';
  }

  @override
  String playJoinPreviewPlayers(int count, int capacity) {
    return '$count/$capacity खिलाड़ी';
  }

  @override
  String get playJoinStatusOpen => 'खुला';

  @override
  String get playJoinStatusFull => 'भरा हुआ';

  @override
  String get playJoinStatusInProgress => 'चल रहा है';

  @override
  String get playJoinStatusClosed => 'बंद';

  @override
  String get playPaste => 'पेस्ट करें';

  @override
  String get playPracticeTitle => 'बॉट के साथ प्रैक्टिस';

  @override
  String get playPracticeBotsLabel => 'बॉट';

  @override
  String playPracticeBotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बॉट',
      one: '1 बॉट',
    );
    return '$_temp0';
  }

  @override
  String get playPracticeStart => 'प्रैक्टिस शुरू करें';

  @override
  String get playPracticeNote =>
      'प्रैक्टिस मुफ़्त है और इसमें सिक्के नहीं मिलते। आप कंप्यूटर खिलाड़ियों के ख़िलाफ़ खेलते हैं।';

  @override
  String get playPracticeSettingUp => 'आपकी प्रैक्टिस टेबल तैयार हो रही है…';

  @override
  String playPracticeBotsJoining(int seated, int total) {
    return 'बॉट जुड़ रहे हैं… $seated/$total';
  }

  @override
  String get playPracticeBotsUnavailableTitle => 'बॉट अभी व्यस्त हैं';

  @override
  String get playPracticeErrorTitle => 'प्रैक्टिस शुरू नहीं हो सकी';

  @override
  String get playLeave => 'मैच छोड़ें';

  @override
  String get playTurnYourRoll => 'आपकी बारी — पासा दबाएँ!';

  @override
  String get playTurnPickToken => 'चलाने के लिए चमकती गोटी चुनें';

  @override
  String get playTurnYours => 'आपकी बारी';

  @override
  String playTurnOther(String name) {
    return '$name की बारी';
  }

  @override
  String get playVoidedThreeSixes => 'लगातार तीन छक्के! बारी आगे गई।';

  @override
  String playAutoPlayed(String name) {
    return 'समय खत्म — $name की चाल अपने आप चली गई';
  }

  @override
  String playForfeitLeft(String name) {
    return '$name ने मैच छोड़ दिया';
  }

  @override
  String playForfeitTimeouts(String name) {
    return '3 बारियाँ चूकने पर $name को हटा दिया गया';
  }

  @override
  String get playPlayerDisconnected => 'ऑफ़लाइन';

  @override
  String get playPlayerForfeited => 'चला गया';

  @override
  String get playPanelTurnA11y => 'अभी इनकी बारी';

  @override
  String playStrikesA11y(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बारियाँ चूकीं',
      one: '1 बारी चूकी',
    );
    return '$_temp0';
  }

  @override
  String playTokensHome(int home, int total) {
    return '$total में से $home गोटियाँ घर पहुँचीं';
  }

  @override
  String playSquare(int square) {
    return 'खाना $square';
  }

  @override
  String get playAtStart => 'शुरुआत पर';

  @override
  String get playReconnecting => 'फिर से जुड़ रहे हैं… आपका मैच जारी है';

  @override
  String get playSyncing => 'बोर्ड सिंक हो रहा है…';

  @override
  String get playLeaveMatchTitle => 'मैच छोड़ें?';

  @override
  String get playLeaveMatchMessage =>
      'छोड़ने पर हार मानी जाएगी और आपकी एंट्री फ़ीस वापस नहीं मिलेगी।';

  @override
  String get playLeavePracticeMessage => 'आपका प्रैक्टिस गेम खत्म हो जाएगा।';

  @override
  String get playLeaveMatchConfirm => 'छोड़ें';

  @override
  String get playKeepPlaying => 'खेलते रहें';

  @override
  String playRoundLabel(int round) {
    return 'राउंड $round';
  }

  @override
  String get playStartingNextRound => 'अगला राउंड शुरू हो रहा है…';

  @override
  String get playChatOpen => 'क्विक चैट';

  @override
  String get playChatTitle => 'क्विक चैट';

  @override
  String get playChatEmotes => 'इमोट';

  @override
  String get playChatMuteOthers => 'दूसरे खिलाड़ियों को म्यूट करें';

  @override
  String get playChatMutedBySettings => 'सेटिंग्स में क्विक चैट म्यूट है।';

  @override
  String playChatCooldown(int seconds) {
    return 'अगला संदेश $seconds सेकंड में';
  }

  @override
  String get playChatGg => 'अच्छा खेल!';

  @override
  String get playChatNiceMove => 'बढ़िया चाल!';

  @override
  String get playChatWellPlayed => 'बहुत अच्छा खेले!';

  @override
  String get playChatRematch => 'एक और मैच?';

  @override
  String get playChatAgain => 'चलो फिर से खेलें।';

  @override
  String get playChatGoodLuck => 'शुभकामनाएँ!';

  @override
  String get playChatOops => 'उफ़!';

  @override
  String get playChatThanks => 'शुक्रिया!';

  @override
  String get playResultYouWon => 'आप जीत गए!';

  @override
  String playResultWinnerIs(String name) {
    return '$name की जीत!';
  }

  @override
  String get playResultGameOver => 'खेल खत्म';

  @override
  String get playResultYouForfeited => 'आपने मैच छोड़ दिया';

  @override
  String get playResultByForfeit =>
      'बाकी खिलाड़ियों ने हार मान ली — जीत आपकी है।';

  @override
  String get playResultWellPlayed => 'बहुत बढ़िया खेले!';

  @override
  String playResultYouFinished(int place) {
    return 'आप #$place स्थान पर रहे';
  }

  @override
  String get playResultFinishingOrder => 'अंतिम क्रम';

  @override
  String playResultPlaceShort(int place) {
    return '$place';
  }

  @override
  String playResultPlaceA11y(int place) {
    return 'स्थान $place';
  }

  @override
  String get playRewardsTitle => 'इनाम';

  @override
  String playRewardCoins(String amount) {
    return '+$amount सिक्के';
  }

  @override
  String playRewardCoinsBalance(String amount) {
    return 'वॉलेट: $amount सिक्के';
  }

  @override
  String get playRewardNoCoinsMatch => 'इस मैच में सिक्के नहीं मिलते।';

  @override
  String get playRewardNoCoins =>
      'इस बार सिक्के नहीं — पूरा पॉट विजेता को मिलता है।';

  @override
  String playRewardXp(int xp) {
    return '+$xp XP';
  }

  @override
  String get playRewardXpPending => 'XP गिना जा रहा है…';

  @override
  String get playRewardXpLater => 'आपका XP जल्द ही प्रोफ़ाइल पर दिखेगा।';

  @override
  String playRewardLevelUp(int level) {
    return 'लेवल अप! आप लेवल $level पर पहुँच गए';
  }

  @override
  String get playRewardUnlocked => 'अनलॉक हुए';

  @override
  String get playRematchTitle => 'रीमैच';

  @override
  String get playRematchRequest => 'रीमैच माँगें';

  @override
  String get playRematchAccept => 'स्वीकार करें';

  @override
  String get playRematchDecline => 'मना करें';

  @override
  String playRematchIncoming(String name) {
    return '$name ने रीमैच माँगा है!';
  }

  @override
  String get playRematchWaiting => 'आप तैयार हैं! बाकी का इंतज़ार…';

  @override
  String get playRematchYouDeclined => 'आपने रीमैच से मना किया।';

  @override
  String get playRematchClosed => 'रीमैच अब उपलब्ध नहीं है।';

  @override
  String get playRematchPublicNote =>
      'स्वीकार करने वाले खिलाड़ी साथ में नए प्राइवेट रूम में जाएँगे।';

  @override
  String get playRematchStatusAccepted => 'तैयार';

  @override
  String get playRematchStatusDeclined => 'मना किया';

  @override
  String get playRematchStatusPending => 'सोच रहे हैं…';

  @override
  String get playRematchStatusOut => 'चले गए';

  @override
  String playRematchSeatA11y(String name, String status) {
    return '$name: $status';
  }

  @override
  String get playPlayAgain => 'फिर से खेलें';

  @override
  String playInviteIncoming(String name, String game) {
    return '$name ने आपको $game खेलने बुलाया है';
  }

  @override
  String get playInviteJoin => 'जुड़ें';

  @override
  String get playInviteDismiss => 'अभी नहीं';

  @override
  String get playInviteSomeone => 'एक दोस्त';

  @override
  String get profileTitle => 'प्रोफ़ाइल';

  @override
  String get profileFriendCode => 'फ़्रेंड कोड';

  @override
  String get profileFriendCodeHint =>
      'इसे शेयर करें ताकि दोस्त आपको जोड़ सकें।';

  @override
  String profileShareFriendCode(String code) {
    return 'लूडो रॉयल पर मुझे जोड़ें! मेरा फ़्रेंड कोड है $code';
  }

  @override
  String profileLevelProgress(String xp, int level) {
    return 'लेवल $level के लिए $xp XP बाकी';
  }

  @override
  String get profileMaxLevel => 'सबसे ऊँचा लेवल हासिल';

  @override
  String get profileTitleLabel => 'टाइटल';

  @override
  String get profileAccountSection => 'अकाउंट';

  @override
  String get profileAccountType => 'अकाउंट का प्रकार';

  @override
  String get profileAccountGuest => 'मेहमान (सेव नहीं)';

  @override
  String get profileAccountLinked => 'सेव अकाउंट';

  @override
  String get profileLinkedAccounts => 'साइन-इन तरीके';

  @override
  String get profileLinked => 'जुड़ा है';

  @override
  String get profileNotLinked => 'जुड़ा नहीं';

  @override
  String get profileSaveProgressCta => 'प्रोग्रेस सेव करें';

  @override
  String get profileTotalXp => 'कुल XP';

  @override
  String get profileStatsSection => 'प्रोग्रेस';

  @override
  String get profileEditNameTooltip => 'नाम बदलें';

  @override
  String get profileEditNameTitle => 'अपना नाम बदलें';

  @override
  String get profileNameLabel => 'डिस्प्ले नाम';

  @override
  String get profileNameRules =>
      '3–16 अक्षर। अक्षर, अंक, स्पेस, _ . और - इस्तेमाल कर सकते हैं।';

  @override
  String get profileNameNote =>
      'दोस्तों, लीडरबोर्ड और नए गेम में आपका नया नाम दिखेगा। चल रहे गेम में पुराना नाम ही रहेगा।';

  @override
  String profileNameCounterSemantics(int count, int max) {
    return '$max में से $count अक्षर';
  }

  @override
  String profileNameSaved(String name) {
    return 'अब आपका नाम $name है';
  }

  @override
  String get profileNameChangeLimit =>
      'आपने बहुत बार नाम बदला है। कृपया बाद में फिर कोशिश करें।';

  @override
  String profileNameChangeLimitRetry(String wait) {
    return 'आपने बहुत बार नाम बदला है। $wait बाद फिर कोशिश करें।';
  }

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get settingsAppearance => 'दिखावट';

  @override
  String get settingsTheme => 'थीम';

  @override
  String get settingsThemeLight => 'लाइट';

  @override
  String get settingsThemeDark => 'डार्क';

  @override
  String get settingsThemeSystem => 'सिस्टम';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get settingsSoundAndHaptics => 'आवाज़ और वाइब्रेशन';

  @override
  String get settingsSound => 'साउंड इफ़ेक्ट्स';

  @override
  String get settingsHaptics => 'वाइब्रेशन';

  @override
  String get settingsReducedMotion => 'कम एनिमेशन';

  @override
  String get settingsReducedMotionSubtitle => 'कम एनिमेशन और इफ़ेक्ट्स';

  @override
  String get settingsReducedMotionSystemOn =>
      'आपके डिवाइस की सेटिंग्स में भी चालू है';

  @override
  String get settingsGameplay => 'गेमप्ले';

  @override
  String get settingsQuickChatMute => 'क्विक चैट म्यूट करें';

  @override
  String get settingsQuickChatMuteSubtitle =>
      'दूसरे खिलाड़ियों के चैट संदेश और इमोट छिपाएँ';

  @override
  String get settingsPrivacy => 'प्राइवेसी';

  @override
  String get settingsAnalytics => 'गुमनाम इस्तेमाल के आँकड़े शेयर करें';

  @override
  String get settingsAnalyticsSubtitle =>
      'इससे हमें गेम बेहतर बनाने में मदद मिलती है। इसमें कभी आपका नाम, चैट या रूम कोड शामिल नहीं होते।';

  @override
  String get settingsAnalyticsNotConfigured => 'इस बिल्ड में उपलब्ध नहीं';

  @override
  String get settingsAccount => 'अकाउंट';

  @override
  String settingsSignedInAs(String name) {
    return '$name के रूप में साइन इन';
  }

  @override
  String get settingsSaveProgress => 'प्रोग्रेस सेव करें';

  @override
  String get settingsSaveProgressSubtitle =>
      'अपनी प्रोग्रेस सुरक्षित रखने के लिए साइन-इन तरीका जोड़ें';

  @override
  String get settingsSwitchToGuest => 'मेहमान अकाउंट पर वापस जाएँ';

  @override
  String get settingsSwitchToGuestSubtitle =>
      'इस डिवाइस पर सेव मेहमान अकाउंट पर लौटें';

  @override
  String get settingsSignOut => 'साइन आउट';

  @override
  String get settingsAbout => 'ऐप के बारे में';

  @override
  String get settingsVersion => 'वर्ज़न';

  @override
  String get settingsLegalNotices => 'कानूनी सूचनाएँ';

  @override
  String get settingsLegalNoticesSubtitle =>
      'ओपन-सोर्स लाइसेंस · आपके ब्राउज़र में खुलेगा';

  @override
  String get settingsLegalNoticesOpenFailed =>
      'पेज नहीं खुल सका। कृपया बाद में फिर से कोशिश करें।';

  @override
  String get settingsConsentTitle =>
      'लूडो रॉयल को बेहतर बनाने में हमारी मदद करें';

  @override
  String get settingsConsentMessage =>
      'क्या हम गुमनाम इस्तेमाल के आँकड़े जुटा सकते हैं, जैसे कौन-से गेम मोड लोकप्रिय हैं? हम कभी आपका नाम, चैट, रूम कोड या संपर्क जानकारी नहीं जुटाते। आप इसे कभी भी सेटिंग्स में बदल सकते हैं।';

  @override
  String get settingsConsentAllow => 'गुमनाम आँकड़े शेयर करें';

  @override
  String get settingsConsentDeny => 'नहीं, धन्यवाद';

  @override
  String get socialPodOptionsHint => 'खिलाड़ी के विकल्प देखें';

  @override
  String get socialRequestSent => 'रिक्वेस्ट भेजी गई';

  @override
  String get socialAcceptRequest => 'रिक्वेस्ट स्वीकार करें';

  @override
  String get socialReportPlayer => 'खिलाड़ी की रिपोर्ट करें';

  @override
  String get socialReported => 'रिपोर्ट की गई';

  @override
  String get socialAlreadyReported =>
      'आपने पिछले 24 घंटों में इस खिलाड़ी की रिपोर्ट की है।';

  @override
  String socialReportsLeft(int remaining, int total) {
    return 'आज बची रिपोर्ट: $total में से $remaining';
  }

  @override
  String socialReportLimitAt(int total, String time) {
    return 'आपने आज की $total रिपोर्ट इस्तेमाल कर ली हैं। आप $time पर फिर से रिपोर्ट कर सकते हैं।';
  }

  @override
  String socialReportLimitLater(int total) {
    return 'आपने आज की $total रिपोर्ट इस्तेमाल कर ली हैं। बाद में फिर कोशिश करें।';
  }

  @override
  String socialReportTitle(String name) {
    return '$name की रिपोर्ट करें';
  }

  @override
  String get socialReportWhy => 'क्या हुआ?';

  @override
  String get socialReasonCheating => 'धोखाधड़ी';

  @override
  String get socialReasonOffensiveName => 'आपत्तिजनक नाम';

  @override
  String get socialReasonAbusiveBehavior => 'अपमानजनक व्यवहार';

  @override
  String get socialReasonLeavingOrStalling => 'गेम छोड़ना या जानबूझकर देर करना';

  @override
  String get socialReasonOther => 'कुछ और';

  @override
  String get socialReportReviewNote =>
      'हमारी टीम हर रिपोर्ट की समीक्षा करती है। इसकी स्थिति दोस्त स्क्रीन के रिपोर्ट टैब में देखें।';

  @override
  String get socialSendReport => 'रिपोर्ट भेजें';

  @override
  String socialReportSent(int remaining, int total) {
    return 'रिपोर्ट भेज दी गई। आज $total में से $remaining रिपोर्ट बची हैं।';
  }

  @override
  String socialFriendLimitNote(int max) {
    return 'आपके ज़्यादा से ज़्यादा $max दोस्त हो सकते हैं — नया जोड़ने के लिए किसी एक को हटाएँ।';
  }

  @override
  String get socialErrorCannotReportSelf => 'आप ख़ुद की रिपोर्ट नहीं कर सकते।';

  @override
  String get socialErrorCannotReportBot =>
      'इस खिलाड़ी की रिपोर्ट नहीं की जा सकती।';

  @override
  String get socialErrorNotInRoom =>
      'आप सिर्फ़ उसी मैच के खिलाड़ियों की रिपोर्ट कर सकते हैं जिसमें आप हैं।';

  @override
  String get socialErrorRoomNotFound =>
      'यह मैच अब नहीं मिल रहा, इसलिए रिपोर्ट नहीं भेजी जा सकी।';

  @override
  String get socialErrorPlayerNotFound => 'यह खिलाड़ी नहीं मिला।';

  @override
  String get socialTabReported => 'रिपोर्ट की गई';

  @override
  String socialOnlineNow(int count) {
    return 'अभी ऑनलाइन ($count)';
  }

  @override
  String socialOfflineCount(int count) {
    return 'ऑफ़लाइन ($count)';
  }

  @override
  String socialFriendsCount(int count, int max) {
    return 'दोस्त $count/$max';
  }

  @override
  String socialReportsResetAt(String time) {
    return 'आप $time पर फिर से रिपोर्ट कर सकते हैं।';
  }

  @override
  String socialReportsInfo(int total) {
    return 'आप एक दिन में ज़्यादा से ज़्यादा $total खिलाड़ियों की रिपोर्ट कर सकते हैं। हमारी टीम हर रिपोर्ट की समीक्षा करती है।';
  }

  @override
  String get socialNoReportsTitle => 'कोई रिपोर्ट नहीं';

  @override
  String get socialNoReportsMessage =>
      'मैच से जिन खिलाड़ियों की आप रिपोर्ट करेंगे, वे यहाँ हर रिपोर्ट की स्थिति के साथ दिखेंगे।';

  @override
  String get socialStatusSubmitted => 'भेजी गई';

  @override
  String get socialStatusReviewing => 'समीक्षा जारी';

  @override
  String get socialStatusActionTaken => 'कार्रवाई हुई';

  @override
  String get socialStatusDismissed => 'ख़ारिज';

  @override
  String get socialJustNow => 'अभी-अभी';

  @override
  String socialMinutesAgo(int minutes) {
    return '$minutes मिनट पहले';
  }

  @override
  String socialHoursAgo(int hours) {
    return '$hours घंटे पहले';
  }

  @override
  String get socialYesterday => 'कल';

  @override
  String socialReportStatusA11y(String status) {
    return 'स्थिति: $status';
  }

  @override
  String get walletTitle => 'आपका वॉलेट';

  @override
  String get walletCoinsCaption =>
      'मैच की एंट्री फ़ीस के लिए — जीतने वाले को पूरा पॉट मिलता है।';

  @override
  String get walletDiamondsCaption =>
      'कलेक्शन रूम में प्रीमियम कॉस्मेटिक्स के लिए।';

  @override
  String walletExactBalance(String amount) {
    return 'सटीक बैलेंस: $amount';
  }

  @override
  String get walletVirtualTitle => 'वर्चुअल करेंसी';

  @override
  String get walletVirtualNotice =>
      'सिक्के और हीरे सिर्फ़ मनोरंजन के लिए वर्चुअल आइटम हैं। इनकी कोई असली क़ीमत नहीं है और इन्हें बेचा, ट्रांसफ़र, निकाला या पैसों में बदला नहीं जा सकता।';

  @override
  String get walletEarnTitle => 'और कैसे कमाएँ';

  @override
  String get walletEarnWins => 'मैच जीतें और पॉट पाएँ';

  @override
  String get walletEarnMissions => 'रोज़ाना और साप्ताहिक मिशन पूरे करें';

  @override
  String get walletEarnLevels => 'लेवल बढ़ाएँ और माइलस्टोन इनाम पाएँ';

  @override
  String get walletRefresh => 'बैलेंस रिफ़्रेश करें';

  @override
  String widgetsCoinsBalance(String amount) {
    return 'सिक्के: $amount';
  }

  @override
  String widgetsDiamondsBalance(String amount) {
    return 'हीरे: $amount';
  }

  @override
  String widgetsXpLabel(String current, String total) {
    return 'अनुभव: $total में से $current';
  }

  @override
  String get widgetsAvatarLabel => 'खिलाड़ी का अवतार';

  @override
  String widgetsTitleLabel(String title) {
    return 'उपाधि: $title';
  }

  @override
  String widgetsEmoteLabel(String name) {
    return 'इमोट: $name';
  }

  @override
  String widgetsBadgeLabel(String name) {
    return 'बैज: $name';
  }

  @override
  String widgetsSecondsLeft(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds सेकंड बाकी',
      one: '1 सेकंड बाकी',
    );
    return '$_temp0';
  }

  @override
  String widgetsConnectionLabel(String status) {
    return 'कनेक्शन: $status';
  }

  @override
  String widgetsNewItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count नए',
      one: '1 नया',
    );
    return '$_temp0';
  }

  @override
  String get widgetsSelected => 'चुना गया';

  @override
  String widgetsLogoLabel(String appName) {
    return '$appName का शाही चिह्न';
  }
}
