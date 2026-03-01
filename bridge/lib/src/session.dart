import 'dart:io';
import 'dart:typed_data';

import 'package:using/using.dart';

import 'protocol.dart';

typedef FrameHandler = void Function(Op op, Uint8List payload);

typedef CloseHandler = void Function();

final class Session with Releasable {
  /// A session represents a single client connection to the server. It listens
  /// for incoming frames and passes them to [onFrame], and allows sending output
  /// frames back to the client. When the session is closed, [onClose] is called.
  ///
  /// The session is automatically released when the client disconnects or an error
  /// occurs, but can also be released manually by calling [release].
  Session({
    required RawSocket socket,
    required this.onFrame,
    required this.onClose,
  }) : _socket = socket {
    remoteAddress = '${socket.remoteAddress.address}:${socket.remotePort}';
    socket.listen(
      _onEvent,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: false,
    );
  }

  late final String remoteAddress;

  bool get isOpen => !isReleased;

  final FrameHandler onFrame;

  final CloseHandler onClose;

  final RawSocket _socket;

  bool sendOutput(Uint8List payload) {
    assert(
      payload.length == Op.frameLength,
      'Output payload must be $Op.frameLength bytes',
    );
    if (isReleased) return false;

    _socket.write(
      Uint8List(Op.frameLength)..setRange(0, Op.frameLength, payload),
    );
    return true;
  }

  void _onError(Object error, StackTrace stackTrace) {
    stderr.writeln('Error on session with $remoteAddress: $error');
    stderr.writeln(stackTrace);
    release();
  }

  void _onDone() {
    release();
  }

  void _onEvent(RawSocketEvent event) {
    switch (event) {
      case .readClosed || .closed:
        release();
      case .read:
        final chunk = _socket.read();
        if (chunk == null || chunk.isEmpty || chunk.length > Op.frameLength) {
          return;
        }
        if (chunk[0] == Op.shutdown.byte) {
          return onFrame(Op.shutdown, chunk);
        }
        if (chunk[0] == Op.inputReport.byte && chunk.length == Op.frameLength) {
          onFrame(Op.inputReport, chunk);
        }
      case .write:
    }
  }

  @override
  void release() {
    if (isReleased) return;
    super.release();
    onClose();
    _socket.close();
  }
}
