import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ffsds3/ffsds3.dart';

Future<void> main() async {
  final (gadget, controller) = createDualshock3();

  StreamSubscription<void>? stdinSubscription;
  try {
    await gadget.bind();
    await gadget.awaitState(.configured, timeout: const .new(seconds: 30));
    stdout.writeln(
      'Commands: ps, cross, square, circle, triangle, start, quit',
    );
    stdinSubscription = _loop(controller);
    await ProcessSignal.sigint.watch().first;
  } catch (e, st) {
    stderr.writeln('ERROR: $e\n$st');
    exit(1);
  } finally {
    await stdinSubscription?.cancel();
    await gadget.unbind();
  }
}

StreamSubscription<void> _loop(Dualshock3 c) {
  stdin.lineMode = true;

  const btns = {
    'ps': Button.ps,
    'x': Button.cross,
    'cross': Button.cross,
    'o': Button.circle,
    'circle': Button.circle,
    'c': Button.circle,
    'square': Button.square,
    's': Button.square,
    'triangle': Button.triangle,
    't': Button.triangle,
    'start': Button.start,
    'select': Button.select,
    'l1': Button.l1,
    'l2': Button.l2,
    'l3': Button.l3,
    'r1': Button.r1,
    'r2': Button.r2,
    'r3': Button.r3,
    'up': Button.up,
    'u': Button.up,
    'down': Button.down,
    'd': Button.down,
    'left': Button.left,
    'l': Button.left,
    'right': Button.right,
    'r': Button.right,
  };

  int randomByte() => (Random().nextDouble() * 255).toInt();

  return stdin.transform(const SystemEncoding().decoder).listen((line) {
    final cmd = line.trim().toLowerCase();
    switch (cmd) {
      case 'stk':
        c.input.setSticks(
          left: (x: randomByte(), y: randomByte()),
          right: (x: randomByte(), y: randomByte()),
        );
      case final command when btns.containsKey(command):
        final btn = btns[command]!;
        final pressed = !c.input.pressed(btn.bit);
        c.input.setButton(btn.bit, pressed);
    }
    stdout.writeln(c.input);
  });
}
