import 'dart:io';
import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'network_service.dart';
import 'printer_manager.dart';

/// Network Printer
class NetworkPrinterManager extends PrinterManager {
  Socket? socket;

  NetworkPrinterManager(POSPrinter printer) {
    super.printer = printer;
  }

  /// [connect] let you connect to a network printer
  Future<ConnectionResponse> connect(
      {Duration? timeout = const Duration(seconds: 5)}) async {
    try {
      this.socket = await Socket.connect(printer.address, printer.port!,
          timeout: timeout);

      this.printer.connected = true;
      return Future<ConnectionResponse>.value(ConnectionResponse.success);
    } catch (e) {
      this.printer.connected = false;
      return Future<ConnectionResponse>.value(ConnectionResponse.timeout);
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
  Future<ConnectionResponse> writeBytes(List<int> data,
      {bool isDisconnect = true}) async {
    try {
      if (!printer.connected) {
        await connect();
      }
      print(this.socket);
      this.socket?.add(data);
      if (isDisconnect) {
        await disconnect();
      }
      return ConnectionResponse.success;
    } catch (e) {
      return ConnectionResponse.printerNotConnected;
    }
  }

  /// [timeout]: milliseconds to wait after closing the socket
  Future<ConnectionResponse> disconnect({Duration? timeout}) async {
    await socket?.flush();
    await socket?.close();
    this.printer.connected = false;
    if (timeout != null) {
      await Future.delayed(timeout, () => null);
    }
    return ConnectionResponse.success;
  }
}
