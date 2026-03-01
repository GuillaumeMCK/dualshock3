import 'dart:async';
import 'dart:io';

import 'package:embed_annotation/embed_annotation.dart';
import 'package:bridge/bridge.dart';

part 'bridge.g.dart';

@EmbedBinary('/assets/libaio.so')
final List<int> libaioBytes = _$libaioBytes;

const kLibaioPath = '$kBridgeDir/libaio.so';

void main() => runZonedGuarded(
  () async {
    final libaio = File(kLibaioPath);
    if (!libaio.existsSync()) libaio.writeAsBytesSync(libaioBytes);

    await Ds3Bridge.start().then((server) async {
      stdout.writeln('listening on ${InternetAddress.anyIPv4}:${server.port}');
      await server.released;
    });
  },
  (err, st) {
    stderr.writeln('--- FATAL ERROR ---');
    stderr.writeln('$err\n$st');
    exitCode = 1;
  },
);
