import 'dart:io';
import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:drago_pos_printer/utils/esc_pos/commands.dart';
import 'network_service.dart';
import 'printer_manager.dart';

/// Network Printer
class NetworkPrinterManager extends PrinterManager {
  Socket? socket;

  NetworkPrinterManager(POSPrinter printer) {
    super.printer = printer;
  }

  /// [connect] let you connect to a network printer
  Future connect({Duration? timeout = const Duration(seconds: 5)}) async {
    try {
      this.socket = await Socket.connect(printer.address, printer.port!,
          timeout: timeout);
    } catch (e) {
      return Future.error(e.toString());
    }
  }

  /// [discover] let you explore all netWork printer in your network
  static Future<List<NetWorkPrinter>> discover() async {
    var results = await findNetworkPrinter();
    return [
      ...results
          .map((e) => NetWorkPrinter(
                id: e,
                name: e,
                address: e,
                type: 0,
              ))
          .toList()
    ];
  }

  /// [writeBytes] let you write raw list int data into socket
  @override
  Future writeBytes(List<int> data) async {
    try {
      data += cCutFull.codeUnits;
      this.socket?.add(data);
    } catch (e) {
      return Future.error(e.toString());
    }
  }

  /// [timeout]: milliseconds to wait after closing the socket
  Future disconnect({Duration? timeout}) async {
    await socket?.flush();
    await socket?.close();
    if (timeout != null) {
      await Future.delayed(timeout, () => null);
    }
  }
}
