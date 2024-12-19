import 'package:flutter/services.dart';

final flutterPrinterChannel =
    const MethodChannel('com.example.drago_pos_printer');
final flutterPrinterEventChannelBT =
    const EventChannel('com.example.drago_pos_printer/bt_state');
final flutterPrinterEventChannelUSB =
    const EventChannel('com.example.drago_pos_printer/usb_state');
final iosChannel = const MethodChannel('drago_pos_printer/methods');
final iosStateChannel = const EventChannel('drago_pos_printer/state');
