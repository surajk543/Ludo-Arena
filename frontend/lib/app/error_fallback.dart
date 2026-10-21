import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/widgets/brand_logo.dart';

/// In release and profile builds, replaces the framework's error widget
/// (shown in place of a widget whose build failed) with a small branded,
/// localized "Something went wrong" — no stack trace or framework text.
/// Debug builds keep the default red error screen for developers.
///
/// [release] defaults to the build mode; tests pass it explicitly.
void installErrorWidget({bool release = !kDebugMode}) {
  if (!release) return;
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      const AppErrorFallback();
}

/// Self-contained so it can render anywhere in the tree: it needs no theme
/// extension, no Localizations ancestor (falls back to English), no
/// Directionality and no bounded constraints, and never throws itself.
class AppErrorFallback extends StatelessWidget {
  const AppErrorFallback({super.key});

  static String _message(BuildContext context) {
    try {
      final l10n =
          Localizations.of<AppLocalizations>(context, AppLocalizations) ??
          lookupAppLocalizations(const Locale('en'));
      return l10n.commonSomethingWentWrong;
    } catch (_) {
      return 'Something went wrong.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    return Directionality(
      textDirection: direction,
      child: ColoredBox(
        color: dark ? BrandPalette.royal900 : BrandPalette.royal50,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CustomPaint(
                    size: Size(40, 43.2),
                    painter: BrandCrestPainter(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _message(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                      color: dark
                          ? BrandPalette.royal100
                          : BrandPalette.royal700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
