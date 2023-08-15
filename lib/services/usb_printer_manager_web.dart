import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';

class USBPrinterManager {
  USBPrinterManager(POSPrinter printer);

  Future<ConnectionResponse> connect(
      {Duration? timeout = const Duration(seconds: 5)}) {
    throw Exception('Platform does not support');
  }

  static Future<List<USBPrinter>> discover() {
    throw Exception('Platform does not support');
  }

  Future<ConnectionResponse> disconnect({Duration? timeout}) {
    throw Exception('Platform does not support');
  }

  Future<ConnectionResponse> writeBytes(List<int> data) {
    throw Exception('Platform does not support');
  }
}
