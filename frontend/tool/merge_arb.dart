// Merges per-area ARB fragments (lib/l10n/parts/<area>/<locale>.arb) into
// lib/l10n/app_<locale>.arb, the inputs of `flutter gen-l10n`.
//
// Fails when a key is defined twice, when a locale is missing a key that the
// English template defines, or when a fragment is not valid JSON.
//
// Usage: dart run tool/merge_arb.dart
import 'dart:convert';
import 'dart:io';

const locales = ['en', 'hi', 'ur', 'id', 'ar'];

void main() {
  final partsDir = Directory('lib/l10n/parts');
  final areas = partsDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final merged = {for (final l in locales) l: <String, dynamic>{'@@locale': l}};
  final owner = <String, String>{};
  var failed = false;

  for (final area in areas) {
    final areaName = area.uri.pathSegments.where((s) => s.isNotEmpty).last;
    for (final locale in locales) {
      final file = File('${area.path}/$locale.arb');
      if (!file.existsSync()) {
        stderr.writeln('missing fragment: ${file.path}');
        failed = true;
        continue;
      }
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } on FormatException catch (e) {
        stderr.writeln('invalid JSON in ${file.path}: ${e.message}');
        failed = true;
        continue;
      }
      for (final entry in json.entries) {
        if (entry.key == '@@locale') continue;
        if (locale == 'en' && !entry.key.startsWith('@')) {
          final previous = owner[entry.key];
          if (previous != null) {
            stderr.writeln('duplicate key "${entry.key}" in $areaName and $previous');
            failed = true;
          }
          owner[entry.key] = areaName;
        }
        merged[locale]![entry.key] = entry.value;
      }
    }
  }

  final templateKeys =
      merged['en']!.keys.where((k) => !k.startsWith('@')).toSet();
  for (final locale in locales.where((l) => l != 'en')) {
    final keys = merged[locale]!.keys.where((k) => !k.startsWith('@')).toSet();
    for (final missing in templateKeys.difference(keys)) {
      stderr.writeln('[$locale] missing translation for "$missing" (${owner[missing]})');
      failed = true;
    }
    for (final extra in keys.difference(templateKeys)) {
      stderr.writeln('[$locale] key "$extra" is not in the English template');
      failed = true;
    }
  }
  if (failed) exit(1);

  const encoder = JsonEncoder.withIndent('  ');
  for (final locale in locales) {
    File('lib/l10n/app_$locale.arb')
        .writeAsStringSync('${encoder.convert(merged[locale])}\n');
  }
  stdout.writeln('Merged ${templateKeys.length} keys from ${areas.length} areas into ${locales.length} locales.');
}
