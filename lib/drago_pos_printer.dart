export 'package:drago_pos_printer/models/network_printer.dart';
export 'package:drago_pos_printer/models/bluetooth_printer.dart';
export 'package:drago_pos_printer/models/usb_printer.dart';

export 'package:drago_pos_printer/services/bluetooth_printer_manager_web.dart'
    if (dart.library.js) 'package:drago_pos_printer/services/bluetooth_printer_manager_web.dart'
    if (dart.library.io) 'package:drago_pos_printer/services/bluetooth_printer_manager.dart';

export 'package:drago_pos_printer/services/network_printer_manager.dart';

export 'package:drago_pos_printer/services/usb_printer_manager_web.dart'
    if (dart.library.js) 'package:drago_pos_printer/services/usb_printer_manager_web.dart'
    if (dart.library.io) 'package:drago_pos_printer/services/usb_printer_manager.dart';

export 'package:drago_pos_printer/enums/bluetooth_printer_type.dart';
export 'package:drago_pos_printer/enums/connection_response.dart';
export 'package:drago_pos_printer/enums/connection_type.dart';
export 'package:drago_pos_printer/utils/esc_pos_utils.dart';
export 'package:drago_pos_printer/utils/tsc_utils.dart';

class DragoPrinterManager {}
