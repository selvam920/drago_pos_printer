import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';

abstract class PrinterManager {
  late POSPrinter printer;

  Future<ConnectionResponse> connect({Duration? timeout});

  Future<ConnectionResponse> writeBytes(List<int> data);

  Future<ConnectionResponse> disconnect({Duration? timeout});
}
