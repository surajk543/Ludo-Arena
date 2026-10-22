import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_arena/app/app.dart';
import 'package:ludo_arena/app/gate/app_gate_controller.dart';
import 'package:ludo_arena/app/offline/offline_block_controller.dart';
import 'package:ludo_arena/app/offline/offline_blocking_host.dart';
import 'package:ludo_arena/core/audio_haptics/reduced_motion.dart';
import 'package:ludo_arena/core/lifecycle/app_lifecycle.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/core/realtime/realtime_providers.dart';
import 'package:ludo_arena/core/state/in_match_provider.dart';
import 'package:ludo_arena/core/storage/preferences_store.dart';
import 'package:ludo_arena/core/theme/app_theme.dart';
import 'package:ludo_arena/features/ludo/presentation/screens/ludo_game_screen.dart';
import 'package:ludo_arena/l10n/generated/app_localizations.dart';

import '../core/protocol/fixtures.dart';
import '../core/realtime/fakes.dart';
import '../helpers/harness.dart';
import '../helpers/screen_harness.dart';

const _grace = OfflineBlockController.showAfter;
const _minVisible = OfflineBlockController.minVisible;
const _title = 'Connection lost';

/// Gate pinned to a phase (the real one needs the whole startup sequence).
class _Gate extends AppGateController {
  _Gate(this._initial);

  final GatePhase _initial;

  @override
  GateState build() => GateState(phase: _initial);

  void setPhase(GatePhase phase) => state = GateState(phase: phase);
}

class _Probe {
  int taps = 0;
  final navigation = <bool>[];
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.probe});

  final String title;
  final _Probe probe;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      children: [
        TextButton(onPressed: () => probe.taps++, child: const Text('Under')),
        const TextField(key: Key('field')),
        TextButton(
          onPressed: () => context.push('/second'),
          child: const Text('Open second'),
        ),
      ],
    ),
  );
}

class _Harness {
  _Harness(this.container, this.probe);

  final ProviderContainer container;
  final _Probe probe;

  void status(RealtimeStatus s) =>
      container.read(realtimeStatusProvider.notifier).set(s);

  void phase(GatePhase p) =>
      (container.read(appGateControllerProvider.notifier) as _Gate).setPhase(p);

  bool get blocked => container.read(offlineBlockProvider);
}

/// A small router app with the host installed like `app.dart` does.
Future<_Harness> _pump(
  WidgetTester tester, {
  TestEnv? env,
  GatePhase phase = GatePhase.ready,
  RealtimeStatus status = RealtimeStatus.connected,
  Locale locale = const Locale('en'),
  Size size = Viewports.phone,
  double textScale = 1,
  bool reduceMotion = true,
  bool inMatch = false,
}) async {
  setViewportSize(tester, size);
  final e = env ?? await TestEnv.create();
  final probe = _Probe();
  final container = e.container(
    extra: [appGateControllerProvider.overrideWith(() => _Gate(phase))],
  );
  addTearDown(container.dispose);
  container.read(realtimeStatusProvider.notifier).set(status);
  container.read(inMatchProvider.notifier).set(inMatch);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => _Page(title: 'Home page', probe: probe),
      ),
      GoRoute(
        path: '/second',
        builder: (_, _) => _Page(title: 'Second page', probe: probe),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        onNavigationNotification: (n) {
          probe.navigation.add(n.canHandlePop);
          return true;
        },
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: ReducedMotionScope(
            child: OfflineBlockingHost(
              backButtonDispatcher: router.backButtonDispatcher,
              child: child!,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _Harness(container, probe);
}

/// Drops the connection and waits until the overlay is up (and past its
/// minimum on-screen time, so no timer is left pending).
Future<void> _block(WidgetTester tester, _Harness h) async {
  h.status(RealtimeStatus.reconnecting);
  await tester.pump(_grace);
  await tester.pump(_minVisible);
  expect(find.byType(OfflineBlockingOverlay), findsOneWidget);
}

/// Connected again: waits until the overlay is gone.
Future<void> _unblock(WidgetTester tester, _Harness h) async {
  h.status(RealtimeStatus.connected);
  await tester.pump();
  await tester.pump();
  expect(find.byType(OfflineBlockingOverlay), findsNothing);
}

void main() {
  group('when it shows', () {
    testWidgets('after the grace period of a lost connection, not before; '
        'cleared on reconnect after the minimum on-screen time', (
      tester,
    ) async {
      final h = await _pump(tester);
      h.status(RealtimeStatus.reconnecting);
      await tester.pump(_grace - const Duration(milliseconds: 1));
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
      expect(h.blocked, isFalse);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(h.blocked, isTrue);
      expect(find.text(_title), findsOneWidget);
      expect(
        find.text(
          "Reconnecting… You can continue as soon as you're back online.",
        ),
        findsOneWidget,
      );
      expect(find.text('Try now'), findsOneWidget);
      // The match hint is only for matches.
      expect(
        find.text(
          'Your match keeps running. Missed turns are played for you '
          'automatically.',
        ),
        findsNothing,
      );

      // Back immediately: the overlay stays for its minimum time.
      h.status(RealtimeStatus.connected);
      await tester.pump(_minVisible - const Duration(milliseconds: 50));
      expect(find.byType(OfflineBlockingOverlay), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
      expect(h.blocked, isFalse);
    });

    testWidgets('a blip shorter than the grace period never shows it', (
      tester,
    ) async {
      final h = await _pump(tester);
      h.status(RealtimeStatus.reconnecting);
      await tester.pump(const Duration(milliseconds: 600));
      h.status(RealtimeStatus.connected);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
    });

    testWidgets('stays up while the socket retries (connecting between '
        'attempts) until connected', (tester) async {
      final h = await _pump(tester);
      await _block(tester, h);
      h.status(RealtimeStatus.connecting);
      await tester.pump(const Duration(seconds: 2));
      h.status(RealtimeStatus.offline);
      await tester.pump(const Duration(seconds: 2));
      h.status(RealtimeStatus.reconnecting);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(OfflineBlockingOverlay), findsOneWidget);
      h.status(RealtimeStatus.connected);
      await tester.pump(_minVisible);
      await tester.pump();
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
    });

    testWidgets('the first connection attempt after sign-in does not block', (
      tester,
    ) async {
      final h = await _pump(tester, status: RealtimeStatus.idle);
      h.status(RealtimeStatus.connecting);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
    });

    testWidgets('a connection that fails from the start blocks too', (
      tester,
    ) async {
      final h = await _pump(tester, status: RealtimeStatus.connecting);
      // Handshake failed: backing off, then the next attempt.
      h.status(RealtimeStatus.reconnecting);
      await tester.pump(const Duration(milliseconds: 300));
      h.status(RealtimeStatus.connecting);
      await tester.pump(_grace);
      await tester.pump(_minVisible);
      expect(find.byType(OfflineBlockingOverlay), findsOneWidget);
    });

    for (final phase in [
      GatePhase.initializing,
      GatePhase.checkingPolicy,
      GatePhase.restoringSession,
      GatePhase.loadingWallet,
      GatePhase.signedOut,
      GatePhase.maintenance,
      GatePhase.forceUpdate,
      GatePhase.unreachable,
    ]) {
      testWidgets('never on the gate screens (${phase.name})', (tester) async {
        final h = await _pump(tester, phase: phase);
        h.status(RealtimeStatus.reconnecting);
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(OfflineBlockingOverlay), findsNothing);
      });
    }

    testWidgets('clears when the gate leaves ready (e.g. maintenance)', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _block(tester, h);
      h.phase(GatePhase.maintenance);
      await tester.pump(_minVisible);
      await tester.pump();
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
    });

    testWidgets('never for 4409 (the shell offers Reconnect) or when stopped', (
      tester,
    ) async {
      final h = await _pump(tester);
      h.status(RealtimeStatus.replaced);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(OfflineBlockingOverlay), findsNothing);

      await _block(tester, h);
      h.status(RealtimeStatus.replaced);
      await tester.pump(_minVisible);
      await tester.pump();
      expect(find.byType(OfflineBlockingOverlay), findsNothing);

      await _block(tester, h);
      h.status(RealtimeStatus.idle);
      await tester.pump(_minVisible);
      await tester.pump();
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
    });

    testWidgets('not started while the app is in the background', (
      tester,
    ) async {
      final env = await TestEnv.create();
      final h = await _pump(tester, env: env);
      final bus = h.container.read(appLifecycleProvider);
      bus.emit(AppLifecycleState.paused);
      h.status(RealtimeStatus.offline);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(OfflineBlockingOverlay), findsNothing);

      // Back in the foreground and still down: shown after the grace period.
      bus.emit(AppLifecycleState.resumed);
      h.status(RealtimeStatus.reconnecting);
      await tester.pump(_grace);
      await tester.pump(_minVisible);
      expect(find.byType(OfflineBlockingOverlay), findsOneWidget);
    });

    testWidgets('in a match it explains that the match keeps running', (
      tester,
    ) async {
      final h = await _pump(tester, inMatch: true);
      await _block(tester, h);
      expect(
        find.text(
          'Your match keeps running. Missed turns are played for you '
          'automatically.',
        ),
        findsOneWidget,
      );
    });
  });

  group('while it shows', () {
    testWidgets('taps and drags never reach the screen below', (tester) async {
      final h = await _pump(tester);
      await tester.tap(find.text('Under'));
      expect(h.probe.taps, 1);

      await _block(tester, h);
      await tester.tap(find.text('Under'), warnIfMissed: false);
      await tester.drag(
        find.byType(ListView),
        const Offset(0, -200),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(h.probe.taps, 1);

      await _unblock(tester, h);
      await tester.tap(find.text('Under'));
      expect(h.probe.taps, 2);
    });

    testWidgets('keyboard focus leaves the screen below', (tester) async {
      final h = await _pump(tester);
      await tester.tap(find.byKey(const Key('field')));
      await tester.pump();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      await _block(tester, h);
      expect(field.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      tester.testTextInput.enterText('typed while offline');
      await tester.pump();
      expect(find.text('typed while offline'), findsNothing);
    });

    testWidgets('system back is swallowed; works again once back online', (
      tester,
    ) async {
      final h = await _pump(tester);
      await tester.tap(find.text('Open second'));
      await tester.pumpAndSettle();
      expect(find.text('Second page'), findsOneWidget);

      await _block(tester, h);
      // The app keeps claiming back (Android predictive back would
      // otherwise close it from a tab root).
      expect(h.probe.navigation.last, isTrue);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Second page'), findsOneWidget);

      h.status(RealtimeStatus.connected);
      await tester.pump(_minVisible);
      await tester.pump();
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Second page'), findsNothing);
      expect(find.text('Home page'), findsOneWidget);
    });

    testWidgets('restores what the routes report about back when it clears', (
      tester,
    ) async {
      final h = await _pump(tester);
      expect(h.probe.navigation.last, isFalse); // Home: nothing to pop
      await _block(tester, h);
      expect(h.probe.navigation.last, isTrue);
      h.status(RealtimeStatus.connected);
      await tester.pump(_minVisible);
      await tester.pump();
      await tester.pump();
      expect(h.probe.navigation.last, isFalse);
    });

    testWidgets('covers dialogs and bottom sheets on the root navigator', (
      tester,
    ) async {
      final h = await _pump(tester);
      var dialogTaps = 0;
      final ctx = tester.element(find.text('Under'));
      showDialog<void>(
        context: ctx,
        builder: (_) => AlertDialog(
          content: TextButton(
            onPressed: () => dialogTaps++,
            child: const Text('In dialog'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _block(tester, h);
      await tester.tap(find.text('In dialog'), warnIfMissed: false);
      await tester.pump();
      expect(dialogTaps, 0);
      expect(find.text('In dialog'), findsOneWidget); // not dismissed
    });

    testWidgets('screen readers get one live region and only the overlay; '
        '"Back online" when it clears (Android)', (tester) async {
      // Android: announcements are deprecated (not supported).
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final semantics = tester.ensureSemantics();
      final h = await _pump(tester);
      expect(find.semantics.byLabel('Under'), findsOne);
      await _block(tester, h);
      expect(find.semantics.byLabel('Under'), findsNothing);
      final live = find.semantics.byLabel(RegExp('^$_title'));
      expect(live, findsOne);
      expect(live.evaluate().single, isSemantics(isLiveRegion: true));
      expect(find.semantics.byLabel('Try now'), findsOne);

      // A short-lived live region instead of an announcement.
      tester.takeAnnouncements();
      h.status(RealtimeStatus.connected);
      await tester.pump(_minVisible);
      await tester.pump();
      await tester.pump();
      expect(find.semantics.byLabel('Under'), findsOne);
      final backOnline = find.semantics.byLabel('Back online');
      expect(backOnline, findsOne);
      expect(backOnline.evaluate().single, isSemantics(isLiveRegion: true));
      expect(tester.takeAnnouncements(), isEmpty);
      await tester.pump(const Duration(seconds: 3));
      expect(find.semantics.byLabel('Back online'), findsNothing);
      semantics.dispose();
    });

    testWidgets('"Back online" is announced where announcements are '
        'supported (iOS)', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(supportsAnnounce: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final h = await _pump(tester);
      await _block(tester, h);
      tester.takeAnnouncements();
      h.status(RealtimeStatus.connected);
      await tester.pump(_minVisible);
      await tester.pump();
      await tester.pump();
      expect(tester.takeAnnouncements().map((a) => a.message), ['Back online']);
    });

    testWidgets('reduced motion: a static indicator', (tester) async {
      final h = await _pump(tester);
      await _block(tester, h);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('offline-indicator')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });

    testWidgets('full motion: a spinning indicator', (tester) async {
      final h = await _pump(tester, reduceMotion: false);
      await _block(tester, h);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('offline-indicator')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      h.status(RealtimeStatus.connected);
      await tester.pump(_minVisible);
      await tester.pump();
    });

    for (final (locale, dir) in [
      (const Locale('ar'), TextDirection.rtl),
      (const Locale('ur'), TextDirection.rtl),
      (const Locale('hi'), TextDirection.ltr),
      (const Locale('id'), TextDirection.ltr),
    ]) {
      testWidgets('${locale.languageCode} at 320×640, text ×1.35, in a match: '
          'no overflow', (tester) async {
        final h = await _pump(
          tester,
          locale: locale,
          size: Viewports.small,
          textScale: 1.35,
          inMatch: true,
        );
        await _block(tester, h);
        expect(tester.takeException(), isNull);
        final ctx = tester.element(find.byType(OfflineBlockingOverlay));
        expect(Directionality.of(ctx), dir);
        final l10n = AppLocalizations.of(ctx);
        expect(find.text(l10n.connectionLostTitle), findsOneWidget);
        expect(find.text(l10n.connectionLostMatchHint), findsOneWidget);
      });
    }

    testWidgets('dark theme renders', (tester) async {
      final h = await _pump(tester);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.darkTheme, isNotNull);
      await _block(tester, h);
      expect(tester.takeException(), isNull);
    });
  });

  group('with the real socket', () {
    Future<(_Harness, FakeConnector)> pumpWithSocket(
      WidgetTester tester, {
      List<Object?> script = const [],
    }) async {
      final env = await TestEnv.create();
      final connector = FakeConnector()..script.addAll(script);
      env.wsConnector = connector.call;
      final h = await _pump(tester, env: env, status: RealtimeStatus.idle);
      return (h, connector);
    }

    /// Closes the socket so no heartbeat / backoff timer outlives the test.
    Future<void> end(WidgetTester tester, _Harness h) async {
      h.container.read(realtimeConnectionProvider).stop();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> run(WidgetTester tester, [int rounds = 6]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(settle);
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('"Try now" reconnects immediately', (tester) async {
      // Every attempt fails at the network level: backing off.
      final (h, connector) = await pumpWithSocket(
        tester,
        script: List<Object?>.filled(8, null),
      );
      h.container.read(realtimeConnectionProvider).start();
      await run(tester);
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      expect(find.byType(OfflineBlockingOverlay), findsOneWidget);

      connector.script.clear(); // the network is back
      final before = connector.calls.length;
      await tester.tap(find.text('Try now'));
      await run(tester, 2);
      expect(connector.calls.length, before + 1);
      connector.last.ready();
      await run(tester);
      await tester.pump(OfflineBlockingOverlay.retryCooldown);
      await tester.pump();
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
      await end(tester, h);
    });

    testWidgets(
      'a rejected handshake (400, client bug) does not lock the app',
      (tester) async {
        final (h, _) = await pumpWithSocket(tester, script: [400]);
        h.container.read(realtimeConnectionProvider).start();
        await run(tester);
        expect(
          h.container.read(realtimeStatusProvider),
          RealtimeStatus.offline,
        );
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(OfflineBlockingOverlay), findsNothing);
        await end(tester, h);
      },
    );

    testWidgets('a 503 halt the gate did not confirm is retried while '
        'blocked', (tester) async {
      final (h, connector) = await pumpWithSocket(tester);
      final connection = h.container.read(realtimeConnectionProvider);
      connection.start();
      await run(tester);
      connector.last.ready();
      await run(tester);
      expect(
        h.container.read(realtimeStatusProvider),
        RealtimeStatus.connected,
      );

      connector.script.add(503);
      connector.last.serverClose(1006);
      await run(tester);
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      expect(connection.haltReason, RealtimeHaltReason.policy);
      expect(find.byType(OfflineBlockingOverlay), findsOneWidget);

      final before = connector.calls.length;
      await tester.pump(OfflineBlockController.haltedRetryInterval);
      await run(tester);
      expect(connector.calls.length, before + 1);
      connector.last.ready();
      await run(tester);
      await tester.pump(_minVisible);
      await tester.pump();
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
      await end(tester, h);
    });
  });

  group('in the app', () {
    testWidgets('a match: blocked while the socket is down, then the '
        "server's current state after the resync", (tester) async {
      setViewportSize(tester, Viewports.phone);
      final env = await TestEnv.create(prefs: {PrefKeys.languageChosen: true});
      env.routeHappyPath();
      env.seedSession();
      final connector = FakeConnector();
      env.wsConnector = connector.call;
      final container = env.container();
      addTearDown(container.dispose);
      Future<void> settleApp([int rounds = 8]) async {
        for (var i = 0; i < rounds; i++) {
          await tester.runAsync(settle);
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: LudoArenaApp(),
          ),
        ),
      );
      await settleApp();
      // Launch: connection.ready names the running match → game screen.
      final first = connector.last..ready(activeRoomId: 'r_1');
      await settleApp(2);
      first.serverSend('game.state', {
        'room': ludoRoomJson(turnSeat: 0),
      }, first.sentOfType('game.request_sync').last['id'] as String);
      await settleApp(4);
      expect(find.byType(LudoGameScreen), findsOneWidget);
      expect(find.byType(OfflineBlockingOverlay), findsNothing);

      // The network drops.
      first.serverClose(1006);
      await settleApp(12);
      expect(find.byType(OfflineBlockingOverlay), findsOneWidget);
      expect(
        find.text(
          'Your match keeps running. Missed turns are played for you '
          'automatically.',
        ),
        findsOneWidget,
      );
      expect(find.byType(LudoGameScreen), findsOneWidget);

      // Back: the room controller re-syncs and the overlay clears.
      final second = connector.last;
      expect(second, isNot(same(first)));
      second.ready(activeRoomId: 'r_1');
      await settleApp(2);
      final sync = second.sentOfType('game.request_sync').last;
      expect(sync['p'], {'roomId': 'r_1'});
      second.serverSend('game.state', {
        'room': ludoRoomJson(v: 44, turnSeq: 9, turnSeat: 1),
      }, sync['id'] as String);
      await settleApp(6);
      expect(find.byType(OfflineBlockingOverlay), findsNothing);
      expect(find.byType(LudoGameScreen), findsOneWidget);
      final room = container.read(activeRoomControllerProvider).room!;
      expect(room.v, 44);
      expect(room.turn.seat, 1);
      // Nothing was sent while blocked except the resync.
      expect(
        second.sentJson
            .map((m) => m['t'])
            .where(
              (t) => t != 'ping' && t != ClientMessageTypes.gameRequestSync,
            ),
        isEmpty,
      );

      await tester.pumpWidget(const SizedBox());
      container.read(realtimeConnectionProvider).stop();
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
