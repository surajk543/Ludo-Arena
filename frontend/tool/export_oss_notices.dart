// Exports the app's open-source notices as a static HTML page served by the
// backend at GET /legal/open-source (Settings > About > Legal notices opens
// it in the browser). The app itself shows no license page.
//
// Input: the NOTICES file of a build (gzip/zlib-compressed `NOTICES.Z`, or
// plain text) — the exact license texts the build collected from every
// package and the engine — plus the bundled font licenses
// (lib/core/legal/bundled_licenses.dart). Every license text is reproduced
// verbatim.
//
// Usage (from frontend/), before each release:
//   flutter build bundle --release
//   dart run tool/export_oss_notices.dart
//
// Options:
//   --notices <path>   NOTICES(.Z) to read; repeatable (entries are merged and
//                      de-duplicated). Default: the first existing of
//                      [defaultNoticesPaths].
//   --out <path>       Default: ../backend/config/legal/open-source-notices.html
//   --check            Exit 1 if --out differs from what would be written.
import 'dart:convert';
import 'dart:io';

import 'package:ludo_royale/core/legal/bundled_licenses.dart';

const String pageTitle = 'Ludo Royale — Open-source notices';

const List<String> defaultNoticesPaths = [
  'build/flutter_assets/NOTICES.Z',
  'build/app/intermediates/flutter/release/flutter_assets/NOTICES.Z',
  'build/ios/iphoneos/Runner.app/Frameworks/App.framework/flutter_assets/NOTICES.Z',
];

const String defaultOut = '../backend/config/legal/open-source-notices.html';

/// Separator between entries in a NOTICES file (same as the framework's
/// LicenseRegistry parser).
final String noticesSeparator = '\n${'-' * 80}\n';

/// One license entry: the components it covers and its verbatim text.
class NoticeEntry {
  const NoticeEntry(this.packages, this.text);

  final List<String> packages;
  final String text;

  String get _key => '${packages.join('\n')}\n\n$text';

  @override
  bool operator ==(Object other) => other is NoticeEntry && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}

/// Decodes NOTICES bytes: gzip (`NOTICES.Z`), zlib, or plain UTF-8.
String decodeNotices(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
    return utf8.decode(gzip.decode(bytes));
  }
  if (bytes.length >= 2 &&
      bytes[0] == 0x78 &&
      const [0x01, 0x5E, 0x9C, 0xDA].contains(bytes[1])) {
    return utf8.decode(zlib.decode(bytes));
  }
  return utf8.decode(bytes);
}

/// Parses a NOTICES file exactly like the framework's LicenseRegistry:
/// entries separated by a line of 80 '-', each "names\n\ntext" where names
/// are one per line.
List<NoticeEntry> parseNotices(String raw) {
  final text = raw.replaceAll('\r\n', '\n');
  final out = <NoticeEntry>[];
  for (final chunk in text.split(noticesSeparator)) {
    if (chunk.trim().isEmpty) continue;
    final split = chunk.indexOf('\n\n');
    if (split >= 0) {
      out.add(
        NoticeEntry(
          chunk
              .substring(0, split)
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList(),
          chunk.substring(split + 2),
        ),
      );
    } else {
      out.add(NoticeEntry(const [], chunk));
    }
  }
  return out;
}

String escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// Renders the notices page. Deterministic (no timestamps) so regenerating
/// without dependency changes produces no diff.
String renderHtml(List<NoticeEntry> entries, {String? appVersion}) {
  final b = StringBuffer()
    ..writeln('<!doctype html>')
    ..writeln('<html lang="en">')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
    )
    ..writeln('<meta name="color-scheme" content="light dark">')
    ..writeln('<title>${escapeHtml(pageTitle)}</title>')
    ..writeln('<style>$_css</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<header>')
    ..writeln('<h1>${escapeHtml(pageTitle)}</h1>')
    ..writeln(
      '<p>Ludo Royale includes open-source software and fonts. The '
      'license and notice texts of every third-party component in the app '
      'are reproduced below, unmodified.</p>',
    )
    ..writeln(
      '<p class="meta">${entries.length} notices'
      '${appVersion == null ? '' : ' · app version ${escapeHtml(appVersion)}'}'
      '</p>',
    )
    ..writeln('</header>');

  // Index: every component name, linking to the entries that cover it.
  final index = <String, List<int>>{};
  for (var i = 0; i < entries.length; i++) {
    final names = entries[i].packages.isEmpty
        ? const ['(unnamed)']
        : entries[i].packages;
    for (final name in names) {
      (index[name] ??= []).add(i + 1);
    }
  }
  final names = index.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  b
    ..writeln('<nav aria-label="Components">')
    ..writeln('<h2>Components (${names.length})</h2>')
    ..writeln('<ul class="index">');
  for (final name in names) {
    final refs = index[name]!;
    b.write('<li>');
    if (refs.length == 1) {
      b.write('<a href="#n${refs.first}">${escapeHtml(name)}</a>');
    } else {
      b.write(escapeHtml(name));
      b.write(' ');
      b.write(refs.map((r) => '<a href="#n$r">[$r]</a>').join(' '));
    }
    b.writeln('</li>');
  }
  b
    ..writeln('</ul>')
    ..writeln('</nav>')
    ..writeln('<main>');
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final title = e.packages.isEmpty ? '(unnamed)' : e.packages.join(', ');
    b
      ..writeln('<section id="n${i + 1}">')
      ..writeln(
        '<h2><span class="num">${i + 1}.</span> ${escapeHtml(title)}</h2>',
      )
      ..writeln('<pre>${escapeHtml(e.text)}</pre>')
      ..writeln('</section>');
  }
  b
    ..writeln('</main>')
    ..writeln('</body>')
    ..writeln('</html>');
  return b.toString();
}

const String _css =
    ':root{color-scheme:light dark;--bg:#fbfaff;--fg:#1d1733;--muted:#5d5675;'
    '--line:#e3def3;--card:#ffffff;--link:#4b32b8}'
    '@media (prefers-color-scheme:dark){:root{--bg:#120d24;--fg:#ece8fa;'
    '--muted:#a9a2c2;--line:#2c2447;--card:#191233;--link:#b7a6ff}}'
    '*{box-sizing:border-box}'
    'body{margin:0 auto;max-width:960px;padding:24px 16px 64px;'
    'background:var(--bg);color:var(--fg);'
    'font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,'
    'Helvetica,Arial,sans-serif}'
    'h1{font-size:1.6rem;margin:0 0 8px}'
    'h2{font-size:1.05rem;margin:0 0 8px;overflow-wrap:anywhere}'
    'a{color:var(--link)}'
    '.meta,.num{color:var(--muted)}'
    'nav,section{background:var(--card);border:1px solid var(--line);'
    'border-radius:12px;padding:16px;margin:16px 0}'
    '.index{columns:16rem;margin:0;padding-left:18px}'
    '.index li{break-inside:avoid;overflow-wrap:anywhere}'
    'pre{white-space:pre-wrap;overflow-wrap:anywhere;margin:0;'
    'font:12.5px/1.45 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}';

/// Reads `version:` from pubspec.yaml (no YAML dependency needed).
String? readAppVersion([String path = 'pubspec.yaml']) {
  final f = File(path);
  if (!f.existsSync()) return null;
  final m = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(f.readAsStringSync());
  return m?.group(1);
}

/// Loads the bundled font licenses as entries (file contents verbatim).
List<NoticeEntry> fontLicenseEntries({String root = '.'}) => [
  for (final e in bundledFontLicenses.entries)
    NoticeEntry([e.key], File('$root/${e.value}').readAsStringSync()),
];

/// Merges entry lists keeping the first occurrence of each identical entry.
List<NoticeEntry> mergeEntries(Iterable<List<NoticeEntry>> lists) {
  final seen = <NoticeEntry>{};
  return [
    for (final list in lists)
      for (final e in list)
        if (seen.add(e)) e,
  ];
}

void main(List<String> args) {
  final notices = <String>[];
  var out = defaultOut;
  var check = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--notices' when i + 1 < args.length:
        notices.add(args[++i]);
      case '--out' when i + 1 < args.length:
        out = args[++i];
      case '--check':
        check = true;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exit(64);
    }
  }
  if (notices.isEmpty) {
    final found = defaultNoticesPaths.where((p) => File(p).existsSync());
    if (found.isEmpty) {
      stderr.writeln(
        'No NOTICES found. Run `flutter build bundle --release` first, or '
        'pass --notices <path to NOTICES.Z>.',
      );
      exit(66);
    }
    notices.add(found.first);
  }

  final lists = <List<NoticeEntry>>[];
  for (final path in notices) {
    final entries = parseNotices(decodeNotices(File(path).readAsBytesSync()));
    if (entries.isEmpty) {
      stderr.writeln('$path contains no notices');
      exit(65);
    }
    stdout.writeln('read ${entries.length} notices from $path');
    lists.add(entries);
  }
  lists.add(fontLicenseEntries());
  final entries = mergeEntries(lists);
  final html = renderHtml(entries, appVersion: readAppVersion());

  final file = File(out);
  if (check) {
    final same = file.existsSync() && file.readAsStringSync() == html;
    stdout.writeln(same ? '$out is up to date' : '$out is out of date');
    exit(same ? 0 : 1);
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(html);
  stdout.writeln(
    'wrote $out (${entries.length} notices, ${html.length} chars)',
  );
}
