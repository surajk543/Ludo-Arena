import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/shared/game_visuals/motion/board_motion.dart';

class _Job extends MotionJob {
  _Job(this.name, this.log, {this.length = 0.2});

  final String name;
  final List<String> log;
  final double length;

  @override
  double get duration => length;

  @override
  void begin(BoardMotionEngine engine) => log.add('$name.begin');

  @override
  void update(BoardMotionEngine engine, double t) {}

  @override
  void finish(BoardMotionEngine engine) => log.add('$name.finish');
}

class _Host extends StatefulWidget {
  const _Host(this.engine);
  final BoardMotionEngine engine;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.engine.attach(this);
  }

  @override
  void dispose() {
    widget.engine.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  group('TrailHistory', () {
    test('keeps the newest samples in order', () {
      final h = TrailHistory();
      for (var i = 0; i < TrailHistory.capacity + 5; i++) {
        h.add(i.toDouble(), 0, i * 0.1);
      }
      expect(h.length, TrailHistory.capacity);
      expect(h.xAt(0), 5);
      expect(h.xAt(h.length - 1), TrailHistory.capacity + 4);
      h.clear();
      expect(h.length, 0);
    });

    test('skips near-duplicate resting samples', () {
      final h = TrailHistory()
        ..add(1, 1, 0)
        ..add(1, 1, 0.01)
        ..add(1, 1, 0.2);
      expect(h.length, 2);
    });
  });

  group('BoardMotionEngine', () {
    test('without a ticker jobs apply instantly', () async {
      final log = <String>[];
      var changes = 0;
      final engine = BoardMotionEngine(
        onFrame: () {},
        onStateChanged: () => changes++,
      );
      await engine.run(_Job('a', log));
      expect(log, ['a.begin', 'a.finish']);
      expect(changes, 1);
      expect(engine.isAnimating, isFalse);
    });

    testWidgets('runs jobs sequentially and snaps on demand', (tester) async {
      final log = <String>[];
      var frames = 0;
      final engine = BoardMotionEngine(
        onFrame: () => frames++,
        onStateChanged: () {},
      );
      await tester.pumpWidget(_Host(engine));
      var aDone = false;
      var bDone = false;
      var cDone = false;
      engine.run(_Job('a', log)).then((_) => aDone = true);
      engine.run(_Job('b', log)).then((_) => bDone = true);
      expect(log, ['a.begin']);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 250));
      expect(aDone, isTrue);
      expect(log, ['a.begin', 'a.finish', 'b.begin']);
      expect(bDone, isFalse);
      engine.run(_Job('c', log, length: 5)).then((_) => cDone = true);
      engine.snapAll();
      await tester.pump();
      expect(bDone && cDone, isTrue);
      expect(log, [
        'a.begin',
        'a.finish',
        'b.begin',
        'b.finish',
        'c.begin',
        'c.finish',
      ]);
      expect(frames, greaterThan(0));
      expect(engine.isActive, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('effects expire and the ticker stops', (tester) async {
      final engine = BoardMotionEngine(onFrame: () {}, onStateChanged: () {});
      await tester.pumpWidget(_Host(engine));
      engine.addEffect(
        BoardEffect(
          kind: BoardEffectKind.captureBurst,
          center: Offset.zero,
          color: const Color(0xFFFF0000),
          start: engine.now,
          duration: 0.3,
        ),
      );
      expect(engine.isActive, isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 16));
      expect(engine.effects, isEmpty);
      expect(engine.isActive, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('motion curves', () {
    expect(MotionCurves.easeInOut(0), 0);
    expect(MotionCurves.easeInOut(1), 1);
    expect(MotionCurves.hop(0.5), 1);
    expect(MotionCurves.hop(0), 0);
    expect(MotionCurves.squash(0), 1);
    expect(MotionCurves.squash(0.5), 0);
    expect(MotionCurves.hash(3, 4), MotionCurves.hash(3, 4));
    expect(MotionCurves.hash(3, 4), inInclusiveRange(0, 1));
  });
}
