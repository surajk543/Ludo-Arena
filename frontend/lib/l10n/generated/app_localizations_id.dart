// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get authWelcomeTitle => 'Siap menguasai papan?';

  @override
  String get authWelcomeSubtitle =>
      'Main Ludo dan Ular Tangga bersama teman dan pemain dari mana saja.';

  @override
  String get authContinueWithGoogle => 'Lanjutkan dengan Google';

  @override
  String get authContinueWithFacebook => 'Lanjutkan dengan Facebook';

  @override
  String get authContinueWithApple => 'Masuk dengan Apple';

  @override
  String get authPlayAsGuest => 'Main sebagai tamu';

  @override
  String get authGuestHint =>
      'Langsung mulai — progresmu bisa disimpan kapan saja.';

  @override
  String get authOrDivider => 'atau';

  @override
  String get authFairPlayNote =>
      'Koin dan berlian bersifat virtual dan tidak bisa ditukar dengan uang sungguhan.';

  @override
  String get authSessionExpiredBanner =>
      'Kamu telah keluar. Silakan masuk lagi.';

  @override
  String get authSignedInElsewhereTitle => 'Masuk di perangkat lain';

  @override
  String get authSignedInElsewhereMessage =>
      'Seseorang masuk ke akunmu di perangkat lain, jadi kamu telah dikeluarkan di sini. Hanya satu perangkat yang bisa masuk dalam satu waktu. Masuk lagi untuk bermain di sini — perangkat lain akan dikeluarkan.';

  @override
  String get authSignedInElsewhereBanner =>
      'Akunmu telah masuk di perangkat lain.';

  @override
  String get authAccountDeleted => 'Akunmu telah dihapus.';

  @override
  String get authDeleteAccountTitle => 'Hapus akunmu?';

  @override
  String get authDeleteAccountIntro =>
      'Tindakan ini menghapus akunmu beserta seluruh isinya secara permanen:';

  @override
  String get authDeleteAccountItemWallet => 'Koin dan berlian';

  @override
  String get authDeleteAccountItemProgress => 'Level, XP, dan misi';

  @override
  String get authDeleteAccountItemCollection => 'Item Ruang Koleksi';

  @override
  String get authDeleteAccountItemFriends => 'Teman dan permintaan pertemanan';

  @override
  String get authDeleteAccountWarning =>
      'Tindakan ini tidak bisa dibatalkan. Jika kamu bermain lagi nanti, kamu akan mulai dengan akun baru.';

  @override
  String get authDeleteAccountConfirmCheck =>
      'Saya mengerti bahwa akun dan progres saya akan dihapus selamanya.';

  @override
  String get authDeleteAccountConfirm => 'Hapus akun';

  @override
  String get authDeleteAccountFailed =>
      'Akunmu tidak dihapus. Periksa koneksimu dan coba lagi.';

  @override
  String get authChangeLanguage => 'Ganti bahasa';

  @override
  String get authProviderGoogle => 'Google';

  @override
  String get authProviderFacebook => 'Facebook';

  @override
  String get authProviderApple => 'Apple';

  @override
  String get authProviderGuest => 'Tamu';

  @override
  String get authSaveProgressTitle => 'Simpan progresmu';

  @override
  String get authSaveProgressSubtitle =>
      'Tautkan metode masuk agar koin, level, dan koleksimu tidak pernah hilang — bahkan di ponsel baru.';

  @override
  String get authSaveBenefitKeep => 'Simpan semua koin, XP, dan kosmetikmu';

  @override
  String get authSaveBenefitDevices => 'Masuk di perangkat apa pun';

  @override
  String get authSaveBenefitSame =>
      'Akun yang sama — tidak ada yang direset atau dipindahkan';

  @override
  String get authSaveWithGoogle => 'Simpan dengan Google';

  @override
  String get authSaveWithFacebook => 'Simpan dengan Facebook';

  @override
  String get authSaveWithApple => 'Simpan dengan Apple';

  @override
  String get authSaveNoProviders =>
      'Tidak ada metode masuk yang tersedia di build ini.';

  @override
  String get authLinkSuccessTitle => 'Progres tersimpan!';

  @override
  String authLinkSuccessMessage(String provider) {
    return 'Akunmu sekarang tertaut ke $provider. Masuk dengan $provider di perangkat mana pun untuk melanjutkan.';
  }

  @override
  String get authAlreadySavedTitle => 'Progresmu sudah tersimpan';

  @override
  String get authAlreadySavedMessage =>
      'Akun ini sudah tertaut ke metode masuk, jadi progresmu aman.';

  @override
  String authConflictTitle(String provider) {
    return 'Akun $provider ini sudah digunakan';
  }

  @override
  String authConflictMessage(String provider) {
    return 'Akun $provider itu sudah punya akun Ludo Royale sendiri. Tidak ada yang digabung atau dipindahkan antara kedua akun.';
  }

  @override
  String get authConflictSignIn => 'Masuk ke akun itu';

  @override
  String get authConflictGuestNote =>
      'Akun tamumu tetap ada di perangkat ini — kamu bisa kembali ke akun itu dari Pengaturan.';

  @override
  String get authAlreadyLinkedTitle => 'Sudah tertaut';

  @override
  String authAlreadyLinkedMessage(String provider) {
    return 'Akun ini sudah tertaut ke akun $provider yang lain.';
  }

  @override
  String get authLogoutTitle => 'Keluar?';

  @override
  String get authLogoutMessage =>
      'Kamu bisa masuk lagi kapan saja dengan metode yang sama.';

  @override
  String get authLogoutConfirm => 'Keluar';

  @override
  String get authGuestLogoutTitle => 'Keluar dari akun tamu?';

  @override
  String get authGuestLogoutMessage =>
      'Kamu bermain sebagai tamu. Jika keluar sekarang, koin, level, dan koleksimu akan hilang kecuali kamu menyimpan progres terlebih dahulu.';

  @override
  String get authGuestLogoutConfirm => 'Keluar dan hapus progres';

  @override
  String get authSaveProgressFirst => 'Simpan progres dulu';

  @override
  String get authSwitchToGuestTitle => 'Kembali ke akun tamu?';

  @override
  String get authSwitchToGuestMessage =>
      'Kamu akan keluar dari akun ini dan melanjutkan dengan akun tamu yang tersimpan di perangkat ini.';

  @override
  String get authSwitchToGuestConfirm => 'Beralih ke tamu';

  @override
  String get authGuestUnavailable => 'Akun tamu itu sudah tidak tersedia.';

  @override
  String authWelcomeBack(String name) {
    return 'Selamat datang, $name!';
  }

  @override
  String get boardsColorRed => 'Merah';

  @override
  String get boardsColorGreen => 'Hijau';

  @override
  String get boardsColorYellow => 'Kuning';

  @override
  String get boardsColorBlue => 'Biru';

  @override
  String get boardsLudoBoardLabel => 'Papan Ludo';

  @override
  String get boardsSnakesBoardLabel => 'Papan Ular Tangga';

  @override
  String boardsTokenInBase(String color, int number) {
    return 'Bidak $color $number, di markas';
  }

  @override
  String boardsTokenStepsFromHome(String color, int number, int steps) {
    String _temp0 = intl.Intl.pluralLogic(
      steps,
      locale: localeName,
      other: '$steps kotak lagi menuju finis',
    );
    return 'Bidak $color $number, $_temp0';
  }

  @override
  String boardsTokenHome(String color, int number) {
    return 'Bidak $color $number, sudah finis';
  }

  @override
  String get boardsTokenCanMove => 'bisa dijalankan';

  @override
  String get boardsTokenMoveHint => 'jalankan bidak ini';

  @override
  String get boardsCurrentTurn => 'sedang giliran';

  @override
  String boardsSnakesTokenOnSquare(String color, int square) {
    return 'Bidak $color di kotak $square';
  }

  @override
  String boardsSnakesTokenAtStart(String color) {
    return 'Bidak $color di garis start';
  }

  @override
  String boardsDiceShowing(int value) {
    return 'Dadu menunjukkan $value';
  }

  @override
  String get boardsDiceRolling => 'Dadu sedang bergulir';

  @override
  String get boardsDiceRollHint => 'lempar dadu';

  @override
  String get boardsVictoryCelebration => 'Perayaan kemenangan';

  @override
  String get boardsLevelUp => 'Naik level';

  @override
  String get commonOk => 'OK';

  @override
  String get commonCancel => 'Batal';

  @override
  String get commonRetry => 'Coba lagi';

  @override
  String get commonClose => 'Tutup';

  @override
  String get commonContinue => 'Lanjut';

  @override
  String get commonBack => 'Kembali';

  @override
  String get commonDone => 'Selesai';

  @override
  String get commonSave => 'Simpan';

  @override
  String get commonLater => 'Nanti';

  @override
  String get commonLoading => 'Memuat…';

  @override
  String get commonCopy => 'Salin';

  @override
  String get commonCopied => 'Disalin!';

  @override
  String get commonShare => 'Bagikan';

  @override
  String get commonYes => 'Ya';

  @override
  String get commonNo => 'Tidak';

  @override
  String get commonSomethingWentWrong => 'Terjadi kesalahan.';

  @override
  String get commonNothingHereYet => 'Belum ada apa-apa';

  @override
  String get commonYou => 'Kamu';

  @override
  String get commonGuest => 'Tamu';

  @override
  String get commonCoins => 'Koin';

  @override
  String get commonDiamonds => 'Berlian';

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
  String get commonConnectionConnecting => 'Menghubungkan…';

  @override
  String get commonConnectionReconnecting => 'Menyambung ulang…';

  @override
  String get commonConnectionOffline => 'Offline';

  @override
  String get commonConnectionReplaced => 'Game ini terbuka di tempat lain';

  @override
  String get commonReconnect => 'Sambungkan lagi';

  @override
  String commonSecondsShort(int seconds) {
    return '$seconds dtk';
  }

  @override
  String get commonGameLudo => 'Ludo';

  @override
  String get commonGameSnakesLadders => 'Ular Tangga';

  @override
  String get commonVariantClassic => 'Klasik';

  @override
  String get commonVariantQuick => 'Cepat';

  @override
  String commonPlayerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pemain',
    );
    return '$_temp0';
  }

  @override
  String get commonOfflineHint =>
      'Kamu sedang offline. Periksa koneksi lalu coba lagi.';

  @override
  String commonEntryFee(String amount) {
    return 'Biaya masuk $amount';
  }

  @override
  String get commonFree => 'Gratis';

  @override
  String get appTitle => 'Ludo Royale';

  @override
  String get languageNameNative => 'Bahasa Indonesia';

  @override
  String get cosmeticDiceClassic => 'Gading Klasik';

  @override
  String get cosmeticDiceNeon => 'Denyut Neon';

  @override
  String get cosmeticDiceGolden => 'Emas Kerajaan';

  @override
  String get cosmeticDiceAutumn => 'Daun Musim Gugur';

  @override
  String get cosmeticTokenClassic => 'Pion Klasik';

  @override
  String get cosmeticTokenGem => 'Batu Permata';

  @override
  String get cosmeticTokenRoyal => 'Pion Kerajaan';

  @override
  String get cosmeticTokenCrown => 'Bidak Mahkota';

  @override
  String get cosmeticLudoBoardClassic => 'Klasik';

  @override
  String get cosmeticLudoBoardMidnight => 'Marmer Tengah Malam';

  @override
  String get cosmeticLudoBoardRoyal => 'Istana Kerajaan';

  @override
  String get cosmeticSnakesBoardClassic => 'Padang Klasik';

  @override
  String get cosmeticSnakesBoardJungle => 'Kuil Rimba';

  @override
  String get cosmeticSnakesBoardCandy => 'Negeri Permen';

  @override
  String get cosmeticTrailNone => 'Tanpa Jejak';

  @override
  String get cosmeticTrailSparkle => 'Kilau';

  @override
  String get cosmeticTrailComet => 'Komet';

  @override
  String get cosmeticVictoryConfetti => 'Konfeti';

  @override
  String get cosmeticVictoryFireworks => 'Kembang Api';

  @override
  String get cosmeticVictoryCrown => 'Mahkota Emas';

  @override
  String get cosmeticFrameNone => 'Tanpa Bingkai';

  @override
  String get cosmeticFrameBronze => 'Cincin Perunggu';

  @override
  String get cosmeticFrameSilver => 'Mahkota Daun Perak';

  @override
  String get cosmeticFrameGold => 'Mahkota Daun Emas';

  @override
  String get cosmeticFrameRoyal => 'Lambang Kerajaan';

  @override
  String get cosmeticTitleRookie => 'Pemula';

  @override
  String get cosmeticTitleStrategist => 'Ahli Strategi';

  @override
  String get cosmeticTitleDiceMaster => 'Raja Dadu';

  @override
  String get cosmeticTitleRoyal => 'Yang Mulia';

  @override
  String get cosmeticTitleWeeklyChampion => 'Juara Mingguan';

  @override
  String get cosmeticBadgeFirstWin => 'Kemenangan Pertama';

  @override
  String get cosmeticBadgeFriendly => 'Teman Seru';

  @override
  String get cosmeticEmoteWave => 'Lambaian';

  @override
  String get cosmeticEmoteThumbs => 'Jempol';

  @override
  String get cosmeticEmoteLaugh => 'Tawa';

  @override
  String get cosmeticEmoteWow => 'Wah';

  @override
  String get cosmeticEmoteCrown => 'Mahkota';

  @override
  String get cosmeticRarityCommon => 'Biasa';

  @override
  String get cosmeticRarityRare => 'Langka';

  @override
  String get cosmeticRarityEpic => 'Epik';

  @override
  String get cosmeticRarityLegendary => 'Legendaris';

  @override
  String get cosmeticKindDice => 'Dadu';

  @override
  String get cosmeticKindToken => 'Bidak';

  @override
  String get cosmeticKindLudoBoard => 'Papan Ludo';

  @override
  String get cosmeticKindSnakesBoard => 'Papan Ular Tangga';

  @override
  String get cosmeticKindFrame => 'Bingkai avatar';

  @override
  String get cosmeticKindTitle => 'Gelar';

  @override
  String get cosmeticKindBadge => 'Lencana';

  @override
  String get cosmeticKindEmote => 'Emote';

  @override
  String get cosmeticKindVictory => 'Selebrasi kemenangan';

  @override
  String get cosmeticKindTrail => 'Jejak bidak';

  @override
  String get errorGeneric => 'Terjadi kesalahan. Silakan coba lagi.';

  @override
  String get errorBadRequest => 'Permintaan ini tidak dapat diproses.';

  @override
  String get errorUnknownType =>
      'Aksi ini tidak didukung. Silakan perbarui aplikasi.';

  @override
  String get errorRateLimited => 'Pelan-pelan! Tunggu sebentar lalu coba lagi.';

  @override
  String get errorUnauthorized =>
      'Sesi kamu sudah berakhir. Silakan masuk lagi.';

  @override
  String get errorUpdateRequired =>
      'Versi aplikasi yang lebih baru diperlukan.';

  @override
  String get errorMaintenance =>
      'Server game sedang dalam pemeliharaan. Coba lagi sebentar lagi.';

  @override
  String get errorNotInRoom => 'Kamu sudah tidak ada di room ini.';

  @override
  String get errorRoomNotFound => 'Room ini sudah tidak ada.';

  @override
  String get errorRoomFull => 'Room ini sudah penuh.';

  @override
  String get errorRoomInProgress => 'Game ini sudah dimulai.';

  @override
  String get errorRoomClosed => 'Room ini sudah ditutup.';

  @override
  String get errorAlreadyInRoom =>
      'Kamu sudah berada di sebuah room. Keluar dulu untuk bergabung ke room lain.';

  @override
  String get errorNotHost => 'Hanya host yang bisa melakukannya.';

  @override
  String get errorNotEnoughPlayers => 'Butuh minimal 2 pemain untuk mulai.';

  @override
  String get errorPlayersNotReady => 'Menunggu semua pemain siap.';

  @override
  String get errorNotYourTurn => 'Belum giliranmu.';

  @override
  String get errorInvalidPhase => 'Kamu tidak bisa melakukannya sekarang.';

  @override
  String get errorIllegalMove => 'Langkah itu tidak diperbolehkan.';

  @override
  String get errorStaleState => 'Papan baru saja berubah. Coba lagi.';

  @override
  String get errorInsufficientFunds => 'Koin kamu tidak cukup untuk ini.';

  @override
  String get errorInvalidCode =>
      'Kode room tidak valid. Periksa lalu coba lagi.';

  @override
  String get errorRematchClosed => 'Waktu rematch sudah habis.';

  @override
  String get errorNotFriends => 'Kamu hanya bisa mengundang teman.';

  @override
  String get errorItemNotOwned => 'Kamu belum memiliki item ini.';

  @override
  String get errorBotsUnavailable =>
      'Belum ada pemain komputer yang tersedia. Coba lagi sebentar lagi.';

  @override
  String get errorBotsNotAllowed =>
      'Pemain komputer tidak diizinkan di room ini.';

  @override
  String get errorInternal => 'Ada masalah di pihak kami. Silakan coba lagi.';

  @override
  String get errorClientVersionRequired =>
      'Aplikasi tidak dapat mengenali versinya. Silakan perbarui atau pasang ulang aplikasi.';

  @override
  String get errorEnvironmentMismatch =>
      'Build aplikasi ini terhubung ke server yang salah.';

  @override
  String get errorInvalidCredential => 'Gagal masuk. Silakan coba lagi.';

  @override
  String get errorRefreshReused =>
      'Demi keamananmu, kamu telah dikeluarkan. Silakan masuk lagi.';

  @override
  String get errorSessionReplaced =>
      'Akunmu telah masuk di perangkat lain. Silakan masuk lagi.';

  @override
  String get errorForbidden => 'Kamu tidak punya izin untuk melakukannya.';

  @override
  String get errorNotFound => 'Yang kamu cari tidak ditemukan.';

  @override
  String get errorIdentityConflict =>
      'Akun ini sudah terhubung ke profil pemain lain.';

  @override
  String get errorProviderAlreadyLinked =>
      'Profilmu sudah terhubung dengan akun lain dari jenis yang sama.';

  @override
  String get errorAlreadyOwned => 'Kamu sudah memiliki item ini.';

  @override
  String get errorAlreadyClaimed => 'Kamu sudah mengklaim hadiah ini.';

  @override
  String get errorAlreadyFriends => 'Kalian sudah berteman.';

  @override
  String get errorNotCompleted =>
      'Selesaikan misi ini dulu untuk mengklaim hadiah.';

  @override
  String get errorItemLocked => 'Item ini masih terkunci.';

  @override
  String get errorProviderUnavailable =>
      'Layanan masuk sedang tidak tersedia. Silakan coba lagi nanti.';

  @override
  String get errorNetwork =>
      'Tidak dapat terhubung ke layanan game. Periksa koneksi internetmu.';

  @override
  String get errorTimeout => 'Koneksi habis waktu. Silakan coba lagi.';

  @override
  String get errorBadResponse =>
      'Kami menerima respons yang tidak terduga. Silakan coba lagi.';

  @override
  String get errorCancelled => 'Dibatalkan.';

  @override
  String get errorNotConnected =>
      'Kamu sedang tidak terhubung. Menyambung ulang…';

  @override
  String errorRateLimitedRetry(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Terlalu banyak percobaan. Coba lagi dalam $seconds detik.',
    );
    return '$_temp0';
  }

  @override
  String get errorInvalidName =>
      'Nama itu tidak bisa dipakai. Silakan pilih nama lain.';

  @override
  String get errorInvalidNameTooShort => 'Nama minimal 3 karakter.';

  @override
  String get errorInvalidNameTooLong => 'Nama maksimal 16 karakter.';

  @override
  String get errorInvalidNameCharacters =>
      'Gunakan hanya huruf, angka, spasi, _ . atau - (minimal satu huruf). Tanpa emoji atau simbol.';

  @override
  String get errorInvalidNameReserved =>
      'Nama itu sudah dicadangkan. Silakan pilih nama lain.';

  @override
  String get errorInvalidNameInappropriate =>
      'Nama itu tidak diizinkan. Silakan pilih nama yang sopan.';

  @override
  String get gateSplashTagline => 'Lempar. Balapan. Berkuasa.';

  @override
  String get gateStatusChecking => 'Memeriksa server game…';

  @override
  String get gateStatusSigningIn => 'Sedang masuk…';

  @override
  String get gateStatusLoadingProfile => 'Memuat profilmu…';

  @override
  String get gateUpdateNow => 'Perbarui sekarang';

  @override
  String get gateForceUpdateTitle => 'Pembaruan diperlukan';

  @override
  String get gateForceUpdateMessage =>
      'Versi Ludo Royale ini sudah tidak didukung. Perbarui untuk terus bermain online — koin dan progresmu tetap aman.';

  @override
  String get gateInstalledVersion => 'Versi terpasang';

  @override
  String get gateRequiredVersion => 'Versi yang diperlukan';

  @override
  String get gateStoreNotReadyTitle =>
      'Pembaruan belum tersedia di toko aplikasi';

  @override
  String get gateStoreNotReadyMessage =>
      'Versi baru sedang dalam perjalanan ke toko aplikasimu. Coba periksa lagi sebentar lagi.';

  @override
  String get gateCheckAgain => 'Periksa lagi';

  @override
  String get gateOptionalUpdateTitle => 'Versi baru tersedia';

  @override
  String gateOptionalUpdateMessage(String version) {
    return 'Versi $version membawa perbaikan dan peningkatan. Perbarui sekarang agar main makin lancar.';
  }

  @override
  String get gateMaintenanceTitle => 'Kami sedang memoles papan';

  @override
  String get gateMaintenanceMessage =>
      'Ludo Royale sedang dalam pemeliharaan. Koin, progres, dan pertandingan yang berjalan tetap aman — pertandingan dilanjutkan saat kami kembali.';

  @override
  String gateMaintenanceEstimatedEnd(String time) {
    return 'Perkiraan selesai: $time';
  }

  @override
  String get gateMaintenanceEstimateNote =>
      'Ini hanya perkiraan dan bisa berubah.';

  @override
  String get gateMaintenanceAutoCheck =>
      'Kami akan memeriksa lagi otomatis setiap 30 detik.';

  @override
  String gateLastChecked(String time) {
    return 'Terakhir diperiksa pukul $time';
  }

  @override
  String get gateCheckingNow => 'Memeriksa…';

  @override
  String get gateServiceReachable => 'Layanan game terjangkau';

  @override
  String get gateServiceUnreachableShort => 'Tidak terhubung ke layanan game';

  @override
  String get gateUnreachableTitle => 'Tidak dapat menjangkau layanan game';

  @override
  String get gateUnreachableMessage =>
      'Ludo Royale butuh koneksi internet untuk bermain online. Periksa Wi-Fi atau data selulermu, lalu coba lagi.';

  @override
  String get gateUnreachableLastKnownMaintenance =>
      'Status terakhir yang kami terima menyebutkan server sedang dalam pemeliharaan.';

  @override
  String get gateUnreachableLastKnownUpdate =>
      'Status terakhir yang kami terima menyebutkan versi ini perlu diperbarui.';

  @override
  String get gateNotFoundTitle => 'Belum tersedia';

  @override
  String get gateNotFoundMessage =>
      'Bagian Ludo Royale ini belum tersedia di versi ini.';

  @override
  String get gateGoHome => 'Kembali ke beranda';

  @override
  String homeGreeting(String name) {
    return 'Hai, $name';
  }

  @override
  String get homeQuickPlay => 'Main Cepat';

  @override
  String homeQuickPlayDetails(String game, String variant, String players) {
    return '$game · $variant · $players';
  }

  @override
  String get homePrivateRoom => 'Ruang Privat';

  @override
  String get homePrivateRoomSubtitle => 'Buat ruang untuk teman';

  @override
  String get homeJoinWithCode => 'Gabung dengan Kode';

  @override
  String get homeJoinWithCodeSubtitle => 'Masukkan kode ruang';

  @override
  String get homePlayOnline => 'Main Online';

  @override
  String get homePlayWithFriends => 'Main dengan Teman';

  @override
  String get homePracticeVsBots => 'Latihan vs Bot';

  @override
  String get homeLudoTagline => 'Bawa keempat bidak pulang';

  @override
  String get homeSnakesTagline => 'Naiki tangga, hindari ular';

  @override
  String get homeMissions => 'Misi';

  @override
  String get homeMissionsSubtitle => 'Target harian & mingguan';

  @override
  String get homeCollection => 'Koleksi';

  @override
  String get homeCollectionSubtitle => 'Dadu, bidak & bingkai';

  @override
  String get homeFriends => 'Teman';

  @override
  String get homeFriendsSubtitle => 'Main bareng gengmu';

  @override
  String get homeEvents => 'Event';

  @override
  String get homeEventsSubtitle => 'Piala waktu terbatas';

  @override
  String get homeExploreHeader => 'Jelajahi Lainnya';

  @override
  String get homeGamesHeader => 'Pilih Permainan';

  @override
  String get homeSaveProgressTooltip => 'Simpan progres';

  @override
  String get homeProfileTooltip => 'Profil';

  @override
  String get homeSettingsTooltip => 'Pengaturan';

  @override
  String get homeThemeTooltip => 'Ganti tema terang/gelap';

  @override
  String get homeWalletTooltip => 'Dompet';

  @override
  String homeOptionsOnlineTitle(String game) {
    return '$game online';
  }

  @override
  String homeOptionsFriendsTitle(String game) {
    return '$game bersama teman';
  }

  @override
  String homeOptionsPracticeTitle(String game) {
    return 'Latihan $game';
  }

  @override
  String get homeOptionsPrivateRoomTitle => 'Buat ruang privat';

  @override
  String get homeGameLabel => 'Permainan';

  @override
  String get homePlayersLabel => 'Pemain';

  @override
  String get homeModeLabel => 'Mode';

  @override
  String get homeBotsLabel => 'Bot';

  @override
  String get homeModeClassicCaption => 'Aturan lengkap';

  @override
  String get homeModeQuickCaption => 'Permainan lebih singkat';

  @override
  String homeBotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bot',
    );
    return '$_temp0';
  }

  @override
  String get homeFindMatch => 'Cari lawan';

  @override
  String get homeCreateRoom => 'Buat ruang';

  @override
  String get homeStartPractice => 'Mulai latihan';

  @override
  String get homeHaveACode => 'Punya kode? Gabung ruang';

  @override
  String homeEntryFeeNote(String fee) {
    return 'Biaya masuk $fee koin · Pemenang ambil semua';
  }

  @override
  String get homePracticeNote =>
      'Latihan gratis: tanpa koin, tapi tetap dapat XP dan progres misi.';

  @override
  String homeNotEnoughCoins(String fee) {
    return 'Kamu butuh setidaknya $fee koin untuk pertandingan ini.';
  }

  @override
  String get homeJoinCodeTitle => 'Gabung ruang privat';

  @override
  String get homeJoinCodeLabel => 'Kode ruang';

  @override
  String get homeJoinCodeHelper => 'Minta kode 6 karakter dari host.';

  @override
  String get homeJoinCodeInvalid =>
      'Kode ruang terdiri dari 6 huruf atau angka.';

  @override
  String get homeJoinCodeAction => 'Gabung ruang';

  @override
  String homeLevelUpToast(int level) {
    return 'Naik level! Kamu mencapai level $level.';
  }

  @override
  String homeCoinsGainedToast(String amount) {
    return '+$amount koin';
  }

  @override
  String get homeQuickPlaySubtitle => 'Temukan pemain acak dan mulai sekarang';

  @override
  String get homePlayNow => 'Main Sekarang';

  @override
  String get homeQuickLudo => 'Ludo Cepat';

  @override
  String get homeChangeGameHint => 'Ganti permainan';

  @override
  String get homeChangePlayersHint => 'Ubah jumlah pemain';

  @override
  String get homeGamesSubtitle =>
      'Pilih permainan, lalu main online, bersama teman, atau melawan bot.';

  @override
  String get homeNavHome => 'Beranda';

  @override
  String get homeNavGames => 'Permainan';

  @override
  String get homeNavMissions => 'Misi';

  @override
  String get homeNavFriends => 'Teman';

  @override
  String get homeNavProfile => 'Profil';

  @override
  String get homeNoAdsRibbon => 'Tanpa Iklan';

  @override
  String get metaMissionsTitle => 'Misi';

  @override
  String get metaEventsTitle => 'Event';

  @override
  String get metaCollectionTitle => 'Ruang Koleksi';

  @override
  String get metaFriendsTitle => 'Teman';

  @override
  String get metaLeaderboardTitle => 'Peringkat mingguan';

  @override
  String get metaLevelRoadTitle => 'Jalur level';

  @override
  String get metaDailyTitle => 'Misi harian';

  @override
  String get metaWeeklyTitle => 'Tantangan mingguan';

  @override
  String get metaClaim => 'Klaim';

  @override
  String get metaStatusInProgress => 'Sedang berjalan';

  @override
  String get metaStatusReady => 'Siap diklaim';

  @override
  String get metaStatusClaimed => 'Sudah diklaim';

  @override
  String get metaCollected => 'Hadiah diterima — sudah masuk ke akunmu';

  @override
  String metaProgressCount(String progress, String target) {
    return '$progress / $target';
  }

  @override
  String metaMissionSemantics(String title, String progress, String state) {
    return '$title. Progres $progress. $state';
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
    return '$amount koin';
  }

  @override
  String metaRewardDiamondsLabel(String amount) {
    return '$amount berlian';
  }

  @override
  String metaRewardXpLabel(String amount) {
    return '$amount poin pengalaman';
  }

  @override
  String metaRewardItemLabel(String name, String kind) {
    return '$name ($kind)';
  }

  @override
  String get metaGameAny => 'Game apa saja';

  @override
  String metaResetsDailyAt(String time) {
    return 'Misi baru pukul $time';
  }

  @override
  String metaResetsWeeklyAt(String day, String time) {
    return 'Diatur ulang $day pukul $time';
  }

  @override
  String metaEventEndsAt(String date) {
    return 'Berakhir $date';
  }

  @override
  String metaWhenWithCountdown(String when, String duration) {
    return '$when · $duration lagi';
  }

  @override
  String metaDurationDaysHours(int days, int hours) {
    return '$days hr $hours j';
  }

  @override
  String metaDurationHoursMinutes(int hours, int minutes) {
    return '$hours j $minutes mnt';
  }

  @override
  String metaDurationMinutes(int minutes) {
    return '$minutes mnt';
  }

  @override
  String get metaNoPenaltyNote =>
      'Terlewat sehari? Tidak masalah — XP, level, dan koleksimu selalu tersimpan.';

  @override
  String get metaMissionsEmptyTitle => 'Belum ada misi';

  @override
  String get metaMissionsEmptyMessage =>
      'Misi harian baru hadir setiap hari. Tarik ke bawah untuk menyegarkan.';

  @override
  String metaRetryHint(String message) {
    return '$message Ketuk lagi untuk mencoba ulang.';
  }

  @override
  String get metaNewItemsTitle => 'Baru di koleksimu!';

  @override
  String metaNewItemsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count item ini sekarang milikmu. Pasang dan nikmati!',
    );
    return '$_temp0';
  }

  @override
  String get metaNice => 'Mantap!';

  @override
  String get metaViewCollection => 'Lihat koleksi';

  @override
  String get metaEventDetails => 'Detail';

  @override
  String get metaMissionLudoTimeTitle => 'Waktunya Ludo';

  @override
  String get metaMissionClimbTitle => 'Panjat Tangganya';

  @override
  String get metaMissionWarmUpTitle => 'Pemanasan';

  @override
  String get metaMissionFriendlyTableTitle => 'Meja Persahabatan';

  @override
  String get metaMissionStayToEndTitle => 'Main Sampai Selesai';

  @override
  String get metaMissionTasteOfVictoryTitle => 'Rasa Kemenangan';

  @override
  String get metaMissionQuickDrawTitle => 'Gerak Cepat';

  @override
  String get metaMissionWeeklyChallengeTitle => 'Tantangan Mingguan';

  @override
  String get metaMissionAutumnSprintTitle => 'Lari Musim Gugur';

  @override
  String get metaMissionFallbackTitle => 'Misi';

  @override
  String metaMissionLudoMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Selesaikan $count pertandingan Ludo.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionSnakesMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Selesaikan $count pertandingan Ular Tangga.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionAnyMatchesDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Selesaikan $count pertandingan di game apa saja.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionFriendPrivateDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Selesaikan $count pertandingan privat bersama teman.',
      one: 'Selesaikan pertandingan privat bersama teman.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionNoLeavingDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Selesaikan $count pertandingan tanpa keluar lebih awal.',
      one: 'Selesaikan satu pertandingan tanpa keluar lebih awal.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionWinDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Menangkan $count pertandingan.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionQuickLudoDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Selesaikan $count pertandingan Ludo Cepat.',
    );
    return '$_temp0';
  }

  @override
  String metaMissionWeeklyDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Selesaikan $count pertandingan di Ludo dan Ular Tangga.',
    );
    return '$_temp0';
  }

  @override
  String get metaEventAutumnCupTitle => 'Piala Musim Gugur';

  @override
  String get metaEventAutumnCupDesc =>
      'Rayakan musim ini dengan Ludo Cepat dan menangkan dadu Daun Musim Gugur.';

  @override
  String metaEventWindow(String start, String end) {
    return '$start – $end';
  }

  @override
  String get metaEventLiveBadge => 'Event berlangsung';

  @override
  String get metaEventMissionsTitle => 'Misi event';

  @override
  String get metaEventRulesTitle => 'Cara kerjanya';

  @override
  String get metaEventRuleComplete =>
      'Selesaikan misi event selama event berlangsung.';

  @override
  String get metaEventRuleEligible =>
      'Pertandingan dihitung jika kamu bermain sampai selesai, melangkah minimal 3 kali, dan berlangsung minimal 30 detik.';

  @override
  String get metaEventRuleClaim =>
      'Klaim setiap hadiah di sini — langsung masuk ke akunmu.';

  @override
  String get metaEventRuleEnd =>
      'Hadiah yang belum diklaim saat event berakhir tidak tersedia lagi. XP, level, dan koleksimu tidak pernah terpengaruh.';

  @override
  String get metaNoEventsTitle => 'Belum ada event';

  @override
  String get metaNoEventsMessage =>
      'Event baru akan muncul di sini. Misi harianmu selalu tersedia.';

  @override
  String get metaGoToMissions => 'Ke misi';

  @override
  String metaXpToNextLevel(String xp, int level) {
    return '$xp XP lagi ke level $level';
  }

  @override
  String get metaMaxLevelReached =>
      'Level maksimum tercapai — XP tetap dihitung untuk peringkat mingguan';

  @override
  String get metaMaxBadge => 'MAKS';

  @override
  String metaTotalXp(String xp) {
    return 'Total XP: $xp';
  }

  @override
  String get metaHowToEarnXp => 'Cara mendapatkan XP';

  @override
  String metaXpForMatch(int xp) {
    return '+$xp XP untuk setiap pertandingan yang selesai';
  }

  @override
  String metaXpForWin(int xp) {
    return 'Bonus +$xp XP untuk kemenangan';
  }

  @override
  String metaXpForFriend(int xp) {
    return '+$xp XP saat bermain bersama teman';
  }

  @override
  String get metaXpForMissions => 'Hadiah misi juga berisi XP';

  @override
  String get metaXpFairPlayNote =>
      'Pertandingan dihitung jika dimainkan sampai selesai (minimal 3 langkah dan 30 detik). Bot tidak pernah mendapat XP.';

  @override
  String get metaMilestonesTitle => 'Pencapaian';

  @override
  String get metaMilestoneUnlocked => 'Terbuka';

  @override
  String metaMilestoneNext(String xp) {
    return 'Pencapaian berikutnya · $xp XP lagi';
  }

  @override
  String metaMilestoneLocked(String xp) {
    return '$xp XP lagi';
  }

  @override
  String get metaNoMilestones => 'Pencapaian akan muncul di sini.';

  @override
  String get metaLevelUpTitle => 'Naik level!';

  @override
  String metaLevelUpMessage(int level) {
    return 'Kamu mencapai level $level.';
  }

  @override
  String get metaUnlockedHeader => 'Terbuka untukmu';

  @override
  String get metaLevelUpContinue => 'Keren!';

  @override
  String get metaYourLook => 'Gayamu';

  @override
  String metaCollectedCount(String owned, String total) {
    return '$owned dari $total terkumpul';
  }

  @override
  String get metaTabDice => 'Dadu';

  @override
  String get metaTabTokens => 'Bidak';

  @override
  String get metaTabLudoBoards => 'Papan Ludo';

  @override
  String get metaTabSnakesBoards => 'Papan Ular Tangga';

  @override
  String get metaTabTrails => 'Jejak';

  @override
  String get metaTabVictory => 'Kemenangan';

  @override
  String get metaTabFrames => 'Bingkai';

  @override
  String get metaTabTitles => 'Gelar';

  @override
  String get metaTabBadges => 'Lencana';

  @override
  String get metaTabEmotes => 'Emote';

  @override
  String get metaFilterAll => 'Semua';

  @override
  String get metaFilterOwned => 'Dimiliki';

  @override
  String get metaFilterLocked => 'Belum terbuka';

  @override
  String get metaEquipped => 'Dipakai';

  @override
  String get metaOwned => 'Dimiliki';

  @override
  String get metaLocked => 'Terkunci';

  @override
  String get metaNewBadge => 'Baru';

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
  String get metaAcqStarter => 'Item awal';

  @override
  String metaAcqLevel(int level) {
    return 'Capai level $level';
  }

  @override
  String get metaAcqMission => 'Hadiah misi';

  @override
  String get metaAcqWeeklyChallenge => 'Hadiah tantangan mingguan';

  @override
  String get metaAcqFirstWin => 'Menangkan pertandingan pertamamu';

  @override
  String get metaAcqEvent => 'Hadiah event';

  @override
  String get metaAcqAutumnCup => 'Hadiah Piala Musim Gugur';

  @override
  String metaPriceCoins(String amount) {
    return '$amount koin';
  }

  @override
  String metaPriceDiamonds(String amount) {
    return '$amount berlian';
  }

  @override
  String get metaEquip => 'Pakai';

  @override
  String get metaEquipDefault => 'Pakai bawaan';

  @override
  String get metaEquippedToast => 'Dipakai!';

  @override
  String get metaDefaultEquippedToast => 'Kembali ke tampilan bawaan';

  @override
  String get metaEmoteHint => 'Kirim emote saat bertanding lewat tombol emote.';

  @override
  String get metaBadgeHint =>
      'Lencana merayakan pencapaianmu. Semuanya milikmu selamanya.';

  @override
  String metaBuyFor(String price) {
    return 'Beli seharga $price';
  }

  @override
  String get metaBuy => 'Beli';

  @override
  String metaPurchaseTitle(String item) {
    return 'Beli $item?';
  }

  @override
  String get metaPrice => 'Harga';

  @override
  String get metaYourBalance => 'Saldomu';

  @override
  String get metaBalanceAfter => 'Setelah membeli';

  @override
  String metaNeedMore(String amount) {
    return 'Kamu perlu $amount lagi. Menangkan pertandingan dan selesaikan misi untuk mendapatkannya.';
  }

  @override
  String get metaCosmeticOnlyNote =>
      'Hanya kosmetik — tidak pernah mengubah dadu, aturan, atau matchmaking.';

  @override
  String metaPurchaseSuccess(String item) {
    return '$item kini ada di koleksimu!';
  }

  @override
  String get metaNotEnoughCoins => 'Koinmu belum cukup untuk item ini.';

  @override
  String get metaNotEnoughDiamonds => 'Berlianmu belum cukup untuk item ini.';

  @override
  String get metaAlreadyOwned => 'Kamu sudah memiliki item ini.';

  @override
  String get metaItemNotForSale =>
      'Item ini dibuka dengan bermain, bukan dibeli.';

  @override
  String metaUnlocksAtLevel(int level) {
    return 'Terbuka otomatis saat kamu mencapai level $level.';
  }

  @override
  String get metaEarnFromMissionsHint =>
      'Dapatkan dengan menyelesaikan misi atau event terkait — tanpa perlu membeli.';

  @override
  String get metaAllOwnedInKind =>
      'Kamu sudah membuka semuanya di sini. Hebat!';

  @override
  String get metaNothingOwnedInKind =>
      'Belum ada apa-apa — terus bermain untuk membuka lebih banyak.';

  @override
  String get metaCollectionFairNote =>
      'Setiap item hanya kosmetik dan cara mendapatkannya jelas — tanpa kotak acak, tanpa keuntungan bermain.';

  @override
  String get metaDescDiceClassic =>
      'Dadu gading klasik dengan titik hitam yang tegas.';

  @override
  String get metaDescDiceNeon =>
      'Dadu menyala yang berdenyut di setiap lemparan.';

  @override
  String get metaDescDiceGolden =>
      'Dadu emas mengilap yang layak untuk bangsawan.';

  @override
  String get metaDescDiceAutumn => 'Dadu kuning hangat dari Piala Musim Gugur.';

  @override
  String get metaDescTokenClassic => 'Bidak yang dikenal semua orang.';

  @override
  String get metaDescTokenGem =>
      'Bidak permata berfaset yang memantulkan cahaya.';

  @override
  String get metaDescTokenRoyal => 'Bidak yang memakai mahkota mungil.';

  @override
  String get metaDescTokenCrown => 'Bidak legendaris berbentuk mahkota.';

  @override
  String get metaDescLudoBoardClassic => 'Papan Ludo tradisional empat warna.';

  @override
  String get metaDescLudoBoardMidnight => 'Marmer gelap dengan hiasan perak.';

  @override
  String get metaDescLudoBoardRoyal =>
      'Halaman istana berwarna emas dan merah tua.';

  @override
  String get metaDescSnakesBoardClassic =>
      'Padang hijau, ular ramah, tangga kokoh.';

  @override
  String get metaDescSnakesBoardJungle =>
      'Tanaman rambat, reruntuhan, dan tangga kuil.';

  @override
  String get metaDescSnakesBoardCandy =>
      'Ular permen akar manis dan tangga permen tongkat.';

  @override
  String get metaDescTrailNone => 'Gerakan bersih, tanpa jejak.';

  @override
  String get metaDescTrailSparkle => 'Hujan kilauan mengikuti setiap langkah.';

  @override
  String get metaDescTrailComet => 'Ekor komet yang menyala.';

  @override
  String get metaDescVictoryConfetti => 'Perayaan konfeti klasik.';

  @override
  String get metaDescVictoryFireworks => 'Terangi langit saat kamu menang.';

  @override
  String get metaDescVictoryCrown => 'Mahkota emas turun ke sang pemenang.';

  @override
  String get metaDescFrameNone => 'Avatarmu, tanpa bingkai.';

  @override
  String get metaDescFrameBronze =>
      'Cincin perunggu sederhana di sekeliling avatarmu.';

  @override
  String get metaDescFrameSilver => 'Karangan daun salam perak.';

  @override
  String get metaDescFrameGold =>
      'Karangan daun salam emas untuk pemain berpengalaman.';

  @override
  String get metaDescFrameRoyal => 'Lambang kerajaan yang megah.';

  @override
  String get metaDescTitleRookie => 'Semua orang memulai dari suatu tempat.';

  @override
  String get metaDescTitleStrategist =>
      'Untuk pemain yang berpikir tiga langkah ke depan.';

  @override
  String get metaDescTitleDiceMaster => 'Dadu seolah menurutimu.';

  @override
  String get metaDescTitleRoyal => 'Khusus untuk bangsawan sejati.';

  @override
  String get metaDescTitleWeeklyChampion => 'Menyelesaikan tantangan mingguan.';

  @override
  String get metaDescBadgeFirstWin => 'Memenangkan pertandingan pertamamu.';

  @override
  String get metaDescBadgeFriendly => 'Menyelesaikan tantangan mingguan.';

  @override
  String get metaDescEmoteWave => 'Sapa semua.';

  @override
  String get metaDescEmoteThumbs => 'Bagus!';

  @override
  String get metaDescEmoteLaugh => 'Tertawa bersama.';

  @override
  String get metaDescEmoteWow => 'Barusan itu sungguhan?';

  @override
  String get metaDescEmoteCrown => 'Tunjukkan siapa penguasa papan.';

  @override
  String get metaYourFriendCode => 'Kode temanmu';

  @override
  String get metaFriendCodeHint => 'Bagikan agar teman bisa menambahkanmu.';

  @override
  String metaFriendCodeSemantics(String code) {
    return 'Kode teman: $code';
  }

  @override
  String metaShareFriendCodeMessage(String code) {
    return 'Ayo main Ludo Royale bareng! Tambahkan aku sebagai teman dengan kode: $code';
  }

  @override
  String get metaAddFriend => 'Tambah teman';

  @override
  String get metaAdd => 'Tambah';

  @override
  String get metaAddFriendTitle => 'Tambah teman';

  @override
  String get metaAddFriendHelp =>
      'Masukkan kode temanmu. Mereka bisa menemukannya di layar Teman.';

  @override
  String get metaFriendCodeLabel => 'Kode teman';

  @override
  String get metaFriendCodeHintExample => 'u_abcd 2345 wxyz';

  @override
  String get metaPaste => 'Tempel';

  @override
  String get metaSendRequest => 'Kirim permintaan';

  @override
  String get metaFriendCodeRequired => 'Masukkan kode teman.';

  @override
  String get metaInvalidFriendCode =>
      'Sepertinya itu bukan kode teman. Kode diawali u_ lalu huruf dan angka.';

  @override
  String metaRequestSent(String name) {
    return 'Permintaan pertemanan terkirim ke $name';
  }

  @override
  String metaNowFriends(String name) {
    return 'Kamu dan $name sekarang berteman!';
  }

  @override
  String get metaAlreadyFriends => 'Kalian sudah berteman.';

  @override
  String get metaTabFriends => 'Teman';

  @override
  String get metaTabRequests => 'Permintaan';

  @override
  String get metaTabRecent => 'Terbaru';

  @override
  String get metaOnline => 'Online';

  @override
  String get metaOffline => 'Offline';

  @override
  String get metaMoreActions => 'Tindakan lain';

  @override
  String get metaRemoveFriend => 'Hapus teman';

  @override
  String metaRemoveFriendTitle(String name) {
    return 'Hapus $name?';
  }

  @override
  String get metaRemoveFriendMessage =>
      'Kalian bisa saling menambahkan lagi kapan saja dengan kode teman.';

  @override
  String get metaRemove => 'Hapus';

  @override
  String metaFriendRemoved(String name) {
    return '$name dihapus dari temanmu';
  }

  @override
  String get metaIncomingRequests => 'Diterima';

  @override
  String get metaOutgoingRequests => 'Terkirim';

  @override
  String get metaWantsToBeFriends => 'Ingin berteman denganmu';

  @override
  String get metaRequestPending => 'Menunggu jawaban';

  @override
  String get metaAccept => 'Terima';

  @override
  String get metaDecline => 'Tolak';

  @override
  String get metaRequestDeclined => 'Permintaan ditolak';

  @override
  String get metaRequestCancelled => 'Permintaan dibatalkan';

  @override
  String get metaRequested => 'Diminta';

  @override
  String get metaFriendsLabel => 'Berteman';

  @override
  String get metaNoFriendsTitle => 'Belum ada teman';

  @override
  String get metaNoFriendsMessage =>
      'Bagikan kodemu atau tambah teman untuk bermain bersama.';

  @override
  String get metaNoRequestsTitle => 'Tidak ada permintaan';

  @override
  String get metaNoRequestsMessage =>
      'Permintaan pertemanan yang kamu kirim atau terima muncul di sini.';

  @override
  String get metaRecentHint =>
      'Pemain yang kamu temui di pertandingan online dalam 14 hari terakhir.';

  @override
  String get metaNoRecentTitle => 'Belum ada lawan terbaru';

  @override
  String get metaNoRecentMessage =>
      'Mainkan pertandingan online — pemain yang kamu temui akan muncul di sini.';

  @override
  String metaFriendRequestBanner(String name) {
    return '$name ingin berteman denganmu';
  }

  @override
  String get metaView => 'Lihat';

  @override
  String get metaErrorCannotFriendSelf => 'Itu kode temanmu sendiri.';

  @override
  String metaErrorFriendLimit(int max) {
    return 'Kamu bisa punya maksimal $max teman. Hapus satu teman untuk menambah yang baru.';
  }

  @override
  String get metaErrorUnknownFriendCode =>
      'Tidak ada pemain dengan kode ini. Periksa lalu coba lagi.';

  @override
  String get metaErrorRequestInProgress =>
      'Masih diproses — coba lagi sebentar lagi.';

  @override
  String get metaErrorMissionEnded =>
      'Misi ini sudah berakhir. Tarik ke bawah untuk melihat misi saat ini.';

  @override
  String get metaLeaderboardSubtitle =>
      'Kamu dan temanmu, diurutkan berdasarkan XP minggu ini.';

  @override
  String get metaLeaderboardTeaser =>
      'Lihat perkembanganmu dan teman-temanmu minggu ini.';

  @override
  String metaWeeklyXp(String xp) {
    return '$xp XP';
  }

  @override
  String metaYouName(String name) {
    return '$name (kamu)';
  }

  @override
  String metaLeaderboardRowSemantics(int rank, String name, String xp) {
    return 'Peringkat $rank: $name, $xp';
  }

  @override
  String get metaLeaderboardAlone =>
      'Tambah teman untuk melihat perbandingannya. Persaingan santai, tanpa tekanan.';

  @override
  String numberLakh(String value) {
    return '$value lakh';
  }

  @override
  String numberCrore(String value) {
    return '$value crore';
  }

  @override
  String get onboardingLanguageTitle => 'Pilih bahasamu';

  @override
  String get onboardingLanguageSubtitle =>
      'Kamu bisa mengubahnya kapan saja di Pengaturan.';

  @override
  String get onboardingPreviewLabel => 'Pratinjau';

  @override
  String get onboardingPreviewTitle => 'Selamat datang di Ludo Royale!';

  @override
  String get onboardingPreviewBody =>
      'Lempar dadu, bawa bidakmu pulang, dan rebut mahkotanya.';

  @override
  String playGameVariantTitle(String game, String variant) {
    return '$game · $variant';
  }

  @override
  String get playModeOnline => 'Online';

  @override
  String get playModePrivate => 'Ruang privat';

  @override
  String get playModePractice => 'Latihan';

  @override
  String playSeatPlayer(int seat) {
    return 'Pemain $seat';
  }

  @override
  String playNameYou(String name) {
    return '$name (kamu)';
  }

  @override
  String get playHome => 'Beranda';

  @override
  String get playBackHome => 'Kembali ke beranda';

  @override
  String get playTryAgain => 'Coba lagi';

  @override
  String playEntryFee(String fee) {
    return 'Masuk $fee';
  }

  @override
  String playEntryFeeNote(String fee) {
    return 'Biaya masuk: $fee koin per pemain, ditarik saat permainan dimulai. Pemenang mendapat seluruh pot. Gratis jika ada bot.';
  }

  @override
  String get playNotEnoughCoinsTitle => 'Koin tidak cukup';

  @override
  String playNotEnoughCoinsHint(String fee) {
    return 'Kamu butuh $fee koin untuk bermain. Kumpulkan koin dari misi lalu kembali!';
  }

  @override
  String get playSeatOpen => 'Kursi kosong';

  @override
  String get playLoadingMatch => 'Bergabung ke pertandingan…';

  @override
  String get playMatchUnavailable => 'Pertandingan ini sudah tidak tersedia.';

  @override
  String get playRoomClosed => 'Ruang telah ditutup.';

  @override
  String get playRemovedFromRoom => 'Kamu sudah tidak ada di ruang ini.';

  @override
  String get playRoomUnavailable => 'Ruang ini sudah tidak tersedia.';

  @override
  String get playLoadingRoom => 'Membuka ruang…';

  @override
  String get playGameLabel => 'Permainan';

  @override
  String get playModeLabel => 'Aturan';

  @override
  String get playPlayersLabel => 'Pemain';

  @override
  String get playVariantClassicCaption => '4 bidak · keluar markas dengan 6';

  @override
  String get playVariantQuickCaption =>
      '2 bidak · keluar markas dengan 1 atau 6';

  @override
  String get playMatchmakingTitle => 'Mencari pemain';

  @override
  String get playMatchmakingConnecting => 'Menghubungkan ke server game…';

  @override
  String get playMatchmakingJoining => 'Masuk antrean…';

  @override
  String get playMatchmakingSearching => 'Mencari lawan…';

  @override
  String get playMatchmakingStarting => 'Meja penuh! Memulai…';

  @override
  String get playMatchmakingStartsSoon =>
      'Pertandingan dimulai saat semua kursi terisi atau waktu habis.';

  @override
  String get playMatchmakingStartsWhenFull =>
      'Pertandingan dimulai begitu semua kursi terisi.';

  @override
  String playMatchmakingPlayers(int count, int capacity) {
    return '$count dari $capacity pemain bergabung';
  }

  @override
  String get playMatchmakingCancel => 'Batalkan pencarian';

  @override
  String get playMatchmakingFeeNote =>
      'Biaya masuk ditarik saat pertandingan dimulai. Pemenang mendapat seluruh pot.';

  @override
  String get playMatchmakingTimeoutTitle => 'Belum ada lawan';

  @override
  String get playMatchmakingTimeoutMessage =>
      'Tidak ada yang bergabung tepat waktu. Coba lagi, atau undang teman ke ruang privat.';

  @override
  String get playMatchmakingErrorTitle => 'Tidak dapat menemukan pertandingan';

  @override
  String get playCreateRoomTitle => 'Buat ruang privat';

  @override
  String get playCreateRoomAction => 'Buat ruang';

  @override
  String get playCreatingRoom => 'Membuat ruangmu…';

  @override
  String get playLobbyTitle => 'Ruang privat';

  @override
  String get playRoomCodeLabel => 'Kode ruang';

  @override
  String playRoomCodeA11y(String letters) {
    return 'Kode ruang $letters';
  }

  @override
  String get playCopyCode => 'Salin kode';

  @override
  String get playCodeCopied => 'Kode ruang disalin';

  @override
  String get playShareInvite => 'Bagikan undangan';

  @override
  String playInviteShareText(String game, String code) {
    return 'Ayo main $game bareng aku di Ludo Royale! Buka aplikasinya, ketuk Gabung dengan Kode, lalu masukkan: $code';
  }

  @override
  String get playInviteShareSubject => 'Undangan Ludo Royale';

  @override
  String playLobbyPlayers(int count, int capacity) {
    return 'Pemain $count/$capacity';
  }

  @override
  String get playLobbyStart => 'Mulai permainan';

  @override
  String get playLobbyWaitingForHost => 'Menunggu tuan rumah memulai…';

  @override
  String playLobbyWaitingForNamedHost(String name) {
    return 'Menunggu $name (tuan rumah) memulai…';
  }

  @override
  String get playStartBlockedNeedPlayers =>
      'Butuh minimal 2 pemain untuk mulai.';

  @override
  String get playStartBlockedConnections =>
      'Menunggu semua pemain terhubung kembali.';

  @override
  String get playStartBlockedBots => 'Bot sedang mengambil kursi…';

  @override
  String get playAllowBots => 'Izinkan bot';

  @override
  String get playAllowBotsHint =>
      'Isi kursi kosong dengan pemain komputer. Pertandingan dengan bot gratis dan tidak memberi koin.';

  @override
  String get playAddBot => 'Tambah bot';

  @override
  String get playBotJoining => 'Bot bergabung…';

  @override
  String playRemoveBotA11y(String name) {
    return 'Keluarkan $name';
  }

  @override
  String get playBotsFreeNote =>
      'Ada bot di meja: pertandingan ini gratis dan tidak memberi koin.';

  @override
  String get playInviteFriends => 'Undang teman';

  @override
  String get playInviteSheetTitle => 'Undang teman';

  @override
  String get playInviteSend => 'Undang';

  @override
  String get playInviteSent => 'Diundang';

  @override
  String get playFriendOnline => 'Online';

  @override
  String get playFriendOffline => 'Offline';

  @override
  String get playInviteEmptyTitle => 'Belum ada teman';

  @override
  String get playInviteEmptyMessage =>
      'Bagikan kode ruang saja, atau tambahkan teman dari layar Teman.';

  @override
  String get playInviteError => 'Tidak dapat memuat daftar teman.';

  @override
  String get playLeaveRoom => 'Keluar dari ruang';

  @override
  String get playLeaveRoomTitle => 'Keluar dari ruang ini?';

  @override
  String get playLeaveRoomHostMessage =>
      'Kamu tuan rumahnya. Pemain berikutnya jadi tuan rumah saat kamu keluar.';

  @override
  String get playLeaveRoomMessage =>
      'Kamu bisa kembali dengan kode ruang selama ruang masih terbuka.';

  @override
  String get playStay => 'Tetap di sini';

  @override
  String get playHostBadge => 'Tuan rumah';

  @override
  String get playJoinTitle => 'Gabung dengan kode';

  @override
  String get playJoinHint => 'Masukkan kode ruang 6 karakter dari temanmu.';

  @override
  String playJoinCodeIncomplete(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining karakter lagi',
    );
    return '$_temp0';
  }

  @override
  String get playJoinInvalidChars =>
      'Kode ruang memakai huruf A–Z dan angka 2–9 (tanpa I, O, 0, atau 1).';

  @override
  String get playJoinLookingUp => 'Mencari ruang…';

  @override
  String get playJoinAction => 'Gabung ke ruang';

  @override
  String get playJoining => 'Bergabung…';

  @override
  String playJoinPreviewHost(String name) {
    return 'Tuan rumah: $name';
  }

  @override
  String playJoinPreviewPlayers(int count, int capacity) {
    return '$count/$capacity pemain';
  }

  @override
  String get playJoinStatusOpen => 'Terbuka';

  @override
  String get playJoinStatusFull => 'Penuh';

  @override
  String get playJoinStatusInProgress => 'Sedang berlangsung';

  @override
  String get playJoinStatusClosed => 'Ditutup';

  @override
  String get playPaste => 'Tempel';

  @override
  String get playPracticeTitle => 'Latihan lawan bot';

  @override
  String get playPracticeBotsLabel => 'Bot';

  @override
  String playPracticeBotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bot',
    );
    return '$_temp0';
  }

  @override
  String get playPracticeStart => 'Mulai latihan';

  @override
  String get playPracticeNote =>
      'Latihan gratis dan tidak memberi koin. Kamu bermain melawan pemain komputer.';

  @override
  String get playPracticeSettingUp => 'Menyiapkan meja latihanmu…';

  @override
  String playPracticeBotsJoining(int seated, int total) {
    return 'Bot bergabung… $seated/$total';
  }

  @override
  String get playPracticeBotsUnavailableTitle => 'Bot sedang sibuk';

  @override
  String get playPracticeErrorTitle => 'Tidak dapat memulai latihan';

  @override
  String get playLeave => 'Keluar dari pertandingan';

  @override
  String get playTurnYourRoll => 'Giliranmu — ketuk dadunya!';

  @override
  String get playTurnPickToken => 'Pilih bidak yang menyala';

  @override
  String get playTurnYours => 'Giliranmu';

  @override
  String playTurnOther(String name) {
    return 'Giliran $name';
  }

  @override
  String get playVoidedThreeSixes =>
      'Tiga kali enam berturut-turut! Giliran berpindah.';

  @override
  String playAutoPlayed(String name) {
    return 'Waktu habis — dimainkan otomatis untuk $name';
  }

  @override
  String playForfeitLeft(String name) {
    return '$name meninggalkan pertandingan';
  }

  @override
  String playForfeitTimeouts(String name) {
    return '$name dikeluarkan setelah 3 kali melewatkan giliran';
  }

  @override
  String get playPlayerDisconnected => 'Terputus';

  @override
  String get playPlayerForfeited => 'Keluar';

  @override
  String get playPanelTurnA11y => 'giliran saat ini';

  @override
  String playStrikesA11y(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giliran terlewat',
    );
    return '$_temp0';
  }

  @override
  String playTokensHome(int home, int total) {
    return '$home dari $total bidak sampai rumah';
  }

  @override
  String playSquare(int square) {
    return 'Kotak $square';
  }

  @override
  String get playAtStart => 'Di awal';

  @override
  String get playReconnecting =>
      'Menghubungkan ulang… pertandinganmu berlanjut';

  @override
  String get playSyncing => 'Menyinkronkan papan…';

  @override
  String get playLeaveMatchTitle => 'Keluar dari pertandingan?';

  @override
  String get playLeaveMatchMessage =>
      'Keluar dihitung sebagai menyerah dan biaya masukmu tidak dikembalikan.';

  @override
  String get playLeavePracticeMessage => 'Permainan latihanmu akan berakhir.';

  @override
  String get playLeaveMatchConfirm => 'Keluar';

  @override
  String get playKeepPlaying => 'Lanjut main';

  @override
  String playRoundLabel(int round) {
    return 'Ronde $round';
  }

  @override
  String get playStartingNextRound => 'Memulai ronde berikutnya…';

  @override
  String get playChatOpen => 'Obrolan cepat';

  @override
  String get playChatTitle => 'Obrolan cepat';

  @override
  String get playChatEmotes => 'Emote';

  @override
  String get playChatMuteOthers => 'Bisukan pemain lain';

  @override
  String get playChatMutedBySettings =>
      'Obrolan cepat dibisukan di Pengaturan.';

  @override
  String playChatCooldown(int seconds) {
    return 'Pesan berikutnya dalam $seconds dtk';
  }

  @override
  String get playChatGg => 'Permainan bagus!';

  @override
  String get playChatNiceMove => 'Langkah bagus!';

  @override
  String get playChatWellPlayed => 'Main yang hebat!';

  @override
  String get playChatRematch => 'Tanding ulang?';

  @override
  String get playChatAgain => 'Ayo main lagi.';

  @override
  String get playChatGoodLuck => 'Semoga beruntung!';

  @override
  String get playChatOops => 'Ups!';

  @override
  String get playChatThanks => 'Terima kasih!';

  @override
  String get playResultYouWon => 'Kamu menang!';

  @override
  String playResultWinnerIs(String name) {
    return '$name menang!';
  }

  @override
  String get playResultGameOver => 'Permainan selesai';

  @override
  String get playResultYouForfeited => 'Kamu keluar dari pertandingan';

  @override
  String get playResultByForfeit =>
      'Pemain lain menyerah — kemenangan milikmu.';

  @override
  String get playResultWellPlayed => 'Permainan yang hebat!';

  @override
  String playResultYouFinished(int place) {
    return 'Kamu finis di posisi #$place';
  }

  @override
  String get playResultFinishingOrder => 'Urutan akhir';

  @override
  String playResultPlaceShort(int place) {
    return '$place';
  }

  @override
  String playResultPlaceA11y(int place) {
    return 'Posisi $place';
  }

  @override
  String get playRewardsTitle => 'Hadiah';

  @override
  String playRewardCoins(String amount) {
    return '+$amount koin';
  }

  @override
  String playRewardCoinsBalance(String amount) {
    return 'Dompet: $amount koin';
  }

  @override
  String get playRewardNoCoinsMatch => 'Pertandingan ini tidak memberi koin.';

  @override
  String get playRewardNoCoins =>
      'Tidak ada koin kali ini — pemenang mendapat seluruh pot.';

  @override
  String playRewardXp(int xp) {
    return '+$xp XP';
  }

  @override
  String get playRewardXpPending => 'Menghitung XP…';

  @override
  String get playRewardXpLater => 'XP-mu akan segera muncul di profil.';

  @override
  String playRewardLevelUp(int level) {
    return 'Naik level! Kamu mencapai level $level';
  }

  @override
  String get playRewardUnlocked => 'Terbuka';

  @override
  String get playRematchTitle => 'Tanding ulang';

  @override
  String get playRematchRequest => 'Ajak tanding ulang';

  @override
  String get playRematchAccept => 'Terima';

  @override
  String get playRematchDecline => 'Tolak';

  @override
  String playRematchIncoming(String name) {
    return '$name mengajak tanding ulang!';
  }

  @override
  String get playRematchWaiting => 'Kamu siap! Menunggu yang lain…';

  @override
  String get playRematchYouDeclined => 'Kamu menolak tanding ulang.';

  @override
  String get playRematchClosed => 'Tanding ulang sudah tidak tersedia.';

  @override
  String get playRematchPublicNote =>
      'Pemain yang menerima akan pindah bersama ke ruang privat baru.';

  @override
  String get playRematchStatusAccepted => 'Siap';

  @override
  String get playRematchStatusDeclined => 'Menolak';

  @override
  String get playRematchStatusPending => 'Memutuskan…';

  @override
  String get playRematchStatusOut => 'Keluar';

  @override
  String playRematchSeatA11y(String name, String status) {
    return '$name: $status';
  }

  @override
  String get playPlayAgain => 'Main lagi';

  @override
  String playInviteIncoming(String name, String game) {
    return '$name mengajakmu main $game';
  }

  @override
  String get playInviteJoin => 'Gabung';

  @override
  String get playInviteDismiss => 'Nanti saja';

  @override
  String get playInviteSomeone => 'Seorang teman';

  @override
  String get profileTitle => 'Profil';

  @override
  String get profileFriendCode => 'Kode teman';

  @override
  String get profileFriendCodeHint => 'Bagikan agar teman bisa menambahkanmu.';

  @override
  String profileShareFriendCode(String code) {
    return 'Tambahkan aku di Ludo Royale! Kode temanku $code';
  }

  @override
  String profileLevelProgress(String xp, int level) {
    return '$xp XP lagi ke level $level';
  }

  @override
  String get profileMaxLevel => 'Level maksimum tercapai';

  @override
  String get profileTitleLabel => 'Gelar';

  @override
  String get profileAccountSection => 'Akun';

  @override
  String get profileAccountType => 'Jenis akun';

  @override
  String get profileAccountGuest => 'Tamu (belum disimpan)';

  @override
  String get profileAccountLinked => 'Akun tersimpan';

  @override
  String get profileLinkedAccounts => 'Metode masuk';

  @override
  String get profileLinked => 'Tertaut';

  @override
  String get profileNotLinked => 'Belum tertaut';

  @override
  String get profileSaveProgressCta => 'Simpan progres';

  @override
  String get profileTotalXp => 'Total XP';

  @override
  String get profileStatsSection => 'Progres';

  @override
  String get profileEditNameTooltip => 'Ubah nama';

  @override
  String get profileEditNameTitle => 'Ganti namamu';

  @override
  String get profileNameLabel => 'Nama tampilan';

  @override
  String get profileNameRules =>
      '3–16 karakter. Boleh huruf, angka, spasi, _ . dan -.';

  @override
  String get profileNameNote =>
      'Teman, papan peringkat, dan game baru akan menampilkan nama barumu. Game yang sedang berjalan tetap memakai nama lama.';

  @override
  String profileNameCounterSemantics(int count, int max) {
    return '$count dari $max karakter';
  }

  @override
  String profileNameSaved(String name) {
    return 'Namamu sekarang $name';
  }

  @override
  String get profileNameChangeLimit =>
      'Kamu terlalu sering mengganti nama. Silakan coba lagi nanti.';

  @override
  String profileNameChangeLimitRetry(String wait) {
    return 'Kamu terlalu sering mengganti nama. Coba lagi dalam $wait.';
  }

  @override
  String get settingsTitle => 'Pengaturan';

  @override
  String get settingsAppearance => 'Tampilan';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeLight => 'Terang';

  @override
  String get settingsThemeDark => 'Gelap';

  @override
  String get settingsThemeSystem => 'Sistem';

  @override
  String get settingsLanguage => 'Bahasa';

  @override
  String get settingsSoundAndHaptics => 'Suara & getaran';

  @override
  String get settingsSound => 'Suara';

  @override
  String get settingsSoundSubtitle => 'Musik dan efek suara';

  @override
  String get settingsSfxVolume => 'Volume efek suara';

  @override
  String get settingsMusicVolume => 'Volume musik';

  @override
  String get settingsHaptics => 'Getaran';

  @override
  String get settingsReducedMotion => 'Kurangi gerakan';

  @override
  String get settingsReducedMotionSubtitle => 'Lebih sedikit animasi dan efek';

  @override
  String get settingsReducedMotionSystemOn =>
      'Juga aktif di pengaturan perangkatmu';

  @override
  String get settingsGameplay => 'Permainan';

  @override
  String get settingsQuickChatMute => 'Bisukan obrolan cepat';

  @override
  String get settingsQuickChatMuteSubtitle =>
      'Sembunyikan pesan obrolan dan emote pemain lain';

  @override
  String get settingsPrivacy => 'Privasi';

  @override
  String get settingsAnalytics => 'Bagikan statistik penggunaan anonim';

  @override
  String get settingsAnalyticsSubtitle =>
      'Membantu kami meningkatkan game. Tidak pernah menyertakan nama, obrolan, atau kode ruangmu.';

  @override
  String get settingsAnalyticsNotConfigured => 'Tidak tersedia di build ini';

  @override
  String get settingsAccount => 'Akun';

  @override
  String settingsSignedInAs(String name) {
    return 'Masuk sebagai $name';
  }

  @override
  String get settingsSaveProgress => 'Simpan progres';

  @override
  String get settingsSaveProgressSubtitle =>
      'Tautkan metode masuk agar progresmu aman';

  @override
  String get settingsSwitchToGuest => 'Kembali ke akun tamu';

  @override
  String get settingsSwitchToGuestSubtitle =>
      'Kembali ke akun tamu yang tersimpan di perangkat ini';

  @override
  String get settingsSignOut => 'Keluar';

  @override
  String get settingsDeleteAccount => 'Hapus akun';

  @override
  String get settingsDeleteAccountSubtitle =>
      'Hapus akun dan datanya secara permanen';

  @override
  String get settingsAbout => 'Tentang';

  @override
  String get settingsVersion => 'Versi';

  @override
  String get settingsLegalNotices => 'Pemberitahuan hukum';

  @override
  String get settingsLegalNoticesSubtitle =>
      'Lisensi sumber terbuka · dibuka di browser Anda';

  @override
  String get settingsLegalNoticesOpenFailed =>
      'Halaman tidak dapat dibuka. Coba lagi nanti.';

  @override
  String get settingsConsentTitle =>
      'Bantu kami membuat Ludo Royale lebih baik';

  @override
  String get settingsConsentMessage =>
      'Bolehkah kami mengumpulkan statistik penggunaan anonim, seperti mode permainan yang populer? Kami tidak pernah mengumpulkan nama, obrolan, kode ruang, atau detail kontakmu. Kamu bisa mengubahnya kapan saja di Pengaturan.';

  @override
  String get settingsConsentAllow => 'Bagikan statistik anonim';

  @override
  String get settingsConsentDeny => 'Tidak, terima kasih';

  @override
  String get socialPodOptionsHint => 'Lihat opsi pemain';

  @override
  String get socialRequestSent => 'Permintaan terkirim';

  @override
  String get socialAcceptRequest => 'Terima permintaan';

  @override
  String get socialReportPlayer => 'Laporkan pemain';

  @override
  String get socialReported => 'Dilaporkan';

  @override
  String get socialAlreadyReported =>
      'Kamu sudah melaporkan pemain ini dalam 24 jam terakhir.';

  @override
  String socialReportsLeft(int remaining, int total) {
    return 'Sisa laporan hari ini: $remaining dari $total';
  }

  @override
  String socialReportLimitAt(int total, String time) {
    return 'Kamu sudah memakai $total laporan hari ini. Kamu bisa melapor lagi pukul $time.';
  }

  @override
  String socialReportLimitLater(int total) {
    return 'Kamu sudah memakai $total laporan hari ini. Coba lagi nanti.';
  }

  @override
  String socialReportTitle(String name) {
    return 'Laporkan $name';
  }

  @override
  String get socialReportWhy => 'Apa yang terjadi?';

  @override
  String get socialReasonCheating => 'Curang';

  @override
  String get socialReasonOffensiveName => 'Nama yang menyinggung';

  @override
  String get socialReasonAbusiveBehavior => 'Perilaku kasar';

  @override
  String get socialReasonLeavingOrStalling =>
      'Keluar atau sengaja mengulur waktu';

  @override
  String get socialReasonOther => 'Lainnya';

  @override
  String get socialReportReviewNote =>
      'Tim kami meninjau setiap laporan. Pantau statusnya di tab Dilaporkan pada layar Teman.';

  @override
  String get socialSendReport => 'Kirim laporan';

  @override
  String socialReportSent(int remaining, int total) {
    return 'Laporan terkirim. Sisa $remaining dari $total laporan hari ini.';
  }

  @override
  String socialFriendLimitNote(int max) {
    return 'Kamu bisa punya maksimal $max teman — hapus satu untuk menambah yang baru.';
  }

  @override
  String get socialErrorCannotReportSelf =>
      'Kamu tidak bisa melaporkan diri sendiri.';

  @override
  String get socialErrorCannotReportBot => 'Pemain ini tidak bisa dilaporkan.';

  @override
  String get socialErrorNotInRoom =>
      'Kamu hanya bisa melaporkan pemain dari pertandingan yang kamu ikuti.';

  @override
  String get socialErrorRoomNotFound =>
      'Pertandingan ini sudah tidak ditemukan, jadi laporan tidak terkirim.';

  @override
  String get socialErrorPlayerNotFound => 'Pemain ini tidak ditemukan.';

  @override
  String get socialTabReported => 'Dilaporkan';

  @override
  String socialOnlineNow(int count) {
    return 'Online sekarang ($count)';
  }

  @override
  String socialOfflineCount(int count) {
    return 'Offline ($count)';
  }

  @override
  String socialFriendsCount(int count, int max) {
    return 'Teman $count/$max';
  }

  @override
  String socialReportsResetAt(String time) {
    return 'Kamu bisa melapor lagi pukul $time.';
  }

  @override
  String socialReportsInfo(int total) {
    return 'Kamu bisa melaporkan maksimal $total pemain per hari. Tim kami meninjau setiap laporan.';
  }

  @override
  String get socialNoReportsTitle => 'Belum ada laporan';

  @override
  String get socialNoReportsMessage =>
      'Pemain yang kamu laporkan dari pertandingan akan muncul di sini beserta status setiap laporan.';

  @override
  String get socialStatusSubmitted => 'Terkirim';

  @override
  String get socialStatusReviewing => 'Sedang ditinjau';

  @override
  String get socialStatusActionTaken => 'Sudah ditindak';

  @override
  String get socialStatusDismissed => 'Ditolak';

  @override
  String get socialJustNow => 'Baru saja';

  @override
  String socialMinutesAgo(int minutes) {
    return '$minutes mnt lalu';
  }

  @override
  String socialHoursAgo(int hours) {
    return '$hours jam lalu';
  }

  @override
  String get socialYesterday => 'Kemarin';

  @override
  String socialReportStatusA11y(String status) {
    return 'Status: $status';
  }

  @override
  String get walletTitle => 'Dompetmu';

  @override
  String get walletCoinsCaption =>
      'Untuk biaya masuk pertandingan — pemenang ambil semua.';

  @override
  String get walletDiamondsCaption =>
      'Untuk kosmetik premium di Ruang Koleksi.';

  @override
  String walletExactBalance(String amount) {
    return 'Saldo pasti: $amount';
  }

  @override
  String get walletVirtualTitle => 'Mata uang virtual';

  @override
  String get walletVirtualNotice =>
      'Koin dan berlian adalah item virtual untuk bersenang-senang. Tidak memiliki nilai nyata dan tidak bisa dijual, dipindahkan, ditarik, atau ditukar dengan uang.';

  @override
  String get walletEarnTitle => 'Cara dapat lebih banyak';

  @override
  String get walletEarnWins => 'Menangkan pertandingan untuk ambil semua';

  @override
  String get walletEarnMissions => 'Selesaikan misi harian dan mingguan';

  @override
  String get walletEarnLevels => 'Naik level untuk hadiah pencapaian';

  @override
  String get walletRefresh => 'Muat ulang saldo';

  @override
  String widgetsCoinsBalance(String amount) {
    return 'Koin: $amount';
  }

  @override
  String widgetsDiamondsBalance(String amount) {
    return 'Berlian: $amount';
  }

  @override
  String widgetsXpLabel(String current, String total) {
    return 'Pengalaman: $current dari $total';
  }

  @override
  String get widgetsAvatarLabel => 'Avatar pemain';

  @override
  String widgetsTitleLabel(String title) {
    return 'Gelar: $title';
  }

  @override
  String widgetsEmoteLabel(String name) {
    return 'Emote: $name';
  }

  @override
  String widgetsBadgeLabel(String name) {
    return 'Lencana: $name';
  }

  @override
  String widgetsSecondsLeft(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds detik lagi',
    );
    return '$_temp0';
  }

  @override
  String widgetsConnectionLabel(String status) {
    return 'Koneksi: $status';
  }

  @override
  String widgetsNewItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count baru',
    );
    return '$_temp0';
  }

  @override
  String get widgetsSelected => 'Dipilih';

  @override
  String widgetsLogoLabel(String appName) {
    return 'Lambang $appName';
  }
}
