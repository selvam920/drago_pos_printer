import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';

class BluetoothPrinterManager {
  late CapabilityProfile profile;
  BluetoothPrinterManager(
    POSPrinter printer,
    int paperSizeWidthMM,
    int maxPerLine,
    CapabilityProfile profile, {
    int spaceBetweenRows = 5,
    int port = 9100,
  });

  Future<ConnectionResponse> connect(
      {Duration? timeout = const Duration(seconds: 5)}) {
    throw Exception('Platform does not support');
  }

  static Future<List<BluetoothPrinter>> discover() {
    throw Exception('Platform does not support');
  }

  Future<ConnectionResponse> disconnect({Duration? timeout}) {
    throw Exception('Platform does not support');
  }

  Future<ConnectionResponse> writeBytes(List<int> data,
      {bool isDisconnect = true}) {
    throw Exception('Platform does not support');
  }
}
