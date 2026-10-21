// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get authWelcomeTitle => 'مستعد لتحكم اللوحة؟';

  @override
  String get authWelcomeSubtitle =>
      'العب لودو والسلم والثعبان مع أصدقائك ولاعبين من كل مكان.';

  @override
  String get authContinueWithGoogle => 'المتابعة باستخدام Google';

  @override
  String get authContinueWithFacebook => 'المتابعة باستخدام Facebook';

  @override
  String get authContinueWithApple => 'تسجيل الدخول باستخدام Apple';

  @override
  String get authPlayAsGuest => 'العب كضيف';

  @override
  String get authGuestHint => 'ابدأ فورًا — يمكنك حفظ تقدّمك في أي وقت.';

  @override
  String get authOrDivider => 'أو';

  @override
  String get authFairPlayNote =>
      'العملات والماسات افتراضية ولا يمكن استبدالها بأموال حقيقية.';

  @override
  String get authSessionExpiredBanner =>
      'تم تسجيل خروجك. يُرجى تسجيل الدخول مرة أخرى.';

  @override
  String get authSignedInElsewhereTitle => 'تم تسجيل الدخول على جهاز آخر';

  @override
  String get authSignedInElsewhereMessage =>
      'سجّل أحدهم الدخول إلى حسابك على جهاز آخر، لذا تم تسجيل خروجك هنا. يمكن تسجيل الدخول على جهاز واحد فقط في كل مرة. سجّل الدخول مرة أخرى للعب هنا — وسيتم تسجيل خروج الجهاز الآخر.';

  @override
  String get authSignedInElsewhereBanner =>
      'تم تسجيل الدخول إلى حسابك على جهاز آخر.';

  @override
  String get authChangeLanguage => 'تغيير اللغة';

  @override
  String get authProviderGoogle => 'Google';

  @override
  String get authProviderFacebook => 'Facebook';

  @override
  String get authProviderApple => 'Apple';

  @override
  String get authProviderGuest => 'ضيف';

  @override
  String get authSaveProgressTitle => 'احفظ تقدّمك';

  @override
  String get authSaveProgressSubtitle =>
      'اربط طريقة لتسجيل الدخول حتى لا تفقد عملاتك ومستواك ومجموعتك أبدًا — حتى على هاتف جديد.';

  @override
  String get authSaveBenefitKeep => 'احتفظ بكل عملاتك وخبرتك وعناصرك التجميلية';

  @override
  String get authSaveBenefitDevices => 'سجّل الدخول من أي جهاز';

  @override
  String get authSaveBenefitSame => 'الحساب نفسه — لا شيء يُعاد ضبطه أو يُنقل';

  @override
  String get authSaveWithGoogle => 'الحفظ باستخدام Google';

  @override
  String get authSaveWithFacebook => 'الحفظ باستخدام Facebook';

  @override
  String get authSaveWithApple => 'الحفظ باستخدام Apple';

  @override
  String get authSaveNoProviders => 'لا تتوفر طرق تسجيل دخول في هذا الإصدار.';

  @override
  String get authLinkSuccessTitle => 'تم حفظ تقدّمك!';

  @override
  String authLinkSuccessMessage(String provider) {
    return 'أصبح حسابك مرتبطًا بـ $provider. سجّل الدخول باستخدام $provider على أي جهاز للمتابعة.';
  }

  @override
  String get authAlreadySavedTitle => 'تقدّمك محفوظ';

  @override
  String get authAlreadySavedMessage =>
      'هذا الحساب مرتبط بطريقة تسجيل دخول، لذا تقدّمك في أمان.';

  @override
  String authConflictTitle(String provider) {
    return 'حساب $provider هذا مستخدم بالفعل';
  }

  @override
  String authConflictMessage(String provider) {
    return 'حساب $provider هذا لديه بالفعل حساب لودو رويال خاص به. لن يتم دمج أو نقل أي شيء بين الحسابين.';
  }

  @override
  String get authConflictSignIn => 'تسجيل الدخول إلى ذلك الحساب';

  @override
  String get authConflictGuestNote =>
      'يبقى حساب الضيف على هذا الجهاز — يمكنك العودة إليه من الإعدادات.';

  @override
  String get authAlreadyLinkedTitle => 'مرتبط بالفعل';

  @override
  String authAlreadyLinkedMessage(String provider) {
    return 'هذا الحساب مرتبط بالفعل بحساب $provider آخر.';
  }

  @override
  String get authLogoutTitle => 'تسجيل الخروج؟';

  @override
  String get authLogoutMessage =>
      'يمكنك تسجيل الدخول مجددًا في أي وقت بالطريقة نفسها.';

  @override
  String get authLogoutConfirm => 'تسجيل الخروج';

  @override
  String get authGuestLogoutTitle => 'تسجيل الخروج من حساب الضيف؟';

  @override
  String get authGuestLogoutMessage =>
      'أنت تلعب كضيف. إذا سجّلت الخروج الآن فستفقد عملاتك ومستواك ومجموعتك ما لم تحفظ تقدّمك أولًا.';

  @override
  String get authGuestLogoutConfirm => 'تسجيل الخروج وفقدان التقدّم';

  @override
  String get authSaveProgressFirst => 'احفظ التقدّم أولًا';

  @override
  String get authSwitchToGuestTitle => 'العودة إلى حساب الضيف؟';

  @override
  String get authSwitchToGuestMessage =>
      'ستغادر هذا الحساب وتتابع بحساب الضيف المحفوظ على هذا الجهاز.';

  @override
  String get authSwitchToGuestConfirm => 'التبديل إلى الضيف';

  @override
  String get authGuestUnavailable => 'حساب الضيف هذا لم يعد متاحًا.';

  @override
  String authWelcomeBack(String name) {
    return 'أهلًا، $name!';
  }

  @override
  String get boardsColorRed => 'الأحمر';

  @override
  String get boardsColorGreen => 'الأخضر';

  @override
  String get boardsColorYellow => 'الأصفر';

  @override
  String get boardsColorBlue => 'الأزرق';

  @override
  String get boardsLudoBoardLabel => 'لوحة لودو';

  @override
  String get boardsSnakesBoardLabel => 'لوحة السلم والثعبان';

  @override
  String boardsTokenInBase(String color, int number) {
    return 'الحجر $color رقم $number، في القاعدة';
  }

  @override
  String boardsTokenStepsFromHome(String color, int number, int steps) {
    String _temp0 = intl.Intl.pluralLogic(
      steps,
      locale: localeName,
      other: 'على بعد $steps مربع من المنزل',
      many: 'على بعد $steps مربعًا من المنزل',
      few: 'على بعد $steps مربعات من المنزل',
      two: 'على بعد مربعين من المنزل',
      one: 'على بعد مربع واحد من المنزل',
    );
    return 'الحجر $color رقم $number، $_temp0';
  }

  @override
  String boardsTokenHome(String color, int number) {
    return 'الحجر $color رقم $number، وصل إلى المنزل';
  }

  @override
  String get boardsTokenCanMove => 'يمكن تحريكه';

  @override
  String get boardsTokenMoveHint => 'تحريك هذا الحجر';

  @override
  String get boardsCurrentTurn => 'دوره الآن';

  @override
  String boardsSnakesTokenOnSquare(String color, int square) {
    return 'الحجر $color على المربع $square';
  }

  @override
  String boardsSnakesTokenAtStart(String color) {
    return 'الحجر $color عند نقطة البداية';
  }

  @override
  String boardsDiceShowing(int value) {
    return 'النرد يُظهر $value';
  }

  @override
  String get boardsDiceRolling => 'النرد يتدحرج';

  @override
  String get boardsDiceRollHint => 'رمي النرد';

  @override
  String get boardsVictoryCelebration => 'احتفال بالفوز';

  @override
  String get boardsLevelUp => 'ارتقاء في المستوى';

  @override
  String get commonOk => 'حسنًا';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonContinue => 'متابعة';

  @override
  String get commonBack => 'رجوع';

  @override
  String get commonDone => 'تم';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonLater => 'لاحقًا';

  @override
  String get commonLoading => 'جارٍ التحميل…';

  @override
  String get commonCopy => 'نسخ';

  @override
  String get commonCopied => 'تم النسخ!';

  @override
  String get commonShare => 'مشاركة';

  @override
  String get commonYes => 'نعم';

  @override
  String get commonNo => 'لا';

  @override
  String get commonSomethingWentWrong => 'حدث خطأ ما.';

  @override
  String get commonNothingHereYet => 'لا يوجد شيء هنا بعد';

  @override
  String get commonYou => 'أنت';

  @override
  String get commonGuest => 'ضيف';

  @override
  String get commonCoins => 'عملات';

  @override
  String get commonDiamonds => 'ماسات';

  @override
  String commonLevel(int level) {
    return 'المستوى $level';
  }

  @override
  String commonLevelShort(int level) {
    return 'مستوى $level';
  }

  @override
  String commonXpProgress(String current, String total) {
    return '$current / $total خبرة';
  }

  @override
  String get commonConnectionConnected => 'متصل';

  @override
  String get commonConnectionConnecting => 'جارٍ الاتصال…';

  @override
  String get commonConnectionReconnecting => 'جارٍ إعادة الاتصال…';

  @override
  String get commonConnectionOffline => 'غير متصل';

  @override
  String get commonConnectionReplaced => 'هذه اللعبة مفتوحة في مكان آخر';

  @override
  String get commonReconnect => 'إعادة الاتصال';

  @override
  String commonSecondsShort(int seconds) {
    return '$seconds ث';
  }

  @override
  String get commonGameLudo => 'لودو';

  @override
  String get commonGameSnakesLadders => 'السلم والثعبان';

  @override
  String get commonVariantClassic => 'كلاسيكي';

  @override
  String get commonVariantQuick => 'سريع';

  @override
  String commonPlayerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count لاعب',
      many: '$count لاعبًا',
      few: '$count لاعبين',
      two: 'لاعبان',
      one: 'لاعب واحد',
    );
    return '$_temp0';
  }

  @override
  String get commonOfflineHint =>
      'أنت غير متصل. تحقّق من الاتصال وحاول مرة أخرى.';

  @override
  String commonEntryFee(String amount) {
    return 'رسوم الدخول $amount';
  }

  @override
  String get commonFree => 'مجاني';

  @override
  String get appTitle => 'لودو رويال';

  @override
  String get languageNameNative => 'العربية';

  @override
  String get cosmeticDiceClassic => 'عاجي كلاسيكي';

  @override
  String get cosmeticDiceNeon => 'نبض النيون';

  @override
  String get cosmeticDiceGolden => 'الذهب الملكي';

  @override
  String get cosmeticDiceAutumn => 'ورقة الخريف';

  @override
  String get cosmeticTokenClassic => 'البيدق الكلاسيكي';

  @override
  String get cosmeticTokenGem => 'الحجر الكريم';

  @override
  String get cosmeticTokenRoyal => 'البيدق الملكي';

  @override
  String get cosmeticTokenCrown => 'قطعة التاج';

  @override
  String get cosmeticLudoBoardClassic => 'كلاسيكي';

  @override
  String get cosmeticLudoBoardMidnight => 'رخام منتصف الليل';

  @override
  String get cosmeticLudoBoardRoyal => 'البلاط الملكي';

  @override
  String get cosmeticSnakesBoardClassic => 'المرج الكلاسيكي';

  @override
  String get cosmeticSnakesBoardJungle => 'معبد الأدغال';

  @override
  String get cosmeticSnakesBoardCandy => 'أرض الحلوى';

  @override
  String get cosmeticTrailNone => 'بلا أثر';

  @override
  String get cosmeticTrailSparkle => 'بريق';

  @override
  String get cosmeticTrailComet => 'مذنّب';

  @override
  String get cosmeticVictoryConfetti => 'قصاصات ملوّنة';

  @override
  String get cosmeticVictoryFireworks => 'ألعاب نارية';

  @override
  String get cosmeticVictoryCrown => 'التاج الذهبي';

  @override
  String get cosmeticFrameNone => 'بلا إطار';

  @override
  String get cosmeticFrameBronze => 'الحلقة البرونزية';

  @override
  String get cosmeticFrameSilver => 'إكليل الغار الفضي';

  @override
  String get cosmeticFrameGold => 'إكليل الغار الذهبي';

  @override
  String get cosmeticFrameRoyal => 'الشعار الملكي';

  @override
  String get cosmeticTitleRookie => 'مبتدئ';

  @override
  String get cosmeticTitleStrategist => 'خبير استراتيجي';

  @override
  String get cosmeticTitleDiceMaster => 'سيّد النرد';

  @override
  String get cosmeticTitleRoyal => 'صاحب السمو';

  @override
  String get cosmeticTitleWeeklyChampion => 'بطل الأسبوع';

  @override
  String get cosmeticBadgeFirstWin => 'الفوز الأول';

  @override
  String get cosmeticBadgeFriendly => 'رفقة طيبة';

  @override
  String get cosmeticEmoteWave => 'تلويح';

  @override
  String get cosmeticEmoteThumbs => 'إعجاب';

  @override
  String get cosmeticEmoteLaugh => 'ضحكة';

  @override
  String get cosmeticEmoteWow => 'واو';

  @override
  String get cosmeticEmoteCrown => 'تاج';

  @override
  String get cosmeticRarityCommon => 'عادي';

  @override
  String get cosmeticRarityRare => 'نادر';

  @override
  String get cosmeticRarityEpic => 'ملحمي';

  @override
  String get cosmeticRarityLegendary => 'أسطوري';

  @override
  String get cosmeticKindDice => 'النرد';

  @override
  String get cosmeticKindToken => 'البيادق';

  @override
  String get cosmeticKindLudoBoard => 'لوحة لودو';

  @override
  String get cosmeticKindSnakesBoard => 'لوحة السلم والثعبان';

  @override
  String get cosmeticKindFrame => 'إطار الصورة';

  @override
  String get cosmeticKindTitle => 'اللقب';

  @override
  String get cosmeticKindBadge => 'الشارة';

  @override
  String get cosmeticKindEmote => 'تعبير';

  @override
  String get cosmeticKindVictory => 'احتفال الفوز';

  @override
  String get cosmeticKindTrail => 'أثر البيدق';

  @override
  String get errorGeneric => 'حدث خطأ ما. يُرجى المحاولة مرة أخرى.';

  @override
  String get errorBadRequest => 'تعذّرت معالجة هذا الطلب.';

  @override
  String get errorUnknownType => 'هذا الإجراء غير مدعوم. يُرجى تحديث التطبيق.';

  @override
  String get errorRateLimited => 'على مهلك! انتظر لحظة ثم حاول مرة أخرى.';

  @override
  String get errorUnauthorized => 'انتهت جلستك. يُرجى تسجيل الدخول مرة أخرى.';

  @override
  String get errorUpdateRequired => 'يلزم إصدار أحدث من التطبيق.';

  @override
  String get errorMaintenance =>
      'خوادم اللعبة قيد الصيانة. حاول مرة أخرى قريبًا.';

  @override
  String get errorNotInRoom => 'لم تعد في هذه الغرفة.';

  @override
  String get errorRoomNotFound => 'هذه الغرفة لم تعد موجودة.';

  @override
  String get errorRoomFull => 'هذه الغرفة ممتلئة بالفعل.';

  @override
  String get errorRoomInProgress => 'بدأت هذه اللعبة بالفعل.';

  @override
  String get errorRoomClosed => 'تم إغلاق هذه الغرفة.';

  @override
  String get errorAlreadyInRoom =>
      'أنت في غرفة بالفعل. غادرها أولًا للانضمام إلى غرفة أخرى.';

  @override
  String get errorNotHost => 'يمكن للمضيف فقط القيام بذلك.';

  @override
  String get errorNotEnoughPlayers => 'يلزم لاعبان على الأقل للبدء.';

  @override
  String get errorPlayersNotReady => 'بانتظار جاهزية جميع اللاعبين.';

  @override
  String get errorNotYourTurn => 'ليس دورك بعد.';

  @override
  String get errorInvalidPhase => 'لا يمكنك فعل ذلك الآن.';

  @override
  String get errorIllegalMove => 'هذه الحركة غير مسموح بها.';

  @override
  String get errorStaleState => 'تغيّرت اللوحة للتو. حاول مرة أخرى.';

  @override
  String get errorInsufficientFunds => 'ليس لديك ما يكفي من العملات لهذا.';

  @override
  String get errorInvalidCode =>
      'رمز الغرفة غير صالح. تحقّق منه وحاول مرة أخرى.';

  @override
  String get errorRematchClosed => 'انتهت مهلة إعادة المباراة.';

  @override
  String get errorNotFriends => 'يمكنك دعوة أصدقائك فقط.';

  @override
  String get errorItemNotOwned => 'لا تملك هذا العنصر بعد.';

  @override
  String get errorBotsUnavailable =>
      'لا يتوفر لاعبون آليون الآن. حاول مرة أخرى بعد قليل.';

  @override
  String get errorBotsNotAllowed =>
      'اللاعبون الآليون غير مسموح بهم في هذه الغرفة.';

  @override
  String get errorInternal => 'حدث خطأ من جهتنا. يُرجى المحاولة مرة أخرى.';

  @override
  String get errorClientVersionRequired =>
      'تعذّر على التطبيق تحديد إصداره. يُرجى تحديث التطبيق أو إعادة تثبيته.';

  @override
  String get errorEnvironmentMismatch =>
      'هذا الإصدار من التطبيق متصل بالخادم الخطأ.';

  @override
  String get errorInvalidCredential =>
      'تعذّر تسجيل الدخول. يُرجى المحاولة مرة أخرى.';

  @override
  String get errorRefreshReused =>
      'حفاظًا على أمانك، تم تسجيل خروجك. يُرجى تسجيل الدخول مرة أخرى.';

  @override
  String get errorSessionReplaced =>
      'تم تسجيل الدخول إلى حسابك على جهاز آخر. يُرجى تسجيل الدخول مرة أخرى.';

  @override
  String get errorForbidden => 'ليس لديك إذن للقيام بذلك.';

  @override
  String get errorNotFound => 'لم نعثر على ما تبحث عنه.';

  @override
  String get errorIdentityConflict =>
      'حساب تسجيل الدخول هذا مرتبط بالفعل بملف لاعب آخر.';

  @override
  String get errorProviderAlreadyLinked =>
      'ملفك مرتبط بالفعل بحساب آخر من النوع نفسه.';

  @override
  String get errorAlreadyOwned => 'أنت تملك هذا العنصر بالفعل.';

  @override
  String get errorAlreadyClaimed => 'لقد استلمت هذه المكافأة بالفعل.';

  @override
  String get errorAlreadyFriends => 'أنتما صديقان بالفعل.';

  @override
  String get errorNotCompleted => 'أكمل هذه المهمة أولًا لاستلام المكافأة.';

  @override
  String get errorItemLocked => 'هذا العنصر ما زال مقفلًا.';

  @override
  String get errorAssetsUnavailable =>
      'لا يمكن تنزيل الصور الآن. يُرجى المحاولة لاحقًا.';

  @override
  String get errorProviderUnavailable =>
      'خدمة تسجيل الدخول غير متاحة الآن. يُرجى المحاولة لاحقًا.';

  @override
  String get errorNetwork =>
      'تعذّر الوصول إلى خدمة اللعبة. تحقّق من اتصالك بالإنترنت.';

  @override
  String get errorTimeout => 'انتهت مهلة الاتصال. يُرجى المحاولة مرة أخرى.';

  @override
  String get errorBadResponse =>
      'تلقّينا ردًا غير متوقع. يُرجى المحاولة مرة أخرى.';

  @override
  String get errorCancelled => 'تم الإلغاء.';

  @override
  String get errorNotConnected => 'أنت غير متصل الآن. جارٍ إعادة الاتصال…';

  @override
  String errorRateLimitedRetry(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'محاولات كثيرة. حاول مجددًا بعد $seconds ثانية.',
      many: 'محاولات كثيرة. حاول مجددًا بعد $seconds ثانية.',
      few: 'محاولات كثيرة. حاول مجددًا بعد $seconds ثوانٍ.',
      two: 'محاولات كثيرة. حاول مجددًا بعد ثانيتين.',
      one: 'محاولات كثيرة. حاول مجددًا بعد ثانية واحدة.',
    );
    return '$_temp0';
  }

  @override
  String get errorInvalidName =>
      'لا يمكن استخدام هذا الاسم. يُرجى اختيار اسم آخر.';

  @override
  String get errorInvalidNameTooShort =>
      'يجب أن يتكوّن الاسم من 3 أحرف على الأقل.';

  @override
  String get errorInvalidNameTooLong =>
      'يمكن أن يتكوّن الاسم من 16 حرفًا كحد أقصى.';

  @override
  String get errorInvalidNameCharacters =>
      'استخدم الحروف والأرقام والمسافات و_ . أو - فقط (حرف واحد على الأقل). بلا رموز تعبيرية أو رموز.';

  @override
  String get errorInvalidNameReserved =>
      'هذا الاسم محجوز. يُرجى اختيار اسم آخر.';

  @override
  String get errorInvalidNameInappropriate =>
      'هذا الاسم غير مسموح به. يُرجى اختيار اسم لائق.';

  @override
  String get gateSplashTagline => 'ارمِ. تسابق. احكم.';

  @override
  String get gateStatusChecking => 'جارٍ التحقق من خوادم اللعبة…';

  @override
  String get gateStatusSigningIn => 'جارٍ تسجيل دخولك…';

  @override
  String get gateStatusLoadingProfile => 'جارٍ تحميل ملفك الشخصي…';

  @override
  String get gateUpdateNow => 'حدّث الآن';

  @override
  String get gateForceUpdateTitle => 'التحديث مطلوب';

  @override
  String get gateForceUpdateMessage =>
      'لم يعد هذا الإصدار من لودو رويال مدعومًا. حدّث التطبيق لمواصلة اللعب عبر الإنترنت — عملاتك وتقدّمك في أمان.';

  @override
  String get gateInstalledVersion => 'الإصدار المثبّت';

  @override
  String get gateRequiredVersion => 'الإصدار المطلوب';

  @override
  String get gateStoreNotReadyTitle => 'التحديث غير متوفر في المتجر بعد';

  @override
  String get gateStoreNotReadyMessage =>
      'الإصدار الجديد في طريقه إلى متجر التطبيقات. يُرجى التحقق مرة أخرى بعد قليل.';

  @override
  String get gateCheckAgain => 'تحقّق مجددًا';

  @override
  String get gateOptionalUpdateTitle => 'يتوفر إصدار جديد';

  @override
  String gateOptionalUpdateMessage(String version) {
    return 'يجلب الإصدار $version إصلاحات وتحسينات. حدّث الآن لتجربة لعب أكثر سلاسة.';
  }

  @override
  String get gateMaintenanceTitle => 'نحن نلمّع اللوحات';

  @override
  String get gateMaintenanceMessage =>
      'لودو رويال قيد الصيانة حاليًا. عملاتك وتقدّمك ومبارياتك الجارية في أمان — ستُستأنف المباريات فور عودتنا.';

  @override
  String gateMaintenanceEstimatedEnd(String time) {
    return 'الانتهاء المتوقع: $time';
  }

  @override
  String get gateMaintenanceEstimateNote => 'هذا مجرد تقدير وقد يتغير.';

  @override
  String get gateMaintenanceAutoCheck => 'سنتحقق تلقائيًا كل 30 ثانية.';

  @override
  String gateLastChecked(String time) {
    return 'آخر تحقق: $time';
  }

  @override
  String get gateCheckingNow => 'جارٍ التحقق…';

  @override
  String get gateServiceReachable => 'خدمة اللعبة متاحة';

  @override
  String get gateServiceUnreachableShort => 'لا يوجد اتصال بخدمة اللعبة';

  @override
  String get gateUnreachableTitle => 'تعذّر الوصول إلى خدمة اللعبة';

  @override
  String get gateUnreachableMessage =>
      'يحتاج لودو رويال إلى اتصال بالإنترنت للعب عبر الشبكة. تحقّق من شبكة Wi-Fi أو بيانات الجوال وحاول مرة أخرى.';

  @override
  String get gateUnreachableLastKnownMaintenance =>
      'آخر حالة وصلتنا أشارت إلى أن الخوادم قيد الصيانة.';

  @override
  String get gateUnreachableLastKnownUpdate =>
      'آخر حالة وصلتنا أشارت إلى أن هذا الإصدار يحتاج إلى تحديث.';

  @override
  String get gateNotFoundTitle => 'غير متاح بعد';

  @override
  String get gateNotFoundMessage =>
      'هذا الجزء من لودو رويال غير متاح في هذا الإصدار بعد.';

  @override
  String get gateGoHome => 'العودة إلى الرئيسية';

  @override
  String homeGreeting(String name) {
    return 'مرحبًا، $name';
  }

  @override
  String get homeQuickPlay => 'لعب سريع';

  @override
  String homeQuickPlayDetails(String game, String variant, String players) {
    return '$game · $variant · $players';
  }

  @override
  String get homePrivateRoom => 'غرفة خاصة';

  @override
  String get homePrivateRoomSubtitle => 'أنشئ غرفة لأصدقائك';

  @override
  String get homeJoinWithCode => 'انضم برمز';

  @override
  String get homeJoinWithCodeSubtitle => 'أدخل رمز الغرفة';

  @override
  String get homePlayOnline => 'العب أونلاين';

  @override
  String get homePlayWithFriends => 'العب مع الأصدقاء';

  @override
  String get homePracticeVsBots => 'تدرّب ضد البوتات';

  @override
  String get homeLudoTagline => 'أوصل قطعك الأربع إلى البيت';

  @override
  String get homeSnakesTagline => 'اصعد السلالم وتجنّب الثعابين';

  @override
  String get homeMissions => 'المهام';

  @override
  String get homeMissionsSubtitle => 'أهداف يومية وأسبوعية';

  @override
  String get homeCollection => 'المجموعة';

  @override
  String get homeCollectionSubtitle => 'نرد وقطع وإطارات';

  @override
  String get homeFriends => 'الأصدقاء';

  @override
  String get homeFriendsSubtitle => 'العب مع رفاقك';

  @override
  String get homeEvents => 'الفعاليات';

  @override
  String get homeEventsSubtitle => 'كؤوس لفترة محدودة';

  @override
  String get homeStore => 'المتجر';

  @override
  String get homeStoreSubtitle => 'صور الملف الشخصي';

  @override
  String get homeExploreHeader => 'استكشف المزيد';

  @override
  String get homeGamesHeader => 'اختر لعبة';

  @override
  String get homeSaveProgressTooltip => 'احفظ التقدّم';

  @override
  String get homeProfileTooltip => 'الملف الشخصي';

  @override
  String get homeSettingsTooltip => 'الإعدادات';

  @override
  String get homeThemeTooltip => 'تبديل المظهر الفاتح/الداكن';

  @override
  String get homeWalletTooltip => 'المحفظة';

  @override
  String homeOptionsOnlineTitle(String game) {
    return '$game أونلاين';
  }

  @override
  String homeOptionsFriendsTitle(String game) {
    return '$game مع الأصدقاء';
  }

  @override
  String homeOptionsPracticeTitle(String game) {
    return 'تدرّب على $game';
  }

  @override
  String get homeOptionsPrivateRoomTitle => 'إنشاء غرفة خاصة';

  @override
  String get homeGameLabel => 'اللعبة';

  @override
  String get homePlayersLabel => 'اللاعبون';

  @override
  String get homeModeLabel => 'النمط';

  @override
  String get homeBotsLabel => 'البوتات';

  @override
  String get homeModeClassicCaption => 'القواعد الكاملة';

  @override
  String get homeModeQuickCaption => 'مباريات أقصر';

  @override
  String homeBotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بوت',
      many: '$count بوتًا',
      few: '$count بوتات',
      two: 'بوتان',
      one: 'بوت واحد',
    );
    return '$_temp0';
  }

  @override
  String get homeFindMatch => 'ابحث عن مباراة';

  @override
  String get homeCreateRoom => 'أنشئ غرفة';

  @override
  String get homeStartPractice => 'ابدأ التدريب';

  @override
  String get homeHaveACode => 'لديك رمز؟ انضم إلى غرفة';

  @override
  String homeEntryFeeNote(String fee) {
    return 'رسوم الدخول $fee عملة · الفائز يأخذ الحصيلة';
  }

  @override
  String get homePracticeNote =>
      'التدريب مجاني: بلا عملات، لكنك تكسب الخبرة وتتقدّم في المهام.';

  @override
  String homeNotEnoughCoins(String fee) {
    return 'تحتاج إلى $fee عملة على الأقل لهذه المباراة.';
  }

  @override
  String get homeJoinCodeTitle => 'انضم إلى غرفة خاصة';

  @override
  String get homeJoinCodeLabel => 'رمز الغرفة';

  @override
  String get homeJoinCodeHelper => 'اطلب من المضيف الرمز المكوّن من 6 خانات.';

  @override
  String get homeJoinCodeInvalid => 'يتكوّن رمز الغرفة من 6 أحرف أو أرقام.';

  @override
  String get homeJoinCodeAction => 'انضم إلى الغرفة';

  @override
  String homeLevelUpToast(int level) {
    return 'ارتقيت! وصلت إلى المستوى $level.';
  }

  @override
  String homeCoinsGainedToast(String amount) {
    return '+$amount عملة';
  }

  @override
  String get homeQuickPlaySubtitle => 'اعثر على لاعبين عشوائيين وابدأ الآن';

  @override
  String get homePlayNow => 'العب الآن';

  @override
  String get homeQuickLudo => 'لودو سريع';

  @override
  String get homeChangeGameHint => 'تغيير اللعبة';

  @override
  String get homeChangePlayersHint => 'تغيير عدد اللاعبين';

  @override
  String get homeGamesSubtitle =>
      'اختر لعبة، ثم العب عبر الإنترنت أو مع الأصدقاء أو ضد الروبوتات.';

  @override
  String get homeNavHome => 'الرئيسية';

  @override
  String get homeNavGames => 'الألعاب';

  @override
  String get homeNavMissions => 'المهام';

  @override
  String get homeNavFriends => 'الأصدقاء';

  @override
  String get homeNavProfile => 'ملفي';

  @override
  String get metaMissionsTitle => 'المهام';

  @override
  String get metaEventsTitle => 'الفعاليات';

  @override
  String get metaCollectionTitle => 'غرفة المجموعة';

  @override
  String get metaFriendsTitle => 'الأصدقاء';

  @override
  String get metaLeaderboardTitle => 'ترتيب الأسبوع';

  @override
  String get metaLevelRoadTitle => 'طريق المستويات';

  @override
  String get metaDailyTitle => 'المهام اليومية';

  @override
  String get metaWeeklyTitle => 'التحدي الأسبوعي';

  @override
  String get metaClaim => 'استلام';

  @override
  String get metaStatusInProgress => 'قيد التقدم';

  @override
  String get metaStatusReady => 'جاهزة للاستلام';

  @override
  String get metaStatusClaimed => 'تم الاستلام';

  @override
  String get metaCollected => 'تم استلام المكافأة — أُضيفت إلى حسابك';

  @override
  String metaProgressCount(String progress, String target) {
    return '$progress / $target';
  }

  @override
  String metaMissionSemantics(String title, String progress, String state) {
    return '$title. التقدم $progress. $state';
  }

  @override
  String metaRewardAmount(String amount) {
    return '+$amount';
  }

  @override
  String metaRewardXp(String amount) {
    return '+$amount خبرة';
  }

  @override
  String metaRewardCoinsLabel(String amount) {
    return '$amount عملة';
  }

  @override
  String metaRewardDiamondsLabel(String amount) {
    return '$amount ماسة';
  }

  @override
  String metaRewardXpLabel(String amount) {
    return '$amount نقطة خبرة';
  }

  @override
  String metaRewardItemLabel(String name, String kind) {
    return '$name ($kind)';
  }

  @override
  String get metaGameAny => 'أي لعبة';

  @override
  String metaResetsDailyAt(String time) {
    return 'مهام جديدة الساعة $time';
  }

  @override
  String metaResetsWeeklyAt(String day, String time) {
    return 'يُعاد ضبطه $day الساعة $time';
  }

  @override
  String metaEventEndsAt(String date) {
    return 'ينتهي $date';
  }

  @override
  String metaWhenWithCountdown(String when, String duration) {
    return '$when · بعد $duration';
  }

  @override
  String metaDurationDaysHours(int days, int hours) {
    return '$days ي $hours س';
  }

  @override
  String metaDurationHoursMinutes(int hours, int minutes) {
    return '$hours س $minutes د';
  }

  @override
  String metaDurationMinutes(int minutes) {
    return '$minutes د';
  }

  @override
  String get metaNoPenaltyNote =>
      'فاتك يوم؟ لا مشكلة — تبقى خبرتك ومستواك ومجموعتك محفوظة دائمًا.';

  @override
  String get metaMissionsEmptyTitle => 'لا توجد مهام الآن';

  @override
  String get metaMissionsEmptyMessage =>
      'تصل مهام يومية جديدة كل يوم. اسحب للأسفل للتحديث.';

  @override
  String metaRetryHint(String message) {
    return '$message اضغط مرة أخرى لإعادة المحاولة.';
  }

  @override
  String get metaNewItemsTitle => 'جديد في مجموعتك!';

  @override
  String metaNewItemsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'هذه العناصر الـ$count أصبحت لك الآن، جهّزها واستمتع بها.',
      many: 'هذه العناصر الـ$count أصبحت لك الآن، جهّزها واستمتع بها.',
      few: 'هذه العناصر الـ$count أصبحت لك الآن، جهّزها واستمتع بها.',
      two: 'هذان العنصران أصبحا لك الآن، جهّزهما واستمتع بهما.',
      one: 'هذا العنصر أصبح لك الآن، جهّزه واستمتع به.',
    );
    return '$_temp0';
  }

  @override
  String get metaNice => 'رائع!';

  @override
  String get metaViewCollection => 'عرض المجموعة';

  @override
  String get metaEventDetails => 'التفاصيل';

  @override
  String get metaMissionLudoTimeTitle => 'وقت اللودو';

  @override
  String get metaMissionClimbTitle => 'اصعد السلم';

  @override
  String get metaMissionWarmUpTitle => 'إحماء';

  @override
  String get metaMissionFriendlyTableTitle => 'طاولة الأصدقاء';

  @override
  String get metaMissionStayToEndTitle => 'حتى النهاية';

  @override
  String get metaMissionTasteOfVictoryTitle => 'طعم الفوز';

  @override
  String get metaMissionQuickDrawTitle => 'حركة سريعة';

  @override
  String get metaMissionWeeklyChallengeTitle => 'التحدي الأسبوعي';

  @override
  String get metaMissionAutumnSprintTitle => 'سباق الخريف';

  @override
  String get metaMissionFallbackTitle => 'مهمة';

  @override
  String metaMissionLudoMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أكمل $count مباراة لودو.',
      many: 'أكمل $count مباراة لودو.',
      few: 'أكمل $count مباريات لودو.',
      two: 'أكمل مباراتَي لودو.',
      one: 'أكمل مباراة لودو واحدة.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionSnakesMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أكمل $count مباراة في السلم والثعبان.',
      many: 'أكمل $count مباراة في السلم والثعبان.',
      few: 'أكمل $count مباريات في السلم والثعبان.',
      two: 'أكمل مباراتين في السلم والثعبان.',
      one: 'أكمل مباراة واحدة في السلم والثعبان.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionAnyMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أكمل $count مباراة في أي لعبة.',
      many: 'أكمل $count مباراة في أي لعبة.',
      few: 'أكمل $count مباريات في أي لعبة.',
      two: 'أكمل مباراتين في أي لعبة.',
      one: 'أكمل مباراة واحدة في أي لعبة.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionFriendPrivateDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أكمل $count مباراة خاصة مع أصدقائك.',
      many: 'أكمل $count مباراة خاصة مع أصدقائك.',
      few: 'أكمل $count مباريات خاصة مع أصدقائك.',
      two: 'أكمل مباراتين خاصتين مع أصدقائك.',
      one: 'أكمل مباراة خاصة مع صديق.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionNoLeavingDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أكمل $count مباراة دون المغادرة مبكرًا.',
      many: 'أكمل $count مباراة دون المغادرة مبكرًا.',
      few: 'أكمل $count مباريات دون المغادرة مبكرًا.',
      two: 'أكمل مباراتين دون المغادرة مبكرًا.',
      one: 'أكمل مباراة دون المغادرة مبكرًا.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionWinDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'افز بـ$count مباراة.',
      many: 'افز بـ$count مباراة.',
      few: 'افز بـ$count مباريات.',
      two: 'افز بمباراتين.',
      one: 'افز بمباراة واحدة.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionQuickLudoDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أكمل $count مباراة لودو سريع.',
      many: 'أكمل $count مباراة لودو سريع.',
      few: 'أكمل $count مباريات لودو سريع.',
      two: 'أكمل مباراتَي لودو سريع.',
      one: 'أكمل مباراة لودو سريع واحدة.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionWeeklyDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أكمل $count مباراة في لودو والسلم والثعبان.',
      many: 'أكمل $count مباراة في لودو والسلم والثعبان.',
      few: 'أكمل $count مباريات في لودو والسلم والثعبان.',
      two: 'أكمل مباراتين في لودو والسلم والثعبان.',
      one: 'أكمل مباراة واحدة في لودو أو السلم والثعبان.',
    );
    return '$_temp0';
  }

  @override
  String get metaEventAutumnCupTitle => 'كأس الخريف';

  @override
  String get metaEventAutumnCupDesc =>
      'احتفل بالموسم مع لودو السريع واربح نرد ورقة الخريف.';

  @override
  String metaEventWindow(String start, String end) {
    return '$start – $end';
  }

  @override
  String get metaEventLiveBadge => 'فعالية جارية';

  @override
  String get metaEventMissionsTitle => 'مهام الفعالية';

  @override
  String get metaEventRulesTitle => 'كيف تعمل';

  @override
  String get metaEventRuleComplete => 'أكمل مهام الفعالية أثناء فترة الفعالية.';

  @override
  String get metaEventRuleEligible =>
      'تُحتسب المباراة عندما تلعبها حتى النهاية وتقوم بـ3 حركات على الأقل وتستمر 30 ثانية على الأقل.';

  @override
  String get metaEventRuleClaim =>
      'استلم كل مكافأة هنا — تُضاف إلى حسابك فورًا.';

  @override
  String get metaEventRuleEnd =>
      'المكافآت غير المستلمة قبل انتهاء الفعالية لا تعود متاحة. لا تتأثر خبرتك ومستواك ومجموعتك أبدًا.';

  @override
  String get metaNoEventsTitle => 'لا توجد فعاليات الآن';

  @override
  String get metaNoEventsMessage =>
      'ستظهر الفعاليات الجديدة هنا. مهامك اليومية متاحة دائمًا.';

  @override
  String get metaGoToMissions => 'الذهاب إلى المهام';

  @override
  String metaXpToNextLevel(String xp, int level) {
    return '$xp خبرة للوصول إلى المستوى $level';
  }

  @override
  String get metaMaxLevelReached =>
      'وصلت إلى أعلى مستوى — تظل الخبرة محسوبة في ترتيب الأسبوع';

  @override
  String get metaMaxBadge => 'الأقصى';

  @override
  String metaTotalXp(String xp) {
    return 'إجمالي الخبرة: $xp';
  }

  @override
  String get metaHowToEarnXp => 'كيف تكسب الخبرة';

  @override
  String metaXpForMatch(int xp) {
    return '+$xp خبرة لكل مباراة مكتملة';
  }

  @override
  String metaXpForWin(int xp) {
    return 'مكافأة +$xp خبرة عند الفوز';
  }

  @override
  String metaXpForFriend(int xp) {
    return '+$xp خبرة عند اللعب مع صديق';
  }

  @override
  String get metaXpForMissions => 'مكافآت المهام تتضمن الخبرة أيضًا';

  @override
  String get metaXpFairPlayNote =>
      'تُحتسب المباريات عند لعبها حتى النهاية (3 حركات و30 ثانية على الأقل). لا يكسب الروبوت خبرة أبدًا.';

  @override
  String get metaMilestonesTitle => 'المحطات';

  @override
  String get metaMilestoneUnlocked => 'مفتوح';

  @override
  String metaMilestoneNext(String xp) {
    return 'المحطة التالية · بقي $xp خبرة';
  }

  @override
  String metaMilestoneLocked(String xp) {
    return 'بقي $xp خبرة';
  }

  @override
  String get metaNoMilestones => 'ستظهر المحطات هنا.';

  @override
  String get metaLevelUpTitle => 'ارتقيت!';

  @override
  String metaLevelUpMessage(int level) {
    return 'وصلت إلى المستوى $level.';
  }

  @override
  String get metaUnlockedHeader => 'فُتح لك';

  @override
  String get metaLevelUpContinue => 'رائع!';

  @override
  String get metaYourLook => 'مظهرك';

  @override
  String metaCollectedCount(String owned, String total) {
    return 'جمعت $owned من $total';
  }

  @override
  String get metaTabDice => 'النرد';

  @override
  String get metaTabTokens => 'البيادق';

  @override
  String get metaTabLudoBoards => 'ألواح لودو';

  @override
  String get metaTabSnakesBoards => 'ألواح السلم والثعبان';

  @override
  String get metaTabTrails => 'المسارات';

  @override
  String get metaTabVictory => 'احتفالات الفوز';

  @override
  String get metaTabFrames => 'الإطارات';

  @override
  String get metaTabTitles => 'الألقاب';

  @override
  String get metaTabBadges => 'الشارات';

  @override
  String get metaTabEmotes => 'التعبيرات';

  @override
  String get metaFilterAll => 'الكل';

  @override
  String get metaFilterOwned => 'المملوكة';

  @override
  String get metaFilterLocked => 'للفتح';

  @override
  String get metaEquipped => 'مُجهَّز';

  @override
  String get metaOwned => 'مملوك';

  @override
  String get metaLocked => 'مقفل';

  @override
  String get metaNewBadge => 'جديد';

  @override
  String metaItemSemantics(
    String name,
    String rarity,
    String state,
    String how,
  ) {
    return '$name، $rarity، $state. $how';
  }

  @override
  String get metaAcqStarter => 'عنصر البداية';

  @override
  String metaAcqLevel(int level) {
    return 'صِل إلى المستوى $level';
  }

  @override
  String get metaAcqMission => 'مكافأة مهمة';

  @override
  String get metaAcqWeeklyChallenge => 'مكافأة التحدي الأسبوعي';

  @override
  String get metaAcqFirstWin => 'افز بمباراتك الأولى';

  @override
  String get metaAcqEvent => 'مكافأة فعالية';

  @override
  String get metaAcqAutumnCup => 'مكافأة كأس الخريف';

  @override
  String metaPriceCoins(String amount) {
    return '$amount عملة';
  }

  @override
  String metaPriceDiamonds(String amount) {
    return '$amount ماسة';
  }

  @override
  String get metaEquip => 'تجهيز';

  @override
  String get metaEquipDefault => 'استخدام الافتراضي';

  @override
  String get metaEquippedToast => 'تم التجهيز!';

  @override
  String get metaDefaultEquippedToast => 'عدت إلى المظهر الافتراضي';

  @override
  String get metaEmoteHint =>
      'استخدم تعبيراتك أثناء المباريات من زر التعبيرات.';

  @override
  String get metaBadgeHint => 'الشارات احتفاء بإنجازاتك، وهي لك دائمًا.';

  @override
  String metaBuyFor(String price) {
    return 'اشترِ مقابل $price';
  }

  @override
  String get metaBuy => 'شراء';

  @override
  String metaPurchaseTitle(String item) {
    return 'هل تشتري $item؟';
  }

  @override
  String get metaPrice => 'السعر';

  @override
  String get metaYourBalance => 'رصيدك';

  @override
  String get metaBalanceAfter => 'بعد الشراء';

  @override
  String metaNeedMore(String amount) {
    return 'تحتاج إلى $amount إضافية. افز بالمباريات وأكمل المهام لتكسب المزيد.';
  }

  @override
  String get metaCosmeticOnlyNote =>
      'للمظهر فقط — لا يغيّر النرد أو القواعد أو المطابقة أبدًا.';

  @override
  String metaPurchaseSuccess(String item) {
    return '$item أصبح الآن في مجموعتك!';
  }

  @override
  String get metaNotEnoughCoins => 'لا تكفي عملاتك لهذا العنصر.';

  @override
  String get metaNotEnoughDiamonds => 'لا تكفي ماساتك لهذا العنصر.';

  @override
  String get metaAlreadyOwned => 'أنت تملك هذا العنصر بالفعل.';

  @override
  String get metaItemNotForSale => 'يُفتح هذا العنصر باللعب، ولا يُشترى.';

  @override
  String metaUnlocksAtLevel(int level) {
    return 'يُفتح تلقائيًا عند وصولك إلى المستوى $level.';
  }

  @override
  String get metaEarnFromMissionsHint =>
      'احصل عليه بإكمال المهمة أو الفعالية المرتبطة — دون أي شراء.';

  @override
  String get metaAllOwnedInKind => 'لقد فتحت كل شيء هنا. أحسنت!';

  @override
  String get metaNothingOwnedInKind =>
      'لا شيء هنا بعد — واصل اللعب لفتح المزيد.';

  @override
  String get metaCollectionFairNote =>
      'كل عنصر للمظهر فقط وطريقة الحصول عليه ثابتة — بلا صناديق عشوائية ولا أفضلية في اللعب.';

  @override
  String get metaDescDiceClassic => 'نرد عاجي خالد بنقاط سوداء واضحة.';

  @override
  String get metaDescDiceNeon => 'نرد متوهج ينبض مع كل رمية.';

  @override
  String get metaDescDiceGolden => 'نرد ذهبي لامع يليق بالملوك.';

  @override
  String get metaDescDiceAutumn => 'نرد كهرماني دافئ من كأس الخريف.';

  @override
  String get metaDescTokenClassic => 'البيدق الذي يعرفه الجميع.';

  @override
  String get metaDescTokenGem => 'بيادق من الأحجار الكريمة تلتقط الضوء.';

  @override
  String get metaDescTokenRoyal => 'بيادق ترتدي تيجانًا صغيرة.';

  @override
  String get metaDescTokenCrown => 'قطعة أسطورية على شكل تاج.';

  @override
  String get metaDescLudoBoardClassic => 'لوح لودو التقليدي بأربعة ألوان.';

  @override
  String get metaDescLudoBoardMidnight => 'رخام داكن مطعّم بالفضة.';

  @override
  String get metaDescLudoBoardRoyal => 'فناء قصر بالذهبي والقرمزي.';

  @override
  String get metaDescSnakesBoardClassic =>
      'مروج خضراء، ثعابين ودودة، وسلالم متينة.';

  @override
  String get metaDescSnakesBoardJungle => 'كروم وأطلال ودرجات معبد.';

  @override
  String get metaDescSnakesBoardCandy =>
      'ثعابين من حلوى العرقسوس وسلالم من عصي الحلوى.';

  @override
  String get metaDescTrailNone => 'حركات نظيفة بلا أثر.';

  @override
  String get metaDescTrailSparkle => 'وابل من البريق يتبع كل حركة.';

  @override
  String get metaDescTrailComet => 'ذيل مذنّب متوهج.';

  @override
  String get metaDescVictoryConfetti =>
      'احتفال كلاسيكي بقصاصات الورق الملوّنة.';

  @override
  String get metaDescVictoryFireworks => 'أضئ السماء عندما تفوز.';

  @override
  String get metaDescVictoryCrown => 'تاج ذهبي يهبط على الفائز.';

  @override
  String get metaDescFrameNone => 'صورتك الرمزية بلا إطار.';

  @override
  String get metaDescFrameBronze => 'حلقة برونزية بسيطة حول صورتك الرمزية.';

  @override
  String get metaDescFrameSilver => 'إكليل غار فضي.';

  @override
  String get metaDescFrameGold => 'إكليل غار ذهبي للاعبين المخضرمين.';

  @override
  String get metaDescFrameRoyal => 'شعار ملكي مزخرف.';

  @override
  String get metaDescTitleRookie => 'الجميع يبدأ من مكان ما.';

  @override
  String get metaDescTitleStrategist => 'للاعبين الذين يفكرون قبل ثلاث خطوات.';

  @override
  String get metaDescTitleDiceMaster => 'يبدو أن النرد يصغي إليك.';

  @override
  String get metaDescTitleRoyal => 'مخصص للملوك الحقيقيين.';

  @override
  String get metaDescTitleWeeklyChampion => 'أكملت تحديًا أسبوعيًا.';

  @override
  String get metaDescBadgeFirstWin => 'فزت بمباراتك الأولى.';

  @override
  String get metaDescBadgeFriendly => 'أكملت تحديًا أسبوعيًا.';

  @override
  String get metaDescEmoteWave => 'قل مرحبًا.';

  @override
  String get metaDescEmoteThumbs => 'أحسنت!';

  @override
  String get metaDescEmoteLaugh => 'شارك ضحكة.';

  @override
  String get metaDescEmoteWow => 'هل حدث ذلك حقًا؟';

  @override
  String get metaDescEmoteCrown => 'أظهر من يحكم اللوح.';

  @override
  String get metaYourFriendCode => 'رمز صداقتك';

  @override
  String get metaFriendCodeHint => 'شاركه ليتمكن أصدقاؤك من إضافتك.';

  @override
  String metaFriendCodeSemantics(String code) {
    return 'رمز الصداقة: $code';
  }

  @override
  String metaShareFriendCodeMessage(String code) {
    return 'لنلعب لودو رويال معًا! أضفني صديقًا برمزي: $code';
  }

  @override
  String get metaAddFriend => 'إضافة صديق';

  @override
  String get metaAdd => 'إضافة';

  @override
  String get metaAddFriendTitle => 'أضف صديقًا';

  @override
  String get metaAddFriendHelp =>
      'أدخل رمز صديقك. يمكنه إيجاده في شاشة الأصدقاء لديه.';

  @override
  String get metaFriendCodeLabel => 'رمز الصداقة';

  @override
  String get metaFriendCodeHintExample => 'u_abcd 2345 wxyz';

  @override
  String get metaPaste => 'لصق';

  @override
  String get metaSendRequest => 'إرسال الطلب';

  @override
  String get metaFriendCodeRequired => 'أدخل رمز الصداقة.';

  @override
  String get metaInvalidFriendCode =>
      'لا يبدو هذا رمز صداقة. يبدأ الرمز بـ u_ تليه حروف وأرقام.';

  @override
  String metaRequestSent(String name) {
    return 'تم إرسال طلب الصداقة إلى $name';
  }

  @override
  String metaNowFriends(String name) {
    return 'أنت و$name صديقان الآن!';
  }

  @override
  String get metaAlreadyFriends => 'أنتما صديقان بالفعل.';

  @override
  String get metaTabFriends => 'الأصدقاء';

  @override
  String get metaTabRequests => 'الطلبات';

  @override
  String get metaTabRecent => 'الأخيرون';

  @override
  String get metaOnline => 'متصل';

  @override
  String get metaOffline => 'غير متصل';

  @override
  String get metaMoreActions => 'إجراءات أخرى';

  @override
  String get metaRemoveFriend => 'إزالة الصديق';

  @override
  String metaRemoveFriendTitle(String name) {
    return 'هل تزيل $name؟';
  }

  @override
  String get metaRemoveFriendMessage =>
      'يمكنكما إضافة بعضكما مجددًا في أي وقت برمز الصداقة.';

  @override
  String get metaRemove => 'إزالة';

  @override
  String metaFriendRemoved(String name) {
    return 'تمت إزالة $name من أصدقائك';
  }

  @override
  String get metaIncomingRequests => 'الواردة';

  @override
  String get metaOutgoingRequests => 'المُرسلة';

  @override
  String get metaWantsToBeFriends => 'يريد أن يكون صديقك';

  @override
  String get metaRequestPending => 'بانتظار الرد';

  @override
  String get metaAccept => 'قبول';

  @override
  String get metaDecline => 'رفض';

  @override
  String get metaRequestDeclined => 'تم رفض الطلب';

  @override
  String get metaRequestCancelled => 'تم إلغاء الطلب';

  @override
  String get metaRequested => 'تم الطلب';

  @override
  String get metaFriendsLabel => 'أصدقاء';

  @override
  String get metaNoFriendsTitle => 'لا أصدقاء بعد';

  @override
  String get metaNoFriendsMessage => 'شارك رمزك أو أضف صديقًا لتلعبا معًا.';

  @override
  String get metaNoRequestsTitle => 'لا توجد طلبات معلّقة';

  @override
  String get metaNoRequestsMessage =>
      'تظهر هنا طلبات الصداقة التي ترسلها أو تستقبلها.';

  @override
  String get metaRecentHint =>
      'لاعبون التقيتهم في مباريات عبر الإنترنت خلال آخر 14 يومًا.';

  @override
  String get metaNoRecentTitle => 'لا منافسين مؤخرًا';

  @override
  String get metaNoRecentMessage =>
      'العب مباراة عبر الإنترنت — سيظهر هنا اللاعبون الذين تلتقيهم.';

  @override
  String metaFriendRequestBanner(String name) {
    return '$name يريد أن يكون صديقك';
  }

  @override
  String get metaView => 'عرض';

  @override
  String get metaErrorCannotFriendSelf => 'هذا رمز صداقتك أنت.';

  @override
  String metaErrorFriendLimit(int max) {
    return 'يمكنك امتلاك $max صديقًا كحد أقصى. أزل صديقًا لإضافة شخص جديد.';
  }

  @override
  String get metaErrorUnknownFriendCode =>
      'لا يوجد لاعب بهذا الرمز. تحقق منه وحاول مجددًا.';

  @override
  String get metaErrorRequestInProgress =>
      'لا يزال الطلب قيد المعالجة — حاول مجددًا بعد قليل.';

  @override
  String get metaErrorMissionEnded =>
      'انتهت هذه المهمة. اسحب للأسفل لرؤية المهام الحالية.';

  @override
  String get metaLeaderboardSubtitle =>
      'أنت وأصدقاؤك، مرتبون حسب الخبرة المكتسبة هذا الأسبوع.';

  @override
  String get metaLeaderboardTeaser => 'شاهد أداءك وأداء أصدقائك هذا الأسبوع.';

  @override
  String metaWeeklyXp(String xp) {
    return '$xp خبرة';
  }

  @override
  String metaYouName(String name) {
    return '$name (أنت)';
  }

  @override
  String metaLeaderboardRowSemantics(int rank, String name, String xp) {
    return 'المرتبة $rank: $name، $xp';
  }

  @override
  String get metaLeaderboardAlone =>
      'أضف أصدقاء لترى المقارنة. منافسة ودية بلا ضغط.';

  @override
  String numberLakh(String value) {
    return '$value لك';
  }

  @override
  String numberCrore(String value) {
    return '$value كرور';
  }

  @override
  String get onboardingLanguageTitle => 'اختر لغتك';

  @override
  String get onboardingLanguageSubtitle =>
      'يمكنك تغييرها في أي وقت من الإعدادات.';

  @override
  String get onboardingPreviewLabel => 'معاينة';

  @override
  String get onboardingPreviewTitle => 'مرحبًا بك في لودو رويال!';

  @override
  String get onboardingPreviewBody =>
      'ارمِ النرد، وأوصل قطعك إلى البيت، واظفر بالتاج.';

  @override
  String playGameVariantTitle(String game, String variant) {
    return '$game · $variant';
  }

  @override
  String get playModeOnline => 'عبر الإنترنت';

  @override
  String get playModePrivate => 'غرفة خاصة';

  @override
  String get playModePractice => 'تدريب';

  @override
  String playSeatPlayer(int seat) {
    return 'اللاعب $seat';
  }

  @override
  String playNameYou(String name) {
    return '$name (أنت)';
  }

  @override
  String get playHome => 'الرئيسية';

  @override
  String get playBackHome => 'العودة إلى الرئيسية';

  @override
  String get playTryAgain => 'حاول مرة أخرى';

  @override
  String playEntryFee(String fee) {
    return 'الدخول $fee';
  }

  @override
  String playEntryFeeNote(String fee) {
    return 'رسوم الدخول: $fee عملة لكل لاعب، تُخصم عند بدء اللعبة. يحصل الفائز على كامل المجموع. مجانية عند وجود بوت.';
  }

  @override
  String get playNotEnoughCoinsTitle => 'العملات غير كافية';

  @override
  String playNotEnoughCoinsHint(String fee) {
    return 'تحتاج إلى $fee عملة للعب. اربح العملات من المهام ثم عُد!';
  }

  @override
  String get playSeatOpen => 'مقعد شاغر';

  @override
  String get playLoadingMatch => 'جارٍ الانضمام إلى المباراة…';

  @override
  String get playMatchUnavailable => 'هذه المباراة لم تعد متاحة.';

  @override
  String get playRoomClosed => 'تم إغلاق الغرفة.';

  @override
  String get playRemovedFromRoom => 'لم تعد في هذه الغرفة.';

  @override
  String get playRoomUnavailable => 'هذه الغرفة لم تعد متاحة.';

  @override
  String get playLoadingRoom => 'جارٍ فتح الغرفة…';

  @override
  String get playGameLabel => 'اللعبة';

  @override
  String get playModeLabel => 'القواعد';

  @override
  String get playPlayersLabel => 'اللاعبون';

  @override
  String get playVariantClassicCaption => '4 قطع · الخروج من القاعدة بالرقم 6';

  @override
  String get playVariantQuickCaption =>
      'قطعتان · الخروج من القاعدة بالرقم 1 أو 6';

  @override
  String get playMatchmakingTitle => 'البحث عن لاعبين';

  @override
  String get playMatchmakingConnecting => 'جارٍ الاتصال بخادم اللعبة…';

  @override
  String get playMatchmakingJoining => 'جارٍ الانضمام إلى قائمة الانتظار…';

  @override
  String get playMatchmakingSearching => 'جارٍ البحث عن منافسين…';

  @override
  String get playMatchmakingStarting => 'اكتملت الطاولة! جارٍ البدء…';

  @override
  String get playMatchmakingStartsSoon =>
      'تبدأ المباراة عند امتلاء كل المقاعد أو انتهاء المؤقت.';

  @override
  String get playMatchmakingStartsWhenFull =>
      'تبدأ المباراة فور امتلاء كل المقاعد.';

  @override
  String playMatchmakingPlayers(int count, int capacity) {
    return 'اللاعبون المنضمون: $count من $capacity';
  }

  @override
  String get playMatchmakingCancel => 'إلغاء البحث';

  @override
  String get playMatchmakingFeeNote =>
      'تُخصم رسوم الدخول عند بدء المباراة. يحصل الفائز على كامل المجموع.';

  @override
  String get playMatchmakingTimeoutTitle => 'لا يوجد منافسون الآن';

  @override
  String get playMatchmakingTimeoutMessage =>
      'لم ينضم أحد في الوقت المحدد. حاول مرة أخرى أو ادعُ أصدقاءك إلى غرفة خاصة.';

  @override
  String get playMatchmakingErrorTitle => 'تعذّر العثور على مباراة';

  @override
  String get playCreateRoomTitle => 'إنشاء غرفة خاصة';

  @override
  String get playCreateRoomAction => 'إنشاء الغرفة';

  @override
  String get playCreatingRoom => 'جارٍ إنشاء غرفتك…';

  @override
  String get playLobbyTitle => 'غرفة خاصة';

  @override
  String get playRoomCodeLabel => 'رمز الغرفة';

  @override
  String playRoomCodeA11y(String letters) {
    return 'رمز الغرفة $letters';
  }

  @override
  String get playCopyCode => 'نسخ الرمز';

  @override
  String get playCodeCopied => 'تم نسخ رمز الغرفة';

  @override
  String get playShareInvite => 'مشاركة الدعوة';

  @override
  String playInviteShareText(String game, String code) {
    return 'انضم إليّ للعب $game في Ludo Royale! افتح التطبيق، واضغط على «انضم برمز» وأدخل: $code';
  }

  @override
  String get playInviteShareSubject => 'دعوة إلى Ludo Royale';

  @override
  String playLobbyPlayers(int count, int capacity) {
    return 'اللاعبون $count/$capacity';
  }

  @override
  String get playLobbyStart => 'ابدأ اللعبة';

  @override
  String get playLobbyWaitingForHost => 'بانتظار أن يبدأ المضيف…';

  @override
  String playLobbyWaitingForNamedHost(String name) {
    return 'بانتظار أن يبدأ $name (المضيف)…';
  }

  @override
  String get playStartBlockedNeedPlayers => 'يلزم لاعبان على الأقل للبدء.';

  @override
  String get playStartBlockedConnections => 'بانتظار إعادة اتصال الجميع.';

  @override
  String get playStartBlockedBots => 'البوتات تأخذ مقاعدها…';

  @override
  String get playAllowBots => 'السماح بالبوتات';

  @override
  String get playAllowBotsHint =>
      'املأ المقاعد الشاغرة بلاعبين آليين. المباريات مع البوتات مجانية ولا تمنح عملات.';

  @override
  String get playAddBot => 'إضافة بوت';

  @override
  String get playBotJoining => 'البوت ينضم…';

  @override
  String playRemoveBotA11y(String name) {
    return 'إزالة $name';
  }

  @override
  String get playBotsFreeNote =>
      'يوجد بوت على الطاولة: هذه المباراة مجانية ولا تمنح عملات.';

  @override
  String get playInviteFriends => 'دعوة الأصدقاء';

  @override
  String get playInviteSheetTitle => 'دعوة الأصدقاء';

  @override
  String get playInviteSend => 'دعوة';

  @override
  String get playInviteSent => 'تمت الدعوة';

  @override
  String get playFriendOnline => 'متصل';

  @override
  String get playFriendOffline => 'غير متصل';

  @override
  String get playInviteEmptyTitle => 'لا يوجد أصدقاء بعد';

  @override
  String get playInviteEmptyMessage =>
      'شارك رمز الغرفة بدلًا من ذلك، أو أضف أصدقاء من شاشة الأصدقاء.';

  @override
  String get playInviteError => 'تعذّر تحميل أصدقائك.';

  @override
  String get playLeaveRoom => 'مغادرة الغرفة';

  @override
  String get playLeaveRoomTitle => 'مغادرة هذه الغرفة؟';

  @override
  String get playLeaveRoomHostMessage =>
      'أنت المضيف. سيصبح اللاعب التالي مضيفًا عند مغادرتك.';

  @override
  String get playLeaveRoomMessage =>
      'يمكنك العودة برمز الغرفة ما دامت الغرفة مفتوحة.';

  @override
  String get playStay => 'البقاء';

  @override
  String get playHostBadge => 'المضيف';

  @override
  String get playJoinTitle => 'انضم برمز';

  @override
  String get playJoinHint =>
      'أدخل رمز الغرفة المكوّن من 6 خانات الذي شاركه صديقك.';

  @override
  String playJoinCodeIncomplete(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'بقيت $remaining خانة',
      many: 'بقيت $remaining خانة',
      few: 'بقيت $remaining خانات',
      two: 'بقيت خانتان',
      one: 'بقيت خانة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get playJoinInvalidChars =>
      'تتكوّن رموز الغرف من الحروف A–Z والأرقام 2–9 (بدون I أو O أو 0 أو 1).';

  @override
  String get playJoinLookingUp => 'جارٍ البحث عن الغرفة…';

  @override
  String get playJoinAction => 'انضم إلى الغرفة';

  @override
  String get playJoining => 'جارٍ الانضمام…';

  @override
  String playJoinPreviewHost(String name) {
    return 'المضيف: $name';
  }

  @override
  String playJoinPreviewPlayers(int count, int capacity) {
    return 'اللاعبون $count/$capacity';
  }

  @override
  String get playJoinStatusOpen => 'مفتوحة';

  @override
  String get playJoinStatusFull => 'ممتلئة';

  @override
  String get playJoinStatusInProgress => 'قيد اللعب';

  @override
  String get playJoinStatusClosed => 'مغلقة';

  @override
  String get playPaste => 'لصق';

  @override
  String get playPracticeTitle => 'تدريب ضد البوتات';

  @override
  String get playPracticeBotsLabel => 'البوتات';

  @override
  String playPracticeBotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بوت',
      many: '$count بوتًا',
      few: '$count بوتات',
      two: 'بوتان',
      one: 'بوت واحد',
    );
    return '$_temp0';
  }

  @override
  String get playPracticeStart => 'ابدأ التدريب';

  @override
  String get playPracticeNote =>
      'التدريب مجاني ولا يمنح عملات. ستلعب ضد لاعبين آليين.';

  @override
  String get playPracticeSettingUp => 'جارٍ تجهيز طاولة التدريب…';

  @override
  String playPracticeBotsJoining(int seated, int total) {
    return 'البوتات تنضم… $seated/$total';
  }

  @override
  String get playPracticeBotsUnavailableTitle => 'البوتات مشغولة';

  @override
  String get playPracticeErrorTitle => 'تعذّر بدء التدريب';

  @override
  String get playLeave => 'مغادرة المباراة';

  @override
  String get playTurnYourRoll => 'دورك — اضغط على النرد!';

  @override
  String get playTurnPickToken => 'اختر قطعة متوهجة لتحريكها';

  @override
  String get playTurnYours => 'دورك';

  @override
  String playTurnOther(String name) {
    return 'دور $name';
  }

  @override
  String get playVoidedThreeSixes => 'ثلاث ستات متتالية! ينتقل الدور.';

  @override
  String playAutoPlayed(String name) {
    return 'انتهى الوقت — تم اللعب تلقائيًا عن $name';
  }

  @override
  String playForfeitLeft(String name) {
    return 'غادر $name المباراة';
  }

  @override
  String playForfeitTimeouts(String name) {
    return 'أُخرج $name بعد تفويت 3 أدوار';
  }

  @override
  String get playPlayerDisconnected => 'غير متصل';

  @override
  String get playPlayerForfeited => 'غادر';

  @override
  String get playPanelTurnA11y => 'الدور الحالي';

  @override
  String playStrikesA11y(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count دور فائت',
      many: '$count دورًا فائتًا',
      few: '$count أدوار فائتة',
      two: 'دوران فائتان',
      one: 'دور واحد فائت',
    );
    return '$_temp0';
  }

  @override
  String playTokensHome(int home, int total) {
    return '$home من $total قطع وصلت إلى المنزل';
  }

  @override
  String playSquare(int square) {
    return 'المربع $square';
  }

  @override
  String get playAtStart => 'عند البداية';

  @override
  String get playReconnecting => 'جارٍ إعادة الاتصال… مباراتك مستمرة';

  @override
  String get playSyncing => 'جارٍ مزامنة اللوحة…';

  @override
  String get playLeaveMatchTitle => 'مغادرة المباراة؟';

  @override
  String get playLeaveMatchMessage =>
      'تُحتسب المغادرة انسحابًا ولن تُستردّ رسوم الدخول.';

  @override
  String get playLeavePracticeMessage => 'ستنتهي لعبة التدريب.';

  @override
  String get playLeaveMatchConfirm => 'مغادرة';

  @override
  String get playKeepPlaying => 'متابعة اللعب';

  @override
  String playRoundLabel(int round) {
    return 'الجولة $round';
  }

  @override
  String get playStartingNextRound => 'جارٍ بدء الجولة التالية…';

  @override
  String get playChatOpen => 'الدردشة السريعة';

  @override
  String get playChatTitle => 'الدردشة السريعة';

  @override
  String get playChatEmotes => 'الوجوه التعبيرية';

  @override
  String get playChatMuteOthers => 'كتم اللاعبين الآخرين';

  @override
  String get playChatMutedBySettings => 'الدردشة السريعة مكتومة في الإعدادات.';

  @override
  String playChatCooldown(int seconds) {
    return 'الرسالة التالية بعد $seconds ث';
  }

  @override
  String get playChatGg => 'لعبة جميلة!';

  @override
  String get playChatNiceMove => 'حركة رائعة!';

  @override
  String get playChatWellPlayed => 'أحسنت اللعب!';

  @override
  String get playChatRematch => 'مباراة أخرى؟';

  @override
  String get playChatAgain => 'لنلعب مرة أخرى.';

  @override
  String get playChatGoodLuck => 'حظًا موفقًا!';

  @override
  String get playChatOops => 'أوه!';

  @override
  String get playChatThanks => 'شكرًا!';

  @override
  String get playResultYouWon => 'لقد فزت!';

  @override
  String playResultWinnerIs(String name) {
    return 'الفوز لـ $name!';
  }

  @override
  String get playResultGameOver => 'انتهت اللعبة';

  @override
  String get playResultYouForfeited => 'لقد غادرت المباراة';

  @override
  String get playResultByForfeit => 'انسحب الآخرون — الفوز من نصيبك.';

  @override
  String get playResultWellPlayed => 'أحسنت!';

  @override
  String playResultYouFinished(int place) {
    return 'أنهيت في المركز #$place';
  }

  @override
  String get playResultFinishingOrder => 'ترتيب الإنهاء';

  @override
  String playResultPlaceShort(int place) {
    return '$place';
  }

  @override
  String playResultPlaceA11y(int place) {
    return 'المركز $place';
  }

  @override
  String get playRewardsTitle => 'المكافآت';

  @override
  String playRewardCoins(String amount) {
    return '+$amount عملة';
  }

  @override
  String playRewardCoinsBalance(String amount) {
    return 'المحفظة: $amount عملة';
  }

  @override
  String get playRewardNoCoinsMatch => 'هذه المباراة لا تمنح عملات.';

  @override
  String get playRewardNoCoins =>
      'لا عملات هذه المرة — يحصل الفائز على كامل المجموع.';

  @override
  String playRewardXp(int xp) {
    return '+$xp XP';
  }

  @override
  String get playRewardXpPending => 'جارٍ حساب نقاط الخبرة…';

  @override
  String get playRewardXpLater => 'ستظهر نقاط خبرتك في ملفك الشخصي قريبًا.';

  @override
  String playRewardLevelUp(int level) {
    return 'ترقية! وصلت إلى المستوى $level';
  }

  @override
  String get playRewardUnlocked => 'تم فتحها';

  @override
  String get playRematchTitle => 'مباراة العودة';

  @override
  String get playRematchRequest => 'اطلب مباراة عودة';

  @override
  String get playRematchAccept => 'قبول';

  @override
  String get playRematchDecline => 'رفض';

  @override
  String playRematchIncoming(String name) {
    return 'يريد $name مباراة عودة!';
  }

  @override
  String get playRematchWaiting => 'أنت جاهز! بانتظار الآخرين…';

  @override
  String get playRematchYouDeclined => 'لقد رفضت مباراة العودة.';

  @override
  String get playRematchClosed => 'مباراة العودة لم تعد متاحة.';

  @override
  String get playRematchPublicNote =>
      'ينتقل اللاعبون الموافقون معًا إلى غرفة خاصة جديدة.';

  @override
  String get playRematchStatusAccepted => 'جاهز';

  @override
  String get playRematchStatusDeclined => 'رفض';

  @override
  String get playRematchStatusPending => 'يقرّر…';

  @override
  String get playRematchStatusOut => 'غادر';

  @override
  String playRematchSeatA11y(String name, String status) {
    return '$name: $status';
  }

  @override
  String get playPlayAgain => 'العب مرة أخرى';

  @override
  String playInviteIncoming(String name, String game) {
    return 'دعاك $name للعب $game';
  }

  @override
  String get playInviteJoin => 'انضمام';

  @override
  String get playInviteDismiss => 'ليس الآن';

  @override
  String get playInviteSomeone => 'صديق';

  @override
  String get profileTitle => 'الملف الشخصي';

  @override
  String get profileFriendCode => 'رمز الصداقة';

  @override
  String get profileFriendCodeHint => 'شاركه ليتمكن أصدقاؤك من إضافتك.';

  @override
  String profileShareFriendCode(String code) {
    return 'أضفني في لودو رويال! رمز صداقتي هو $code';
  }

  @override
  String profileLevelProgress(String xp, int level) {
    return '$xp خبرة للوصول إلى المستوى $level';
  }

  @override
  String get profileMaxLevel => 'وصلت إلى أعلى مستوى';

  @override
  String get profileTitleLabel => 'اللقب';

  @override
  String get profileAccountSection => 'الحساب';

  @override
  String get profileAccountType => 'نوع الحساب';

  @override
  String get profileAccountGuest => 'ضيف (غير محفوظ)';

  @override
  String get profileAccountLinked => 'حساب محفوظ';

  @override
  String get profileLinkedAccounts => 'طرق تسجيل الدخول';

  @override
  String get profileLinked => 'مرتبط';

  @override
  String get profileNotLinked => 'غير مرتبط';

  @override
  String get profileSaveProgressCta => 'احفظ التقدّم';

  @override
  String get profileTotalXp => 'إجمالي الخبرة';

  @override
  String get profileStatsSection => 'التقدّم';

  @override
  String get profileEditNameTooltip => 'تعديل الاسم';

  @override
  String get profileChangePicture => 'تغيير الصورة';

  @override
  String get profilePictureTitle => 'اختر صورتك';

  @override
  String get profilePictureClassic => 'الصورة الكلاسيكية';

  @override
  String get profilePictureEmptyMessage =>
      'الصور التي تشتريها من المتجر تظهر هنا.';

  @override
  String get profilePictureOpenStore => 'زيارة المتجر';

  @override
  String get profilePictureGetMore => 'احصل على المزيد من المتجر';

  @override
  String get profilePictureShowMore => 'عرض المزيد';

  @override
  String get profileEditNameTitle => 'غيّر اسمك';

  @override
  String get profileNameLabel => 'الاسم المعروض';

  @override
  String get profileNameRules =>
      'من 3 إلى 16 حرفًا. يُسمح بالحروف والأرقام والمسافات و_ . و-.';

  @override
  String get profileNameNote =>
      'سيظهر اسمك الجديد للأصدقاء وفي لوحات الصدارة والألعاب الجديدة. تحتفظ اللعبة الجارية بالاسم القديم.';

  @override
  String profileNameCounterSemantics(int count, int max) {
    return '$count من $max حرفًا';
  }

  @override
  String profileNameSaved(String name) {
    return 'اسمك الآن $name';
  }

  @override
  String get profileNameChangeLimit =>
      'لقد غيّرت اسمك مرات كثيرة. يُرجى المحاولة لاحقًا.';

  @override
  String profileNameChangeLimitRetry(String wait) {
    return 'لقد غيّرت اسمك مرات كثيرة. حاول مرة أخرى بعد $wait.';
  }

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsAppearance => 'المظهر';

  @override
  String get settingsTheme => 'السمة';

  @override
  String get settingsThemeLight => 'فاتح';

  @override
  String get settingsThemeDark => 'داكن';

  @override
  String get settingsThemeSystem => 'النظام';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsSoundAndHaptics => 'الصوت والاهتزاز';

  @override
  String get settingsSound => 'الصوت';

  @override
  String get settingsSoundSubtitle => 'الموسيقى والمؤثرات الصوتية';

  @override
  String get settingsSfxVolume => 'مستوى صوت المؤثرات';

  @override
  String get settingsMusicVolume => 'مستوى صوت الموسيقى';

  @override
  String get settingsHaptics => 'الاهتزاز';

  @override
  String get settingsReducedMotion => 'تقليل الحركة';

  @override
  String get settingsReducedMotionSubtitle => 'رسوم متحركة ومؤثرات أقل';

  @override
  String get settingsReducedMotionSystemOn => 'مفعّل أيضًا في إعدادات جهازك';

  @override
  String get settingsGameplay => 'اللعب';

  @override
  String get settingsQuickChatMute => 'كتم الدردشة السريعة';

  @override
  String get settingsQuickChatMuteSubtitle =>
      'إخفاء رسائل الدردشة والتعابير من اللاعبين الآخرين';

  @override
  String get settingsPrivacy => 'الخصوصية';

  @override
  String get settingsAnalytics => 'مشاركة إحصاءات استخدام مجهولة';

  @override
  String get settingsAnalyticsSubtitle =>
      'يساعدنا على تحسين اللعبة. لا يتضمن أبدًا اسمك أو دردشاتك أو رموز الغرف.';

  @override
  String get settingsAnalyticsNotConfigured => 'غير متاح في هذا الإصدار';

  @override
  String get settingsAccount => 'الحساب';

  @override
  String settingsSignedInAs(String name) {
    return 'مسجّل الدخول باسم $name';
  }

  @override
  String get settingsSaveProgress => 'احفظ التقدّم';

  @override
  String get settingsSaveProgressSubtitle =>
      'اربط طريقة تسجيل دخول لحماية تقدّمك';

  @override
  String get settingsSwitchToGuest => 'العودة إلى حساب الضيف';

  @override
  String get settingsSwitchToGuestSubtitle =>
      'عُد إلى حساب الضيف المحفوظ على هذا الجهاز';

  @override
  String get settingsSignOut => 'تسجيل الخروج';

  @override
  String get settingsAbout => 'حول التطبيق';

  @override
  String get settingsVersion => 'الإصدار';

  @override
  String get settingsLegalNotices => 'الإشعارات القانونية';

  @override
  String get settingsLegalNoticesSubtitle =>
      'تراخيص المصادر المفتوحة · تُفتح في متصفحك';

  @override
  String get settingsLegalNoticesOpenFailed =>
      'تعذّر فتح الصفحة. يُرجى المحاولة لاحقًا.';

  @override
  String get settingsConsentTitle => 'ساعدنا في تحسين لودو رويال';

  @override
  String get settingsConsentMessage =>
      'هل يمكننا جمع إحصاءات استخدام مجهولة، مثل أنماط اللعب الأكثر شعبية؟ لا نجمع أبدًا اسمك أو دردشاتك أو رموز الغرف أو بيانات الاتصال. يمكنك تغيير ذلك في أي وقت من الإعدادات.';

  @override
  String get settingsConsentAllow => 'مشاركة إحصاءات مجهولة';

  @override
  String get settingsConsentDeny => 'لا، شكرًا';

  @override
  String get socialPodOptionsHint => 'عرض خيارات اللاعب';

  @override
  String get socialRequestSent => 'تم إرسال الطلب';

  @override
  String get socialAcceptRequest => 'قبول الطلب';

  @override
  String get socialReportPlayer => 'الإبلاغ عن اللاعب';

  @override
  String get socialReported => 'تم الإبلاغ';

  @override
  String get socialAlreadyReported =>
      'لقد أبلغت عن هذا اللاعب خلال آخر 24 ساعة.';

  @override
  String socialReportsLeft(int remaining, int total) {
    return 'البلاغات المتبقية اليوم: $remaining من $total';
  }

  @override
  String socialReportLimitAt(int total, String time) {
    return 'استخدمت بلاغات اليوم ($total). يمكنك الإبلاغ مجددًا الساعة $time.';
  }

  @override
  String socialReportLimitLater(int total) {
    return 'استخدمت بلاغات اليوم ($total). حاول مرة أخرى لاحقًا.';
  }

  @override
  String socialReportTitle(String name) {
    return 'الإبلاغ عن $name';
  }

  @override
  String get socialReportWhy => 'ماذا حدث؟';

  @override
  String get socialReasonCheating => 'غش';

  @override
  String get socialReasonOffensiveName => 'اسم مسيء';

  @override
  String get socialReasonAbusiveBehavior => 'سلوك مسيء';

  @override
  String get socialReasonLeavingOrStalling => 'مغادرة اللعبة أو المماطلة';

  @override
  String get socialReasonOther => 'شيء آخر';

  @override
  String get socialReportReviewNote =>
      'يراجع فريقنا كل بلاغ. تابع حالته في تبويب المُبلَّغ عنهم في شاشة الأصدقاء.';

  @override
  String get socialSendReport => 'إرسال البلاغ';

  @override
  String socialReportSent(int remaining, int total) {
    return 'تم إرسال البلاغ. تبقّى لك $remaining من $total بلاغات اليوم.';
  }

  @override
  String socialFriendLimitNote(int max) {
    return 'يمكنك امتلاك $max صديقًا كحد أقصى — أزل أحدهم لإضافة غيره.';
  }

  @override
  String get socialErrorCannotReportSelf => 'لا يمكنك الإبلاغ عن نفسك.';

  @override
  String get socialErrorCannotReportBot => 'لا يمكن الإبلاغ عن هذا اللاعب.';

  @override
  String get socialErrorNotInRoom =>
      'يمكنك الإبلاغ فقط عن لاعبين من مباراة أنت فيها.';

  @override
  String get socialErrorRoomNotFound =>
      'لم تعد هذه المباراة موجودة، لذا تعذّر إرسال البلاغ.';

  @override
  String get socialErrorPlayerNotFound => 'تعذّر العثور على هذا اللاعب.';

  @override
  String get socialTabReported => 'المُبلَّغ عنهم';

  @override
  String socialOnlineNow(int count) {
    return 'متصلون الآن ($count)';
  }

  @override
  String socialOfflineCount(int count) {
    return 'غير متصلين ($count)';
  }

  @override
  String socialFriendsCount(int count, int max) {
    return 'الأصدقاء $count/$max';
  }

  @override
  String socialReportsResetAt(String time) {
    return 'يمكنك الإبلاغ مجددًا الساعة $time.';
  }

  @override
  String socialReportsInfo(int total) {
    return 'يمكنك الإبلاغ عن $total لاعبين كحد أقصى يوميًا. يراجع فريقنا كل بلاغ.';
  }

  @override
  String get socialNoReportsTitle => 'لا توجد بلاغات';

  @override
  String get socialNoReportsMessage =>
      'اللاعبون الذين تبلغ عنهم من مباراة يظهرون هنا مع حالة كل بلاغ.';

  @override
  String get socialStatusSubmitted => 'مُرسَل';

  @override
  String get socialStatusReviewing => 'قيد المراجعة';

  @override
  String get socialStatusActionTaken => 'تم اتخاذ إجراء';

  @override
  String get socialStatusDismissed => 'مرفوض';

  @override
  String get socialJustNow => 'الآن';

  @override
  String socialMinutesAgo(int minutes) {
    return 'منذ $minutes د';
  }

  @override
  String socialHoursAgo(int hours) {
    return 'منذ $hours س';
  }

  @override
  String get socialYesterday => 'أمس';

  @override
  String socialReportStatusA11y(String status) {
    return 'الحالة: $status';
  }

  @override
  String get storeTitle => 'المتجر';

  @override
  String get storeHeroTitle => 'صور الملف الشخصي';

  @override
  String get storeHeroSubtitle =>
      'اشترِها مرة واحدة بالماس واحتفظ بها إلى الأبد.';

  @override
  String get storeFilterAnimated => 'متحركة';

  @override
  String get storeFilterStatic => 'ثابتة';

  @override
  String get storeKindAnimated => 'صورة متحركة';

  @override
  String get storeKindStatic => 'صورة';

  @override
  String get storeApply => 'استخدام';

  @override
  String get storeRemove => 'استخدام الصورة الكلاسيكية';

  @override
  String get storeAppliedToast => 'تم تطبيق الصورة!';

  @override
  String get storeRemovedToast => 'عدت إلى صورتك الكلاسيكية.';

  @override
  String storePurchasedToast(String name) {
    return '$name أصبحت لك إلى الأبد!';
  }

  @override
  String get storeNextMatchNote =>
      'تظهر في ملفك الشخصي الآن، وللاعبين الآخرين بدءًا من مباراتك القادمة.';

  @override
  String get storeEmptyOwnedTitle => 'لا توجد صور بعد';

  @override
  String get storeEmptyOwnedMessage => 'الصور التي تشتريها تبقى لك إلى الأبد.';

  @override
  String get storeEmptyTitle => 'لا شيء هنا بعد';

  @override
  String get storeEmptyMessage => 'صور جديدة في الطريق.';

  @override
  String get storeBrowseAll => 'عرض الكل';

  @override
  String get storeLoadMoreFailed => 'تعذّر تحميل المزيد من الصور.';

  @override
  String storeTileSemantics(String name, String status) {
    return '$name، $status';
  }

  @override
  String get walletTitle => 'محفظتك';

  @override
  String get walletCoinsCaption =>
      'لرسوم دخول المباريات — الفائز يأخذ الحصيلة.';

  @override
  String get walletDiamondsCaption =>
      'للعناصر التجميلية المميزة في غرفة المجموعة.';

  @override
  String walletExactBalance(String amount) {
    return 'الرصيد الدقيق: $amount';
  }

  @override
  String get walletVirtualTitle => 'عملة افتراضية';

  @override
  String get walletVirtualNotice =>
      'العملات والماسات عناصر افتراضية للتسلية فقط. ليست لها قيمة حقيقية ولا يمكن بيعها أو تحويلها أو سحبها أو استبدالها بالمال.';

  @override
  String get walletEarnTitle => 'كيف تكسب المزيد';

  @override
  String get walletEarnWins => 'اربح المباريات لتأخذ الحصيلة';

  @override
  String get walletEarnMissions => 'أكمل المهام اليومية والأسبوعية';

  @override
  String get walletEarnLevels => 'ارتقِ في المستوى لتنال مكافآت المراحل';

  @override
  String get walletRefresh => 'تحديث الرصيد';

  @override
  String widgetsCoinsBalance(String amount) {
    return 'العملات: $amount';
  }

  @override
  String widgetsDiamondsBalance(String amount) {
    return 'الماسات: $amount';
  }

  @override
  String widgetsXpLabel(String current, String total) {
    return 'الخبرة: $current من $total';
  }

  @override
  String get widgetsAvatarLabel => 'صورة اللاعب';

  @override
  String widgetsTitleLabel(String title) {
    return 'اللقب: $title';
  }

  @override
  String widgetsEmoteLabel(String name) {
    return 'تعبير: $name';
  }

  @override
  String widgetsBadgeLabel(String name) {
    return 'الشارة: $name';
  }

  @override
  String widgetsSecondsLeft(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'تبقّت $seconds ثانية',
      many: 'تبقّت $seconds ثانية',
      few: 'تبقّت $seconds ثوانٍ',
      two: 'تبقّت ثانيتان',
      one: 'تبقّت ثانية واحدة',
      zero: 'لم يتبقَّ وقت',
    );
    return '$_temp0';
  }

  @override
  String widgetsConnectionLabel(String status) {
    return 'الاتصال: $status';
  }

  @override
  String widgetsNewItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر جديد',
      many: '$count عنصرًا جديدًا',
      few: '$count عناصر جديدة',
      two: 'عنصران جديدان',
      one: 'عنصر جديد واحد',
    );
    return '$_temp0';
  }

  @override
  String get widgetsSelected => 'محدَّد';

  @override
  String widgetsLogoLabel(String appName) {
    return 'شعار $appName';
  }
}
