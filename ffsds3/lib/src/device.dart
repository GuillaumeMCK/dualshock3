import 'dart:async';
import 'dart:typed_data';

import 'package:usb_gadget/usb_gadget.dart';

import 'reports/feature_reports.dart';
import 'reports/input_report.dart';
import 'reports/output_report.dart';

(Gadget gadget, Dualshock3 dualshock3) createDualshock3([
  String name = 'ds3_gadget',
]) {
  final dualshock3 = Dualshock3();
  final gadget = Gadget(
    name: name,
    idVendor: 0x054C,
    idProduct: 0x0268,
    deviceProtocol: .none,
    deviceSubClass: .none,
    deviceClass: .composite,
    strings: {
      .enUS: .new(
        manufacturer: 'Sony Computer Entertainment Inc.',
        product: 'PLAYSTATION(R)3 Controller',
        serialnumber: 'SN00000000',
      ),
    },
    config: .new(
      attributes: .busPowered,
      maxPower: .fromMilliAmps(500),
      functions: [dualshock3],
    ),
  );
  return (gadget, dualshock3);
}

/// Emulates a Sony DualShock 3 controller using FunctionFS.
final class Dualshock3 extends HIDFunctionFs {
  Dualshock3({List<int>? deviceMac, List<int>? pairedMac, int? serialNumber})
    : input = InputReport(),
      output = OutputReport(),
      features = FeatureReport(
        deviceMac: deviceMac ?? const [0x9E, 0xE8, 0x28, 0x31, 0xC7, 0x33],
        pairedMac: pairedMac ?? const [0x90, 0x34, 0xFC, 0xA5, 0xE5, 0x0B],
        serialNumber: serialNumber ?? 0x01D88151,
      ),
      super(
        name: 'dualshock3',
        reportDescriptor: .fromList([
          0x05, 0x01, // Usage Page (Generic Desktop Ctrls)
          0x09, 0x04, // Usage (Joystick)
          0xA1, 0x01, // Collection (Physical)
          0xA1, 0x02, //   Collection (Application)
          0x85, 0x01, //     Report ID (1)
          0x75, 0x08, //     Report Size (8)
          0x95, 0x01, //     Report Count (1)
          0x15, 0x00, //     Logical Minimum (0)
          0x26, 0xFF, 0x00, //     Logical Maximum (255)
          0x81, 0x03, //     Input (Const,Var,Abs,No Wrap,Linear,Preferred
          //     State,No Null Position)
          // NOTE: reserved byte
          0x75, 0x01, //     Report Size (1)
          0x95, 0x13, //     Report Count (19)
          0x15, 0x00, //     Logical Minimum (0)
          0x25, 0x01, //     Logical Maximum (1)
          0x35, 0x00, //     Physical Minimum (0)
          0x45, 0x01, //     Physical Maximum (1)
          0x05, 0x09, //     Usage Page (Button)
          0x19, 0x01, //     Usage Minimum (0x01)
          0x29, 0x13, //     Usage Maximum (0x13)
          0x81, 0x02, //     Input (Data,Var,Abs,No Wrap,Linear,Preferred
          //     State,No Null Position)
          0x75, 0x01, //     Report Size (1)
          0x95, 0x0D, //     Report Count (13)
          0x06, 0x00, 0xFF, //     Usage Page (Vendor Defined 0xFF00)
          0x81, 0x03, //     Input (Const,Var,Abs,No Wrap,Linear,Preferred
          //     State,No Null Position)
          // NOTE: 32 bit integer, where 0:18 are buttons and 19:31 are reserved
          0x15, 0x00, //     Logical Minimum (0)
          0x26, 0xFF, 0x00, //     Logical Maximum (255)
          0x05, 0x01, //     Usage Page (Generic Desktop Ctrls)
          0x09, 0x01, //     Usage (Pointer)
          0xA1, 0x00, //     Collection (Undefined)
          0x75, 0x08, //       Report Size (8)
          0x95, 0x04, //       Report Count (4)
          0x35, 0x00, //       Physical Minimum (0)
          0x46, 0xFF, 0x00, //       Physical Maximum (255)
          0x09, 0x30, //       Usage (X)
          0x09, 0x31, //       Usage (Y)
          0x09, 0x32, //       Usage (Z)
          0x09, 0x35, //       Usage (Rz)
          0x81, 0x02, //       Input (Data,Var,Abs,No Wrap,Linear,Preferred
          //     State,No Null Position)
          //       NOTE: four joysticks
          0xC0, //     End Collection
          0x05, 0x01, //     Usage Page (Generic Desktop Ctrls)
          0x75, 0x08, //     Report Size (8)
          0x95, 0x27, //     Report Count (39)
          0x09, 0x01, //     Usage (Pointer)
          0x81, 0x02, //     Input (Data,Var,Abs,No Wrap,Linear,Preferred
          //     State,No Null Position)
          0x75, 0x08, //     Report Size (8)
          0x95, 0x30, //     Report Count (48)
          0x09, 0x01, //     Usage (Pointer)
          0x91, 0x02, //     Output (Data,Var,Abs,No Wrap,Linear,Preferred
          //     State,No Null Position,Non-volatile)
          0x75, 0x08, //     Report Size (8)
          0x95, 0x30, //     Report Count (48)
          0x09, 0x01, //     Usage (Pointer)
          0xB1, 0x02, //     Feature (Data,Var,Abs,No Wrap,Linear,Preferred
          //     State,No Null Position,Non-volatile)
          0xC0, //   End Collection
          0xA1, 0x02, //   Collection (Application)
          0x85, 0x02, //     Report ID (2)
          0x75, 0x08, //     Report Size (8)
          0x95, 0x30, //     Report Count (48)
          0x09, 0x01, //     Usage (Pointer)
          0xB1, 0x02, //     Feature (Data,Var,Abs,No Wrap,Linear,Preferred
          //     State,No Null Position,Non-volatile)
          0xC0, //   End Collection
          0xA1, 0x02, //   Collection (Application)
          0x85, 0xEE, //     Report ID (238)
          0x75, 0x08, //     Report Size (8)
          0x95, 0x30, //     Report Count (48)
          0x09, 0x01, //     Usage (Pointer)
          0xB1, 0x02, //     Feature (Data,Var,Abs,No Wrap,Linear,Preferred
          //     State,No Null Position,Non-volatile)
          0xC0, //   End Collection
          0xA1, 0x02, //   Collection (Application)
          0x85, 0xEF, //     Report ID (239)
          0x75, 0x08, //     Report Size (8)
          0x95, 0x30, //     Report Count (48)
          0x09, 0x01, //     Usage (Pointer)
          0xB1, 0x02, //     Feature (Data,Var,Abs,No Wrap,Linear,Preferred
          //     State,No Null Position,Non-volatile)
          0xC0, //   End Collection
          0xC0, // End Collection
        ]),
        speeds: {.fullSpeed, .highSpeed},
        subclass: .none,
        protocol: .none,
        config: const .bidirectional(
          pollInterval: .new(milliseconds: 10),
          reportInterval: .new(milliseconds: 10),
        ),
      );

  final InputReport input;
  final FeatureReport features;
  final OutputReport output;

  Timer? _epInTimer;
  StreamSubscription<Uint8List>? _epOutSub;

  @override
  Future<void> onEnable() async {
    super.onEnable();
    log?.info('Controller configured by host');
    _epInTimer ??= .periodic(config.reportInterval, (_) {
      if (features.inputStreamingEnabled) {
        epIn.write(input.bytes);
      }
    });
    _epOutSub ??= epOut.stream.listen(
      (bytes) => switch (bytes) {
        [0x01, ...final data] when data.length == 48 => output.update(data),
        _ => log?.warn('Received unrecognized output report: ${bytes.xxd()}'),
      },
    );
  }

  @override
  Future<void> release() async {
    _epInTimer?.cancel();
    _epInTimer = null;
    await _epOutSub?.cancel();
    _epOutSub = null;
    await super.release();
  }

  @override
  Uint8List onGetReport(HIDReportType type, int reportId) {
    log?.debug('GET_REPORT: type=${type.name}, id=${reportId.toHex()}');
    return switch ((type, reportId)) {
      (.input, 0x01) => input.bytes,
      (.feature, 0x01) => features.get01(),
      (.feature, 0xF1) => features.getF1(),
      (.feature, 0xF2) => features.getF2(),
      (.feature, 0xF5) => features.getF5(),
      (.feature, 0xEF) => features.getEF(),
      (.feature, 0xF8) => features.getF8(),
      (.feature, 0xF7) => features.getF7(),
      _ => throw UnsupportedError(
        'Unhandled GET_REPORT: type=${type.name}, id=${reportId.toHex()}',
      ),
    };
  }

  @override
  void onSetReport(HIDReportType type, int reportId, Uint8List data) {
    log?.debug(
      'SET_REPORT: type=${type.name}, id=${reportId.toHex()}, '
      'len=${data.length}',
    );
    return switch ((type, reportId)) {
      (.output, 0x01) => output.update(data),
      (.feature, 0xEF) => features.setEF(data),
      (.feature, 0xF1) => features.setF1(data),
      (.feature, 0xF4) => features.setF4(data),
      (.feature, 0xF5) => features.setF5(data),
      _ => throw UnsupportedError(
        'Unhandled SET_REPORT: type=${type.name}, id=${reportId.toHex()}',
      ),
    };
  }
}
