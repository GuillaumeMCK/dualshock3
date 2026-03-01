/// **Client → server**
/// | Opcode     | Value  | Meaning                        |
/// |------------|--------|--------------------------------|
/// | [input]    | `0x01` | 48-byte input report           |
/// | [shutdown] | `0xFF` | Graceful shutdown request      |
///
/// **Server → client**
/// | Opcode   | Value  | Meaning                        |
/// |----------|--------|--------------------------------|
/// | [output] | `any`  | 48-byte output report          |
enum Op {
  /// Dualshock3 input report sent by the client.
  inputReport(0x01),

  /// Graceful shutdown request sent by the client.
  shutdown(0xFF);

  const Op(this.byte);

  /// Raw opcode byte on the wire.
  final int byte;

  static final _byByte = {
    inputReport.byte: inputReport,
    shutdown.byte: shutdown,
  };

  /// Returns the [Op] matching [b], or `null` if unrecognised.
  static Op? fromByte(int b) => _byByte[b];

  static const frameLength = 48;
}
