/// Licenses of bundled third-party assets that are not Dart packages, so the
/// build's `NOTICES` does not contain them: the SIL Open Font License 1.1
/// texts of the app fonts (family name -> license asset).
///
/// The license files ship inside the app next to the fonts (OFL requirement)
/// and `tool/export_oss_notices.dart` appends them to the published
/// open-source notices page. Plain Dart (no Flutter imports) so that tool can
/// import it.
const Map<String, String> bundledFontLicenses = {
  'Fredoka': 'assets/fonts/OFL-Fredoka.txt',
  'Nunito': 'assets/fonts/OFL-Nunito.txt',
  'Baloo 2': 'assets/fonts/OFL-Baloo2.txt',
  'Baloo Bhaijaan 2': 'assets/fonts/OFL-BalooBhaijaan2.txt',
};
