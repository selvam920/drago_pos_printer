import 'package:drago_pos_printer/enums/connection_type.dart';
import 'package:drago_pos_printer/models/pos_printer.dart';

class NetWorkPrinter extends POSPrinter {
  NetWorkPrinter({
    String? id,
    String? name,
    String? address,
    int type = 0,
    ConnectionType? connectionType,
  }) {
    this.id = id;
    this.name = name;
    this.address = address;
    this.type = type;
    this.connectionType = ConnectionType.network;
  }
}
