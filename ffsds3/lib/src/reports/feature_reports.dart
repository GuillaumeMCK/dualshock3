/// DualShock 3 feature report handler.
///
/// Feature reports are used for configuration, calibration access,
/// Bluetooth pairing, and controller mode control.
///
/// ## Implemented Feature Reports
///
/// - **01** – Controller information (type, firmware, stick calibration preview)
///   Returns basic controller identification and a preview of calibration data.
///
/// - **F1** – Flash memory access
///   Used to read small blocks of internal controller flash memory,
///   containing factory calibration values and firmware information.
///
/// - **F2** – Device information
///   Returns controller MAC address and serial number.
///
/// - **F4** – Controller control / mode commands
///   Host-to-controller control report. Commands are prefixed with `0x42`
///   and used for enabling input streaming, sensors, and controller reset.
///
/// - **F5** – Bluetooth pairing information
///   Stores the host MAC address for wireless reconnection.
///
/// - **EF** – Extended sensor configuration
///   Vendor-specific motion sensor configuration block with factory calibration.
///
/// - **F7** – Additional sensor configuration
///   Returns controller-specific calibration values from flash.
///
/// - **F8** – Sensor status information
///
/// ## Protocol Notes
///
/// Normal gameplay input uses HID input report **0x01**, which is separate
/// from all feature reports handled here.
///
/// All feature reports are 64 bytes long and use standard HID GET_FEATURE
/// and SET_FEATURE requests.
///
/// ## Flash Memory Layout
///
/// Flash memory is organized into two 256-byte banks:
///
/// **Bank 0 (0x00-0xFF):**
/// - 0x00-0x07: Controller type and firmware header
/// - 0x08-0x1F: Configuration data
/// - 0x20-0x27: Analog stick calibration values
/// - 0x28-0x5F: Additional calibration and settings
/// - 0x60-0x6B: Firmware version and stick center points
/// - 0x70-0x9F: Deadzone/gain configuration
/// - 0xB0-0xFF: Intensity/rumble lookup table (part 1)
///
/// **Bank 1 (0x00-0xFF):**
/// - 0x00-0x6F: Intensity/rumble lookup table (part 2)
/// - 0x70-0x7F: Duplicate controller header
/// - 0x80-0x8F: Additional configuration
/// - 0x90-0xAF: Motion sensor calibration (accel/gyro)
/// - 0xB0-0xEF: Reserved/configuration
/// - 0xF0-0xFF: Footer data
///
library;

import 'dart:typed_data';
import 'package:usb_gadget/usb_gadget.dart';

/// Command types for Feature Report **F1** (Flash Memory Access).
enum FlashCommand {
  /// Sets the flash bank and address pointer (0x0B).
  ///
  /// This command prepares the controller for a subsequent GET_FEATURE
  /// request by selecting which 16-byte block will be returned.
  setAddress,

  /// Writes a 16-byte block to the selected flash memory (0x0A).
  ///
  /// Updates the internal buffer at the current pointer with
  /// the payload provided in the SET_FEATURE request.
  write;

  factory FlashCommand.fromByte(int byte) => switch (byte) {
    0x0B => .setAddress,
    0x0A => .write,
    _ => throw ArgumentError('Unrecognized flash command: ${byte.toHex()}'),
  };
}

/// Sub-commands used with Feature Report **F4** (prefix 0x42).
///
/// All F4 commands must be prefixed with (0x42).
///
/// ## Usage Example
/// ```dart
/// final cmd = Uint8List.fromList([F4Command.prefix, 0x02]);
/// handler.setF4(cmd); // Enables input streaming
/// ```
enum F4Command {
  /// Disables periodic input report streaming (0x01).
  ///
  /// After this command, the controller stops sending automatic input reports.
  disableInputStreaming,

  /// Enables periodic input report streaming (0x02).
  ///
  /// After this command, the controller sends input reports approximately
  /// every 10ms when the PS button is pressed.
  enableInputStreaming,

  /// Enables motion sensor data in input reports (0x03).
  ///
  /// After this command, the controller includes accelerometer and gyroscope
  /// data in input reports when the PS button is pressed. This is required for
  /// motion controls to work in games that support them.
  enableOutputMotionSensors,

  /// Powers on the controller (0x0C).
  ///
  /// PS3 is booting and tells the controller to power on by sending
  /// this command. The controller should respond by powering on and entering
  /// active mode.
  startupController,

  /// Powers off the controller (0x0B).
  ///
  /// PS3 is shutting down and tells the controller to power off by sending
  /// this command. The controller should power off.
  shutdownController,

  /// Restarts the controller to factory state (0x04).
  ///
  /// Resets all runtime state including streaming mode and sensor
  /// configuration, while preserving persistent data like MAC addresses
  /// and calibration values.
  restartController;

  /// Parses a command from its raw byte value.
  ///
  /// Throws [ArgumentError] if [byte] is not a recognized command.
  factory F4Command.fromByte(int byte) => switch (byte) {
    0x01 => .disableInputStreaming,
    0x02 => .enableInputStreaming,
    0x03 => .enableOutputMotionSensors,
    0x04 => .restartController,
    0x0B => .shutdownController,
    0x0C => .startupController,
    _ => throw ArgumentError('Unrecognized F4 command: ${byte.toHex()}'),
  };
}

/// Maintains controller feature-report state and constructs
/// responses to HID GET_FEATURE / SET_FEATURE requests.
///
/// Instances of this class represent the persistent configuration
/// state of a single virtual DualShock 3 controller, including
/// flash memory contents, calibration data, and runtime state.
///
/// ## Example Usage
/// ```dart
/// final handler = FeatureReport(
///   deviceMac: Uint8List.fromList([0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E]),
///   pairedMac: Uint8List.fromList([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
///   serialNumber: 0x12345678,
///   firmware: 0x0C08,
/// );
///
/// // Handle GET_FEATURE for report 0xF2
/// final deviceInfo = handler.getF2();
///
/// // Handle SET_FEATURE for report 0xF4
/// handler.setF4(Uint8List.fromList([0x42, 0x02])); // Enable streaming
///
/// // Check current state
/// if (handler.inputStreamingEnabled) {
///   print('Controller is streaming input reports');
/// }
/// ```
final class FeatureReport with USBGadgetLogger {
  /// Creates a new feature report handler with the specified configuration.
  ///
  /// The constructor initializes both flash memory banks with factory-default
  /// calibration data, lookup tables, and configuration values that match
  /// real DualShock 3 hardware behavior.
  ///
  /// Parameters:
  /// - [deviceMac]: Controller's hardware MAC address (6 bytes)
  /// - [pairedMac]: Host MAC address for Bluetooth pairing (6 bytes)
  /// - [serialNumber]: Unique 32-bit device serial number
  /// - [firmware]: Firmware version (default: 0x0C01 for v12.1)
  /// - [controllerType]: Controller type identifier (default: 0x04)
  /// - [pcbRevision]: PCB revision identifier (default: 0x8A)
  ///
  /// Throws [ArgumentError] if MAC addresses are not exactly 6 bytes.
  FeatureReport({
    required List<int> deviceMac,
    required List<int> pairedMac,
    required this.serialNumber,
    this.firmware = 0x0C08,
    this.controllerType = 0x04,
    this.pcbRevision = 0x8A,
  }) : assert(deviceMac.length == 6),
       assert(pairedMac.length == 6),
       assert(serialNumber >= 0 && serialNumber <= 0xFFFFFFFF),
       assert(firmware >= 0 && firmware <= 0xFFFF),
       assert(controllerType >= 0 && controllerType <= 0xFF),
       deviceMac = Uint8List.fromList(deviceMac),
       pairedMac = Uint8List.fromList(pairedMac),
       state = Uint8List(4),
       flashBankA = Uint8List(256)
         // Bank 0 header and configuration
         // 0x00-0x03: Controller identification
         // [0x00] 0x01 constant, [0x01] Controller type (0x03=Sixaxis, 0x04=DS3),
         // [0x02] 0x00 reserved, [0x03] Firmware low byte
         ..setAll(0x00, [0x01, controllerType, 0x00, firmware.byte(0)])
         // 0x08-0x1F: Configuration block - returned in Report 0x01 and used in EF report
         ..setAll(0x08, const [
           0xEE, 0x02, 0x00, 0x08, 0xEF, 0x04, 0x00, 0x08, //
           0x00, 0x00, 0x01, 0x64, 0x19, 0x01, 0x00, 0x64, //
           0x00, 0x01, 0x90, 0x00, 0x19, 0xFE, 0x00, 0x00, //
         ])
         // 0x20-0x2F: 4-pin analog stick center calibration (16 bytes total)
         // First 8 bytes: LX, LY, RX, RY center values (16-bit little-endian each)
         // Remaining 8 bytes: Suffix/metadata
         // Note: All zeros at 0x20-0x24 indicates 3-pin stick type
         ..setAll(0x20, const [
           0x01, 0xED, 0x01, 0xF7, 0x01, 0xDE, 0x01, 0xF8, // 0x20-0x27
           0x00, 0x01, 0x01, 0x60, 0x80, 0x20, 0x15, 0x01, // 0x28-0x2F
         ])
         // 0x30-0x5F: Extended calibration data
         // 0x46-0x4D includes 3-pin calibration start
         // 0x4E-0x55 continues 3-pin calibration
         ..setAll(0x30, const [
           0xC7, 0x78, 0x7D, 0x81, 0x7C, 0x00, 0x1C, 0x7D, //
           0x83, 0x84, 0x85, 0x8B, 0x83, 0x10, 0xB0, 0x03, //
           0xFF, 0x00, 0x00, 0xFF, 0x44, 0x44, 0x00, 0x6E, //
           0x03, 0x92, 0x00, 0x6A, 0x03, 0x96, 0x00, 0x65, //
           0x03, 0x9B, 0x00, 0x5A, 0x03, 0xA6, 0x00, 0xFF, //
           0x77, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, //
         ])
         // 0x60: Firmware high byte (forms version with byte 0x03)
         // 0x61-0x6B: Stick center and calibration values - returned in Report 0x01
         ..setAll(0x60, [
           firmware.byte(1), //
           0x01, 0x02, 0x18, 0x18, 0x18, 0x18, 0x09, 0x0A, //
           0x10, 0x11, 0x12, 0x13, 0x00, 0x00, 0x00, //
         ])
         // 0x70-0x9F: Deadzone/gain configuration - used in Report 0x01
         ..setAll(0x70, const [
           0x00, 0x04, 0x00, 0x02, 0x02, 0x02, 0x02, 0x00, //
           0x00, 0x00, 0x04, 0x04, 0x04, 0x04, 0x00, 0x00, //
           0x04, 0x00, 0x01, 0x02, 0x07, 0x00, 0x17, 0x00, //
           0x00, 0x00, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, //
           0x03, 0x00, 0x00, 0x02, 0x00, 0x00, 0x02, 0x62, //
           0x01, 0x02, 0x01, 0x5E, 0x00, 0x32, 0x00, 0x00, //
         ])
         // 0xA0-0xAF: Configuration data
         ..setAll(0xA0, const [
           0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
           0x00, 0x00, 0x00, 0x00, 0x32, 0x20, 0x20, 0x02, //
         ])
         // 0xB0-0xFF: Rumble motor intensity lookup table - Part 1 (80 bytes)
         // Maps input intensity values to motor PWM levels
         ..setAll(0xB0, const [
           0x6C, 0x6C, 0x6C, 0x6C, 0x6C, 0x6C, 0x6C, 0x6C, //
           0x6C, 0x6C, 0x6C, 0x6C, 0x6D, 0x6D, 0x6E, 0x6E, //
           0x6F, 0x70, 0x71, 0x73, 0x75, 0x77, 0x79, 0x7B, //
           0x7D, 0x7F, 0x81, 0x83, 0x85, 0x87, 0x89, 0x8B, //
           0x8D, 0x8E, 0x90, 0x92, 0x93, 0x95, 0x97, 0x99, //
           0x9A, 0x9C, 0x9E, 0x9F, 0xA1, 0xA2, 0xA4, 0xA5, //
           0xA7, 0xA8, 0xAA, 0xAB, 0xAD, 0xAE, 0xB0, 0xB1, //
           0xB3, 0xB4, 0xB6, 0xB7, 0xB9, 0xBB, 0xBC, 0xBE, //
           0xBF, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC8, //
           0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCF, 0xD0, 0xD1, //
         ]),

       flashBankB = Uint8List(256)
         // 0x00-0x6F: Rumble motor intensity lookup table - Part 2 (112 bytes)
         // Continuation from Bank A 0xB0-0xFF
         ..setAll(0x00, const [
           0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, //
           0xDA, 0xDB, 0xDC, 0xDD, 0xDF, 0xE1, 0xE2, 0xE3, //
           0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, //
           0xEC, 0xED, 0xEE, 0xEF, 0xF0, 0xF1, 0xF2, 0xF3, //
           0xF4, 0xF4, 0xF5, 0xF5, 0xF6, 0xF6, 0xF7, 0xF7, //
           0xF7, 0xF8, 0xF8, 0xF8, 0xF9, 0xF9, 0xF9, 0xFA, //
           0xFA, 0xFA, 0xFA, 0xFB, 0xFB, 0xFB, 0xFB, 0xFB, //
           0xFC, 0xFC, 0xFC, 0xFC, 0xFC, 0xFD, 0xFD, 0xFD, //
           0xFD, 0xFD, 0xFD, 0xFD, 0xFD, 0xFD, 0xFE, 0xFE, //
           0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, //
           0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFF, 0xFF, //
           0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, //
           0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, //
           0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, //
         ])
         // 0x70-0x7F: Duplicate configuration data
         ..setAll(0x70, [
           0x01, 0xC7, 0x78, 0x7D, 0x81, 0x7C, 0x00, 0x1C, //
           0x7D, 0x83, 0x84, 0x85, 0x8B, 0x83, 0x10, 0xB0, //
         ])
         // 0x80-0x8F: Configuration block
         ..setAll(0x80, const [
           0x03, 0xFF, 0x00, 0x00, 0xFF, 0x44, 0x44, 0x02, //
           0x6A, 0x02, 0x6E, 0x00, 0x00, 0x00, 0x00, 0x00, //
         ])
         // 0x90-0xAF: Motion sensor calibration data (32 bytes)
         // Used by Report 0xEF - accessed via state[2] offset
         //  acc_x_bias/gain, acc_y_bias/gain, acc_z_bias/gain, gyro_z_offset
         // Format: 16-bit little-endian signed values
         ..setAll(0x90, const [
           0x00, 0x6E, 0x03, 0x92, 0x00, 0x6A, 0x03, 0x96, //
           0x00, 0x65, 0x03, 0x9B, 0x00, 0x5A, 0x03, 0xA6, //
           0x01, 0xFE, 0x01, 0x8B, 0x02, 0x00, 0x01, 0x8F, //
           0x02, 0x00, 0x01, 0x8D, 0x01, 0xF4, 0x00, 0x7D, //
         ])
         // 0xB0-0xBF: Configuration block
         ..setAll(0xB0, const [
           0x02, 0x6A, 0x02, 0x6E, 0x00, 0x00, 0x00, 0x00, //
           0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
         ])
         // 0xC0-0xCF: Configuration block
         ..setAll(0xC0, const [
           0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, //
           0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
         ])
         // 0xD0-0xEF: Reserved (zero-filled by Uint8List constructor)
         // ...
         // 0xF0-0xFF: Footer block
         ..setAll(0xF0, const [
           0x20, 0x07, 0x09, 0x03, 0x00, 0x00, 0x22, 0x2F, //
           0x00, 0x01, 0x00, 0x00, 0x03, 0xBC, 0xB1, 0x09, //
         ]);

  /// MAC address of the controller itself.
  ///
  /// This is the hardware address burned into the controller during
  /// manufacturing. Typically starts with Sony's OUI (e.g., 00:1A:2B).
  /// Used by the host to identify this specific controller.
  final Uint8List deviceMac;

  /// MAC address of the host to which the controller is paired.
  ///
  /// For Bluetooth operation, the controller stores the host's MAC
  /// address to enable automatic reconnection. Can be updated via
  /// the F5 pairing report.
  final Uint8List pairedMac;

  /// Unique device serial number.
  ///
  /// 32-bit unsigned integer used to identify this specific controller
  /// instance. Returned in F2 and F5 reports.
  final int serialNumber;

  /// Firmware version identifier.
  ///
  /// 16-bit value representing the controller's firmware version.
  /// Stored in flash bank 0 at offset 0x60-0x61. Common values include
  /// 0x0C01 (version 12.1).
  final int firmware;

  /// Controller type identifier.
  ///
  /// Stored in flash bank 0 at offset 0x01. Common value is 0x04 for
  /// standard DualShock 3 controllers.
  final int controllerType;

  /// PCB revision identifier.
  ///
  /// Identifies the hardware revision of the controller's circuit board.
  /// Returned in F2 and F5 reports. Common value is 0x8A.
  final int pcbRevision;

  /// Emulated flash memory bank 0 (256 bytes).
  ///
  /// Contains controller header, configuration data, analog stick calibration,
  /// firmware version, deadzone settings, and the first half of the rumble
  /// intensity lookup table.
  ///
  /// Key regions:
  /// - 0x00-0x07: Controller type and header
  /// - 0x20-0x2F: Analog stick calibration
  /// - 0x60-0x6F: Firmware version and center points
  /// - 0xB0-0xFF: Rumble lookup table (part 1)
  late final Uint8List flashBankA;

  /// Emulated flash memory bank 1 (256 bytes).
  ///
  /// Contains the second half of the rumble intensity lookup table,
  /// duplicate configuration data, and motion sensor calibration values.
  ///
  /// Key regions:
  /// - 0x00-0x6F: Rumble lookup table (part 2)
  /// - 0x90-0xAF: Motion sensor calibration (accelerometer/gyroscope)
  final Uint8List flashBankB;

  /// Internal configuration bytes used by EF and F8 reports.
  ///
  /// Format: [reserved, streaming_mode, sensor_enable, sensitivity_mode]
  /// - Byte 0: Reserved (typically 0x00)
  /// - Byte 1: Input streaming mode (0x01 = enabled, 0x03 = outputs enabled)
  /// - Byte 2: flashBankB offset 0x90 bit 0 (0x01 = sensors enabled)
  final Uint8List state;

  /// Currently selected flash bank for F1 read operations (0 or 1).
  ///
  /// Set by F1 SET_FEATURE requests and used by subsequent F1 GET_FEATURE
  /// operations to determine which flash bank to read from.
  int flashBank = 0;

  /// Current flash address pointer for F1 operations (0-255).
  ///
  /// Set by F1 SET_FEATURE requests. Actual reads are aligned to 16-byte
  /// boundaries (flashAddr & 0xF0) to match hardware behavior.
  int flashAddr = 0;

  /// Whether normal input reports are currently enabled.
  ///
  /// Set to `true` by F4 command 0x02, `false` by command 0x01.
  /// When enabled, the controller sends input report 0x01 approximately
  /// every 10ms after the PS button is pressed.
  ///
  /// Note: The implementation checks `state[1] == 0x01` for enabled state.
  bool get inputStreamingEnabled => state[1] == 0x01;

  /// Flash read block size in bytes.
  ///
  /// F1 GET_FEATURE reads return 16 bytes of flash data per request,
  /// aligned to 16-byte boundaries.
  static const int _flashReadBlockSize = 0x10;

  /// Constructs an **F2 – Device Information** feature report.
  ///
  /// This report is typically requested during initial device enumeration
  /// to identify the controller and its hardware characteristics.
  Uint8List getF2() {
    final response = Uint8List(64)
      ..[0] = 0xF2
      ..[1] = 0xFF
      ..[2] = 0xFF
      ..[3] = 0x00
      ..setAll(4, deviceMac.reversed)
      ..[10] = 0x00
      ..[11] = 0x03
      ..setAll(12, serialNumber.toBytes(4, .little))
      ..[16] = pcbRevision
      ..setAll(17, flashBankA.sublist(0x6C, 0x8B));
    log?.info('F2 device information report ${response.xxd()}');
    return response;
  }

  /// Constructs an **F5 – Pairing Information** feature report.
  ///
  /// Returns a 64-byte buffer containing:
  /// - Bytes 0-3: Header (0x01, 0x00, 0x00, 0x00)
  /// - Bytes 4-9: Paired host bluetooth MAC address (6 bytes)
  /// - Bytes 10-12: Reserved (0x00, 0x03, 0x50)
  /// - Bytes 13-16: Serial number (32-bit little-endian)
  /// - Bytes 17-25: Standard suffix
  ///
  /// This report is used to query which Bluetooth host the controller
  /// is currently paired with. Essential for wireless reconnection.
  Uint8List getF5() {
    final r = Uint8List(64)
      ..[0] = 0x01
      ..[1] = 0x00
      ..setAll(2, pairedMac)
      ..setAll(8, deviceMac.sublist(0, 2).reversed)
      ..[10] = 0x00
      ..[11] = 0x03
      ..setAll(0xC, serialNumber.toBytes(4, .little))
      ..[16] = pcbRevision
      ..setAll(17, flashBankA.sublist(0x6C, 0x8B));
    log?.info('F5 pairing information report ${r.xxd()}');
    return r;
  }

  /// Processes an **F5 – Pairing** SET_FEATURE request.
  ///
  /// Updates the paired host MAC address from the provided data.
  /// Expected format: `[0x01, reserved, MAC[6 bytes], ...]`
  ///
  /// The MAC address at bytes 2-7 represents the Bluetooth host that
  /// the controller should connect to automatically.
  ///
  /// Throws [RangeError] if data is too short to contain a MAC address.
  void setF5(Uint8List data) {
    pairedMac.setRange(0, 6, data.sublist(2, 8));
    log?.success(
      'F5 Paired host MAC address to: '
      '${pairedMac.map((b) => b.toHex(prefix: false, padding: 2)).join(':')}'
      '${data.xxd()}',
    );
  }

  /// Constructs an **EF – Extended Sensor Configuration** report.
  ///
  /// Returns a 64-byte buffer containing:
  /// - Bytes 0-1: Header (0x00, 0xEF)
  /// - Bytes 2-4: Configuration marker (0x04, 0x00, 0x08)
  /// - Bytes 5-8: Current state configuration
  /// - Byte 18: Calibration status (0x02 when sensors enabled)
  /// - Bytes 19-34: Motion sensor calibration data (if sensors enabled)
  /// - Byte 48: Fixed footer (0x05)
  ///
  /// The calibration block (bytes 19-34) contains 16-bit signed values
  /// for accelerometer and gyroscope offset/gain calibration, loaded
  /// from flash bank 1 offset 0x90-0x9F.
  ///
  /// This report is essential for proper motion sensor operation and
  /// must return accurate calibration values for each controller unit.
  Uint8List getEF() {
    final address = state[2];
    final r = Uint8List(64)
      ..[1] = 0xEF
      ..setAll(2, flashBankA.sublist(1, 5))
      ..setAll(5, state)
      ..setAll(0x11, flashBankB.sublist(address, address + 0x10))
      ..[0x30] = 0x5;
    log?.debug(
      'EF report with state: ${state.xxd()} and calibration: ${r.sublist(0x11, 0x11 + 0x10).xxd()}',
    );
    return r;
  }

  void setEF(Uint8List data) {
    state.setRange(0, 4, data.sublist(4, 8));
    log?.info('EF report updated from data: ${data.xxd()}');
  }

  /// Returns an **F7 – Sensor Configuration** feature report.
  ///
  /// Returns a 64-byte buffer containing additional sensor configuration
  /// data loaded from flash bank 1 (0xA0-0xAF) with a fixed footer at
  /// byte 48.
  ///
  /// The exact purpose of these values is not fully documented, but they
  /// appear to contain controller-specific calibration or configuration
  /// parameters that vary between hardware units.
  Uint8List getF7() {
    final response = Uint8List(64)
      ..[0x7] = 0xFF
      ..setAll(0x11, flashBankA.sublist(0x8C, 0x8C + 20))
      ..[0x30] = 0x5;
    log?.info('F7 sensor configuration report: ${response.xxd()}');
    return response;
  }

  /// Returns an **F8 – Sensor Status** feature report.
  ///
  /// Returns a 64-byte buffer containing:
  /// - Bytes 0-5: Header (0x00, 0x01, 0x00, 0x00, 0x08, 0x03)
  /// - Bytes 6-8: Current configuration (state[1-3])
  /// - Byte 18: Status flag (0x02)
  /// - Byte 48: Fixed footer (0x05)
  ///
  /// This report provides current runtime status of sensor configuration
  /// and is structurally similar to the EF report but with different
  /// header semantics.
  Uint8List getF8() {
    final response = Uint8List(64)
      ..[0] = 0x00
      ..[1] = 0x01
      ..[2] = 0x00
      ..[3] = 0x00
      ..[4] = flashBankA[3]
      ..setAll(5, state)
      ..setAll(0x11, flashBankB.sublist(state[2], state[2] + 0x10))
      ..[0x30] = 0x5;
    log?.info('F8 sensor status report ${response.xxd()}');
    return response;
  }

  /// Handles an **F1 – Flash Memory Access** SET_FEATURE request.
  ///
  /// Sets the flash bank and address pointer for subsequent F1 read operations.
  ///
  /// Expected format: `[?, ?, ?, ?, bank, address]`
  /// - Byte 4: Bank number (bit 0: 0 or 1, other bits ignored)
  /// - Byte 5: Address offset (0-255)
  ///
  /// The bank selection uses only bit 0 of byte 4, so values like 0x00 and
  /// 0x01 select different banks, while 0x02 would select bank 0 again.
  ///
  /// Throws [ArgumentError] if data is too short.
  void setF1(Uint8List data) {
    log?.info('Received F1 flash access command: ${data.xxd()}');

    switch (FlashCommand.fromByte(data[1])) {
      case .setAddress:
        // 0x0000:  00 0B FF FF 00 20 FF 10  FF
        flashBank = data[4];
        flashAddr = data[5];
        log?.debug(
          'Set flash bank to $flashBank, address to ${flashAddr.toHex()}',
        );
      case .write:
        (flashBank == 0 ? flashBankA : flashBankB).setAll(
          flashAddr,
          data.skip(7),
        );
        log?.debug(
          'Writing to flash bank $flashBank at address ${flashAddr.toHex()} with data: ${data.sublist(7, 7 + 0x10).xxd()}',
        );
    }
  }

  /// Constructs an **F1 – Flash Memory Read** response.
  ///
  /// Returns a 64-byte buffer containing:
  /// - Bytes 0-4: Fixed header (0x57, 0x0B, 0xFF, 0xFF, 0x10)
  /// - Bytes 5-20: 16 bytes of flash data from current bank/address
  ///
  /// The address is automatically aligned to 16-byte boundaries
  /// (address & 0xF0) to match hardware behavior. This means requesting
  /// addresses 0x20-0x2F will all return the same 16-byte block starting
  /// at 0x20.
  ///
  /// Flash contents include calibration values, lookup tables, and
  /// configuration data critical for proper controller operation.
  Uint8List getF1() {
    final result = Uint8List(64)
      ..setAll(0, const [0x57, 0x01, 0xFF, 0xFF, 0x10]);
    final flash = flashBank == 0 ? flashBankA : flashBankB;
    final addr = (flashAddr ~/ _flashReadBlockSize) * _flashReadBlockSize;

    for (var i = 0; i < _flashReadBlockSize; i++) {
      result[5 + i] = flash[(addr + i) & 0xFF];
    }
    log?.debug(
      'F1 flash read report from bank $flashBank, addr $addr: ${result.xxd()}',
    );
    return result;
  }

  /// Constructs a **01 – Controller Information** feature report.
  ///
  Uint8List get01() {
    log?.info('01 controller information report');
    final response = Uint8List(64)
      ..[0] = 0x00
      ..[1] = 0x01
      ..setAll(0x2, flashBankA.sublist(0x1, 0x5))
      ..setAll(0x5, flashBankA.sublist(0x60, 0x8C));
    log?.debug(response.xxd());
    return response;
  }

  /// Handles an **F4 – Controller Control** SET_FEATURE request.
  ///
  /// Commands are encoded as `[0x42, <command_byte>]` where 0x42 is the
  /// required command prefix.
  void setF4(Uint8List data) {
    log?.info('Received F4 controller control command: ${data.xxd()}');
    switch (F4Command.fromByte(data[1])) {
      case .enableInputStreaming:
      case .startupController:
        log?.success('Enabling input streaming');
        state[1] = 0x01;
      case .disableInputStreaming:
        log?.success('Disabling input streaming');
        state[1] = 0x00;
      case .enableOutputMotionSensors:
        log?.success('Enabling output streaming');
        state[1] = 0x03;
      case .restartController:
      case .shutdownController:
        log?.success('Resetting controller state');
        state
          ..[0] = 0x00
          ..[1] = 0x00
          ..[2] = 0x00
          ..[3] = 0x00;
        flashBank = 0;
        flashAddr = 0;
    }
  }
}
