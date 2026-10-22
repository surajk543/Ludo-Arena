import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/legal/bundled_licenses.dart';

import '../../tool/export_oss_notices.dart' as tool;

final String _sep = '\n${'-' * 80}\n';

/// Same layout as a build's NOTICES: names (one per line), blank line,
/// verbatim text; entries separated by a line of 80 '-'.
final String _fixture = [
  'alpha\n\nAlpha License\n\n  Indented <b>clause</b> & "quotes" \'single\'\n',
  'beta\ngamma\n\nShared license text.\nSecond line.',
  'no blank line here, so no package names',
].join(_sep);

void main() {
  test('parses entries, names and verbatim texts like LicenseRegistry', () {
    final entries = tool.parseNotices(_fixture);
    expect(entries, hasLength(3));
    expect(entries[0].packages, ['alpha']);
    expect(
      entries[0].text,
      'Alpha License\n\n  Indented <b>clause</b> & "quotes" \'single\'\n',
    );
    expect(entries[1].packages, ['beta', 'gamma']);
    expect(entries[1].text, 'Shared license text.\nSecond line.');
    expect(entries[2].packages, isEmpty);
    expect(entries[2].text, 'no blank line here, so no package names');
  });

  test('decodes gzip (NOTICES.Z), zlib and plain input identically', () {
    final bytes = utf8.encode(_fixture);
    expect(tool.decodeNotices(gzip.encode(bytes)), _fixture);
    expect(tool.decodeNotices(zlib.encode(bytes)), _fixture);
    expect(tool.decodeNotices(bytes), _fixture);
    expect(tool.parseNotices(tool.decodeNotices(gzip.encode(bytes))), [
      ...tool.parseNotices(_fixture),
    ]);
  });

  test('CRLF input parses like LF input', () {
    final crlf = _fixture.replaceAll('\n', '\r\n');
    expect(tool.parseNotices(crlf), tool.parseNotices(_fixture));
  });

  test('renders an escaped, neutral, deterministic page', () {
    final entries = tool.parseNotices(_fixture);
    final html = tool.renderHtml(entries, appVersion: '1.2.3+4');
    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('<title>Ludo Arena — Open-source notices</title>'));
    expect(html, contains('app version 1.2.3+4'));
    // Texts are reproduced verbatim, HTML-escaped inside <pre>.
    expect(
      html,
      contains(
        '<pre>Alpha License\n\n  Indented &lt;b&gt;clause&lt;/b&gt; &amp; '
        '&quot;quotes&quot; &#39;single&#39;\n</pre>',
      ),
    );
    expect(html, contains('<h2><span class="num">2.</span> beta, gamma</h2>'));
    expect(html, contains('<a href="#n2">gamma</a>'));
    expect(html, contains('(unnamed)'));
    // No scripts, no external resources (the backend sends CSP
    // default-src 'none'; style-src 'unsafe-inline').
    expect(html, isNot(contains('<script')));
    expect(html, isNot(contains('src=')));
    expect(html, isNot(contains('<link')));
    expect(tool.renderHtml(entries, appVersion: '1.2.3+4'), html);
  });

  test('merging de-duplicates identical entries and keeps order', () {
    final a = tool.parseNotices(_fixture);
    final merged = tool.mergeEntries([a, a.reversed.toList()]);
    expect(merged, a);
  });

  test('every bundled font license exists, is bundled and is exported', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final path in bundledFontLicenses.values) {
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(pubspec, contains('- $path'), reason: '$path not bundled');
    }
    final fonts = tool.fontLicenseEntries();
    expect(fonts.map((e) => e.packages.single), bundledFontLicenses.keys);
    for (final e in fonts) {
      expect(e.text, contains('SIL OPEN FONT LICENSE'));
    }
    // Every font family declared in pubspec has a license entry.
    final families = RegExp(
      r'^\s+- family: (\S+)\s*$',
      multiLine: true,
    ).allMatches(pubspec).map((m) => m.group(1)!);
    final licensed = bundledFontLicenses.keys
        .map((k) => k.replaceAll(' ', ''))
        .toSet();
    for (final family in families) {
      expect(licensed, contains(family), reason: '$family has no license');
    }
  });

  test('the committed notices page contains the font licenses', () {
    final page = File('../backend/config/legal/open-source-notices.html');
    expect(page.existsSync(), isTrue);
    final html = page.readAsStringSync();
    expect(html, contains('<title>Ludo Arena — Open-source notices</title>'));
    for (final name in bundledFontLicenses.keys) {
      expect(html, contains('</span> $name</h2>'), reason: name);
    }
  });
}
