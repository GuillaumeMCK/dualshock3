/// DualShock 3 input report implementation.
///
/// This report is sent from the controller to the host at 100Hz (every 10ms).
/// It contains button states, analog stick positions, analog button pressures,
/// and motion sensor data (accelerometer and gyroscope).
///
/// ## Report Format (49 bytes)
///
/// | Offset | Size | Description                               |
/// |--------|------|-------------------------------------------|
/// | 0      | 1    | Report ID (0x01)                          |
/// | 1      | 1    | Reserved (0x00)                           |
/// | 2-4    | 3    | Button states (bitfield)                  |
/// | 5      | 1    | Reserved (0x00)                           |
/// | 6-9    | 4    | Analog sticks (L.X, L.Y, R.X, R.Y)        |
/// | 10-25  | 16   | Analog button pressures                   |
/// | 26-30  | 5    | Reserved (0x00)                           |
/// | 31     | 1    | Unknown (0x05)                            |
/// | 32-40  | 9    | Reserved (0x00)                           |
/// | 41-46  | 6    | Accelerometer + Gyro (big-endian 10-bit)  |
/// | 47-48  | 2    | Reserved (0x00)                           |
///
/// ## Example
///
/// ```dart
/// final report = InputReport();
///
/// // Set button states
/// report.setButton(Button.cross.bit, true);
///
/// // Set analog sticks (directly)
/// report.setAnalog(Button.l2.analogByte, 200);
///
/// // Use records for grouped stick values
/// report.setSticks(
///   left: (x: 128, y: 128),
///   right: (x: 200, y: 100),
/// );
///
/// // Get report bytes for USB transmission
/// final bytes = report.bytes; // Uint8List(49)
/// ```
library;

import 'dart:typed_data';
import 'package:usb_gadget/usb_gadget.dart';

import '../inputs.dart';

/// DualShock 3 Input Report (Sent to Host)
final class InputReport {
  InputReport() : bytes = Uint8List(49), _buttons = 0 {
    // Initialize to neutral state
    bytes[0] = 1; // Report ID
    bytes[6] = 127; // Left stick X (center)
    bytes[7] = 127; // Left stick Y (center)
    bytes[8] = 127; // Right stick X (center)
    bytes[9] = 127; // Right stick Y (center)
    bytes[31] = 5; // Unknown constant

    // Initialize accelerometer/gyro to neutral (big-endian 10-bit center = 511)
    bytes
      ..setRange(41, 43, 511.toBytes(2))
      ..setRange(43, 45, 511.toBytes(2))
      ..setRange(45, 47, 511.toBytes(2));
  }

  final Uint8List bytes;
  int _buttons;

  /// Sets a button's pressed state and automatically updates its analog pressure.
  ///
  /// This method updates both the button bitfield (bytes 2-4) and the analog
  /// pressure value (bytes 10-25) for buttons that support analog input.
  ///
  /// Parameters:
  /// - [bit]: The button bit position (0-23). Use [Button.bit] values.
  /// - [pressed]: Whether the button is pressed.
  /// - [analogValue]: Optional analog pressure (0-255). If not provided and
  ///   [pressed] is true, defaults to 255 (maximum pressure). If the button
  ///   doesn't support analog input, this parameter is ignored.
  ///
  /// Example:
  /// ```dart
  /// // Simple press (auto-sets analog to 255)
  /// report.setButton(Button.cross.bit, true);
  ///
  /// // Custom analog pressure
  /// report.setButton(Button.r2.bit, true, analogValue: 128);
  ///
  /// // Release button (clears both bitfield and analog)
  /// report.setButton(Button.cross.bit, false);
  /// ```
  void setButton(int bit, bool pressed, {int? analogValue}) {
    assert(bit >= 0 && bit < 24, 'Button bit must be in range 0-23');
    assert(
      analogValue == null || (analogValue >= 0 && analogValue <= 255),
      'Analog value must be in range 0-255',
    );

    // Update button bitfield
    if (pressed) {
      _buttons |= 1 << bit;
    } else {
      _buttons &= ~(1 << bit);
    }
    bytes[2] = _buttons.byte(0);
    bytes[3] = _buttons.byte(1);
    bytes[4] = _buttons.byte(2);

    // Update analog pressure for buttons that support it
    final button = Button.values.firstWhere((b) => b.bit == bit);
    if (button.hasAnalog) {
      final pressure = pressed ? (analogValue ?? 255) : 0;
      bytes[button.analogByte] = pressure;
    }
  }

  /// Gets the current pressed state of a button from the bitfield.
  ///
  /// Parameters:
  /// - [bit]: The button bit position (0-23). Use [Button.bit] values.
  ///
  /// Returns: `true` if the button is currently pressed, `false` otherwise.
  ///
  /// Note: This only returns the digital (on/off) state. For analog pressure
  /// values, use [getAnalog] with [Button.analogByte].
  bool pressed(int bit) {
    assert(bit >= 0 && bit < 24, 'Button bit must be in range 0-23');
    return (_buttons >> bit) & 1 == 1;
  }

  /// Sets an analog value directly at the specified byte offset.
  ///
  /// This method provides low-level control over analog values in the report.
  /// For most use cases, prefer [setButton] which handles both digital and
  /// analog states automatically.
  ///
  /// Parameters:
  /// - [offset]: The byte offset in the report (typically 6-25).
  /// - [targetValue]: The analog value (0-255). Values outside this range
  ///   will be clamped.
  ///
  /// Common offsets:
  /// - 6-9: Analog sticks (use [setSticks] instead)
  /// - 10-25: Button pressures (use [setButton] instead)
  ///
  /// Example:
  /// ```dart
  /// // Manually set L2 trigger to half pressure
  /// report.setAnalog(Button.l2.analogByte, 128);
  /// ```
  void setAnalog(int offset, int targetValue) {
    assert(offset >= 0 && offset < 49, 'Offset must be in range 0-48');
    final target = targetValue.clamp(0, 255);
    bytes[offset] = target;
  }

  /// Gets the current analog value at the specified byte offset.
  ///
  /// Parameters:
  /// - [offset]: The byte offset in the report (typically 6-25).
  ///
  /// Returns: The analog value (0-255) at the specified offset.
  ///
  /// Example:
  /// ```dart
  /// // Read R2 trigger pressure
  /// final pressure = report.getAnalog(Button.r2.analogByte);
  /// print('R2 pressure: $pressure');
  /// ```
  int getAnalog(int offset) {
    assert(offset >= 0 && offset < 49, 'Offset must be in range 0-48');
    return bytes[offset];
  }

  /// Sets both analog stick positions simultaneously.
  ///
  /// Parameters:
  /// - [left]: Left stick position (x: 0-255, y: 0-255). Center is (127, 127).
  /// - [right]: Right stick position (x: 0-255, y: 0-255). Center is (127, 127).
  ///
  /// Example:
  /// ```dart
  /// // Center both sticks
  /// report.setSticks(
  ///   left: (x: 127, y: 127),
  ///   right: (x: 127, y: 127),
  /// );
  ///
  /// // Full right on left stick, full up on right stick
  /// report.setSticks(
  ///   left: (x: 255, y: 127),
  ///   right: (x: 127, y: 0),
  /// );
  /// ```
  void setSticks({required Joystick left, required Joystick right}) {
    assert(
      left.x >= 0 && left.x <= 255 && left.y >= 0 && left.y <= 255,
      'Left stick values must be in range 0-255',
    );
    assert(
      right.x >= 0 && right.x <= 255 && right.y >= 0 && right.y <= 255,
      'Right stick values must be in range 0-255',
    );

    bytes[6] = left.x;
    bytes[7] = left.y;
    bytes[8] = right.x;
    bytes[9] = right.y;
  }

  /// Overrides the entire input report with a new byte array.
  // set bytes(Uint8List bytes) {
  //   assert(
  //     bytes.length == 49 || bytes.length == 48,
  //     'Input report must be exactly 49 bytes (including Report ID) or 48 bytes (excluding Report ID)',
  //   );
  //   if (bytes.length == 48) {
  //     this.bytes.setAll(0, [1, ...bytes]);
  //   } else {
  //     this.bytes.setAll(0, bytes);
  //   }
  // }

  /// Gets the current left analog stick position.
  ///
  /// Returns: A [Joystick] record with x and y values (0-255).
  /// Center position is (127, 127).
  Joystick get leftStick => (x: bytes[6], y: bytes[7]);

  /// Gets the current right analog stick position.
  ///
  /// Returns: A [Joystick] record with x and y values (0-255).
  /// Center position is (127, 127).
  Joystick get rightStick => (x: bytes[8], y: bytes[9]);

  @override
  String toString() {
    final buffer = StringBuffer()
      ..writeln('InputReport:')
      ..writeln('  Buttons:');
    for (final button in Button.values) {
      // show only buttons that are pressed or have analog input for clarity
      if (!pressed(button.bit) && !button.hasAnalog) {
        continue;
      }

      buffer
        ..write('    ${button.name}: ${pressed(button.bit)}')
        ..writeln(
          button.hasAnalog ? ' (Analog: ${getAnalog(button.analogByte)})' : '',
        );
    }
    buffer
      ..writeln('  Left Stick: (x: ${leftStick.x}, y: ${leftStick.y})')
      ..writeln('  Right Stick: (x: ${rightStick.x}, y: ${rightStick.y})');
    return buffer.toString();
  }
}
