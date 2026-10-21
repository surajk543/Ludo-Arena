import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import 'gate_illustrations.dart';
import 'gate_layout.dart';

/// Shown for paths that are not registered in this build (e.g. a feature
/// route not shipped yet). Always offers a way back home.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GateLayout(
      art: GateArt.notFound,
      title: l10n.gateNotFoundTitle,
      message: l10n.gateNotFoundMessage,
      actions: [
        PremiumButton(
          label: l10n.gateGoHome,
          icon: Icons.home_rounded,
          onPressed: () => context.go(AppRoutes.home),
        ),
      ],
    );
  }
}
