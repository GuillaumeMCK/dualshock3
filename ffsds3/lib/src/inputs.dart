/// DualShock 3 button definitions with bit positions and analog byte offsets.
///
/// Each button has:
/// - A bit position in the button bitfield (bytes 2-4 of input report)
/// - An analog byte offset for pressure-sensitive buttons (or -1 if not analog)
///
/// ## Button Layout
///
/// **Digital Buttons (bytes 2-4):**
/// - Byte 2 (bits 0-7): SELECT, L3, R3, START, UP, RIGHT, DOWN, LEFT
/// - Byte 3 (bits 8-15): L2, R2, L1, R1, TRIANGLE, CIRCLE, CROSS, SQUARE
/// - Byte 4 (bit 16): PS
///
/// **Analog Pressure (bytes 10-25):**
/// - All buttons except PS have analog pressure values (0-255)
/// - Byte offsets: 10-25 for the 16 analog buttons
///
/// ## Example
///
/// ```dart
/// // Check if button has analog support
/// if (Button.cross.hasAnalog) {
///   print('Cross button pressure byte: ${Button.cross.analogByte}');
/// }
///
/// // Get bit mask for button
/// final mask = Button.triangle.bitMask; // 1 << 12
/// ```
enum Button {
  select,
  l3,
  r3,
  start,
  up,
  right,
  down,
  left,
  l2,
  r2,
  l1,
  r1,
  triangle,
  circle,
  cross,
  square,
  ps;

  const Button();

  static const _analogReservedBytes = 10;

  static const List<Button> analogButtons = [
    l2,
    l1,
    r2,
    r1,
    triangle,
    circle,
    cross,
    square,
    up,
    right,
    down,
    left,
  ];

  /// Bit position in the button bitfield (0-16).
  int get bit => index;

  /// Byte offset for analog pressure value (0-25).
  int get analogByte {
    assert(
      hasAnalog,
      'Button $name does not support analog pressure, but analogByte '
      'tried to access it. Check hasAnalog before accessing analogByte.',
    );
    return bit + _analogReservedBytes;
  }

  /// Byte offset for analog pressure value (0-25), or -1 if not analog.
  // final int analogByte;

  /// Whether the button has analog pressure support.
  bool get hasAnalog => analogButtons.contains(this);

  /// Bit mask for the button (1 << bit).
  int get bitMask => 1 << bit;
}

/// Joystick position with x and y coordinates.
typedef Joystick = ({int x, int y});
