import 'package:drago_pos_printer/enums/connection_type.dart';
import 'package:drago_pos_printer/models/pos_printer.dart';

class BluetoothPrinter extends POSPrinter {
  /// Battery % when the printer reports it to the phone, else null.
  int? battery;

  /// The phone currently holds a link to it.
  bool connected;

  BluetoothPrinter({
    String? id,
    String? name,
    String? address,
    int type = 0,
    ConnectionType? connectionType,
    this.battery,
    this.connected = false,
  }) {
    this.id = id;
    this.name = name;
    this.address = address;
    this.type = type;
    this.connectionType = ConnectionType.bluetooth;
  }
}
