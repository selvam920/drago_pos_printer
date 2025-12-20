import 'package:drago_pos_printer/models/pos_printer.dart';

abstract class PrinterManager {
  late POSPrinter printer;

  Future connect({Duration? timeout});

  Future writeBytes(List<int> data);

  Future disconnect({Duration? timeout});

  Stream<POSPrinter> scan();

  Future<void> pair(POSPrinter device);
}
