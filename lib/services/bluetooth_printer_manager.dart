import 'dart:async';
import 'dart:io';
import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:drago_pos_printer/services/chennel.dart';
import 'package:drago_pos_printer/utils/esc_pos/commands.dart';
import 'printer_manager.dart';

/// Bluetooth Printer
class BluetoothPrinterManager extends PrinterManager {
  BluetoothPrinterManager(
    POSPrinter printer,
  ) {
    super.printer = printer;
  }

  /// [connect] let you connect to a bluetooth printer
  Future connect({Duration? timeout = const Duration(seconds: 5)}) async {
    try {
      if (Platform.isAndroid) {
        Map<String, dynamic> params = {
          "address": printer.address,
          "isBle": false,
          "autoConnect": true
        };
        await flutterPrinterChannel.invokeMethod('onStartConnection', params);
      } else if (Platform.isIOS) {
        Map<String, dynamic> params = {
          "name": printer.name,
          "address": printer.address
        };
        await iosChannel.invokeMethod('connect', params);
      }
    } catch (e) {
      if ((e as dynamic).message == "already connected") {
        await disconnect();
        await connect();
      } else
        return Future.error(e.toString());
    }
  }

  /// [discover] let you explore all bluetooth printer nearby your device
  static Future<List<BluetoothPrinter>> discover() async {
    var results = await flutterPrinterChannel.invokeMethod('getBluetoothList');
    return List.from(results)
        .map((r) => BluetoothPrinter(
              name: r['name'],
              address: r['address'],
            ))
        .toList();
  }

  /// [writeBytes] let you write raw list int data into socket
  @override
  Future writeBytes(List<int> bytes,
      {Duration? timeout = const Duration(milliseconds: 20)}) async {
    try {
      if (Platform.isAndroid) {
        bytes += cCutFull.codeUnits;
        Map<String, dynamic> params = {"bytes": bytes};
        bool res =
            await flutterPrinterChannel.invokeMethod('sendDataByte', params);
        print('WriteDataByte Result: $res');
      } else if (Platform.isIOS) {
        Map<String, Object> args = Map();
        args['bytes'] = bytes;
        args['length'] = bytes.length;
        iosChannel.invokeMethod('writeData', args);
      }
    } catch (e) {
      return Future.error(e.toString());
    }
  }

  /// [timeout]: milliseconds to wait after closing the socket
  Future disconnect({Duration? timeout}) async {
    try {
      if (Platform.isAndroid)
        await flutterPrinterChannel.invokeMethod('disconnect');
      else if (Platform.isIOS) await iosChannel.invokeMethod('disconnect');
    } catch (e) {
      return Future.error(e.toString());
    }
    if (timeout != null) {
      await Future.delayed(timeout, () => null);
    }
  }
}
