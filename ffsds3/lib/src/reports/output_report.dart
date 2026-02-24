/// DualShock 3 Output Report Implementation
///
/// Offset | 00 | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 0A | ... | 2F |
/// -------|----|----|----|----|----|----|----|----|----|----|----|-----|----|
/// Byte   | ID | RD | RP | LD | LP | -- | -- | -- | -- | MSK| B1 | ... | -- |
///
/// [ID] Report ID (0x01)
/// [RD] Right Motor Duration (0x00-0xFF, default 0x0A)
/// [RP] Right Motor Power (0-255, Weak motor)
/// [LD] Left Motor Duration (0x00-0xFF, default 0x0A)
/// [LP] Left Motor Power (0-255, Strong motor)
/// [MSK] LED Flag Mask (Byte 9):
///      Bits 1-4: LED 1-4 States (bit 1 = LED1, bit 2 = LED2, etc.)
///      Other bits: Reserved/Unknown
/// [B1] LED 1 Blink Pattern (5 bytes: Duration, Cycle, Duty, Res, Repeat)
library;

import 'dart:typed_data';
import 'package:usb_gadget/usb_gadget.dart';

/// DualShock 3 Output Report (Parsed from Host)
final class OutputReport with USBGadgetLogger {
  OutputReport({Uint8List? bytes})
    : bytes = bytes ?? Uint8List(48),
      assert(bytes == null || bytes.length == 48, 'Report must be 48 bytes');

  final Uint8List bytes;

  /// Update the internal state with fresh data from the host.
  void update(List<int> newBytes) {
    if (newBytes.length != 48) {
      throw ArgumentError('Output report must be exactly 48 bytes');
    }
    bytes.setAll(0, newBytes);
    log?.info('Output report updated: $this');
  }

  /// Right (Weak) Motor Duration [0-255]
  /// Duration in units of ~10ms. Motor active if duration > 0 AND power > 0.
  int get rumbleRightDuration => bytes[1];

  /// Right (Weak) Motor Power [0-255]
  /// Motor active if duration > 0 AND power > 0.
  int get rumbleRightPower => bytes[2];

  /// Left (Strong) Motor Duration [0-255]
  /// Duration in units of ~10ms. Motor active if duration > 0 AND power > 0.
  int get rumbleLeftDuration => bytes[3];

  /// Left (Strong) Motor Power [0-255]
  /// Motor active if duration > 0 AND power > 0.
  int get rumbleLeftPower => bytes[4];

  /// Whether the right motor is currently active (both duration and power > 0)
  bool get isRightMotorActive =>
      rumbleRightDuration > 0 && rumbleRightPower > 0;

  /// Whether the left motor is currently active (both duration and power > 0)
  bool get isLeftMotorActive => rumbleLeftDuration > 0 && rumbleLeftPower > 0;

  /// LED Mask extracted from Byte 9 (bits 1-4).
  /// Each bit represents one LED: bit 1=LED1, bit 2=LED2, bit 3=LED3, bit 4=LED4
  int get ledMask => (bytes[9] >> 1) & 0x0F;

  List<bool> get ledStates => [
    ledMask.bitFlag(0),
    ledMask.bitFlag(1),
    ledMask.bitFlag(2),
    ledMask.bitFlag(3),
  ];

  @override
  String toString() =>
      'OutputReport('
      'Rumble: L=$rumbleLeftPower R=$rumbleRightPower, '
      'Duration: L=$rumbleLeftDuration R=$rumbleRightDuration, '
      'LEDs: ${ledStates.map((on) => on ? '● ' : '○ ').join()})';
}
