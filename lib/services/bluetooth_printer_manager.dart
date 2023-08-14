import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:drago_blue_printer/drago_blue_printer.dart' as themal;
import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'bluetooth_service.dart';
import 'printer_manager.dart';

/// Bluetooth Printer
class BluetoothPrinterManager extends PrinterManager {
  themal.DragoBluePrinter bluetooth = themal.DragoBluePrinter.instance;
  // fblue.FlutterBlue flutterBlue = fblue.FlutterBlue.instance;
  // fblue.BluetoothDevice fbdevice;

  BluetoothPrinterManager(
    POSPrinter printer,
  ) {
    super.printer = printer;
  }

  /// [connect] let you connect to a bluetooth printer
  Future<ConnectionResponse> connect(
      {Duration? timeout = const Duration(seconds: 5)}) async {
    try {
      // if (Platform.isIOS) {
      // fbdevice = fblue.BluetoothDevice.fromProto(proto.BluetoothDevice(
      //     name: printer.name,
      //     remoteId: printer.address,
      //     type: proto.BluetoothDevice_Type.valueOf(printer.type)));
      // var connected = await flutterBlue.connectedDevices;
      // var index = connected?.indexWhere((e) => e.id == fbdevice.id);
      // if (index < 0) await fbdevice.connect();

      // } else
      if (Platform.isAndroid || Platform.isIOS) {
        var device = themal.BluetoothDevice(printer.name, printer.address);
        await bluetooth.connect(device);
      }

      this.printer.connected = true;
      return Future<ConnectionResponse>.value(ConnectionResponse.success);
    } catch (e) {
      if ((e as dynamic).message == "already connected") {
        await disconnect();
        await connect();

        this.printer.connected = true;
        return Future<ConnectionResponse>.value(ConnectionResponse.success);
      } else {
        this.printer.connected = false;
        return Future<ConnectionResponse>.value(ConnectionResponse.timeout);
      }
    }
  }

  /// [connect] let you connect to a bluetooth printer
  Future<bool> checkConnected() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        var device = themal.BluetoothDevice(printer.name, printer.address);
        return (await bluetooth.isDeviceConnected(device)) ?? false;
      }
    } catch (e) {}

    return Future<bool>.value(false);
  }

  /// [discover] let you explore all bluetooth printer nearby your device
  static Future<List<BluetoothPrinter>> discover() async {
    var results = await BluetoothService.findBluetoothDevice();
    return [
      ...results
          .map((e) => BluetoothPrinter(
                id: e.address,
                name: e.name,
                address: e.address,
                type: e.type,
              ))
          .toList()
    ];
  }

  /// [writeBytes] let you write raw list int data into socket
  @override
  Future<ConnectionResponse> writeBytes(List<int> data,
      {bool isDisconnect = true,
      Duration? timeout = const Duration(milliseconds: 20)}) async {
    try {
      if (!printer.connected) {
        await connect();
      }
      if (Platform.isAndroid || Platform.isIOS) {
        if ((await bluetooth.isConnected) ?? false) {
          if (timeout != null) {
            await Future.delayed(timeout, () => null);
          }
          Uint8List message = Uint8List.fromList(data);
          await bluetooth.writeBytes(message);
          if (isDisconnect) {
            await disconnect();
          }
          return ConnectionResponse.success;
        }
        return ConnectionResponse.printerNotConnected;
      }
      //  else if (Platform.isIOS) {
      //   // var services = (await fbdevice.discoverServices());
      //   // var service = services.firstWhere((e) => e.isPrimary);
      //   // var charactor =
      //   //     service.characteristics.firstWhere((e) => e.properties.write);
      //   // await charactor?.write(data, withoutResponse: true);
      //   return ConnectionResponse.success;
      // }
      return ConnectionResponse.unsupport;
    } catch (e) {
      print("Error : $e");
      return ConnectionResponse.unknown;
    }
  }

  /// [timeout]: milliseconds to wait after closing the socket
  Future<ConnectionResponse> disconnect({Duration? timeout}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await bluetooth.disconnect();
      this.printer.connected = false;
    }
    //  else if (Platform.isIOS) {
    // await fbdevice.disconnect();
    // this.isConnected = false;
    // }

    if (timeout != null) {
      await Future.delayed(timeout, () => null);
    }
    return ConnectionResponse.success;
  }
}
