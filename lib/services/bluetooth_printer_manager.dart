import 'dart:async';
import 'dart:io';

import 'package:drago_blue_printer/drago_blue_printer.dart';
import 'package:flutter/services.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:drago_pos_printer/services/chennel.dart';

import 'printer_manager.dart';

/// Bluetooth Printer
class BluetoothPrinterManager extends PrinterManager {
  /// The printer the Android link is open to, kept across jobs so the next
  /// bill reuses it. Cleared on disconnect or a failed write.
  static String? _connectedAddress;

  BluetoothPrinterManager(POSPrinter printer) {
    super.printer = printer;
  }

  /// [connect] let you connect to a bluetooth printer
  @override
  Future connect({Duration? timeout = const Duration(seconds: 5)}) =>
      _connect(retry: true);

  Future _connect({required bool retry}) async {
    if (printer.address == null || printer.address!.isEmpty) {
      return Future.error('Bluetooth printer has no address');
    }
    try {
      if (Platform.isAndroid) {
        final bluetooth = DragoBluePrinter.instance;
        final bool? isConnected = await bluetooth.isConnected;
        // Still linked to this printer from the last job: nothing to do.
        // Reconnecting cost 1-3 s on every bill.
        if (isConnected == true && _connectedAddress == printer.address) {
          return;
        }
        if (isConnected == true) await bluetooth.disconnect();
        _connectedAddress = null;
        // Name + address is all connect needs; no bonded-list lookup.
        await bluetooth.connect(
          BluetoothDevice(printer.name ?? 'Unknown', printer.address!),
        );
        _connectedAddress = printer.address;
      } else if (Platform.isIOS) {
        Map<String, dynamic> params = {
          "name": printer.name,
          "address": printer.address,
        };
        await iosChannel.invokeMethod('connect', params);
      }
    } catch (e) {
      final msg = e is PlatformException ? e.message : null;
      if (retry && msg == "already connected") {
        // Retry exactly once so a stuck "already connected" cannot loop.
        try {
          await disconnect();
        } catch (_) {}
        return _connect(retry: false);
      }
      return Future.error(e.toString());
    }
  }

  /// [discover] let you explore all bluetooth printer nearby your device
  /// On Android, this now uses [scan] for more comprehensive discovery.
  static Future<List<BluetoothPrinter>> discover() async {
    if (Platform.isAndroid) {
      // Use scan stream and collect for a short period?
      // Or just return bonded?
      // User asked for "scan", so likely they will use scan() directly.
      // But preserving discover() behavior:
      final bluetooth = DragoBluePrinter.instance;
      List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
      return devices
          .map(
            (r) => BluetoothPrinter(
              name: r.name,
              address: r.address,
              type: r.type,
              battery: r.battery,
              connected: r.connected,
            ),
          )
          .toList();
    }
    var results = await flutterPrinterChannel.invokeMethod('getBluetoothList');
    return List.from(results)
        .map((r) => BluetoothPrinter(name: r['name'], address: r['address']))
        .toList();
  }

  /// [scan] scans for Bluetooth devices (Android only)
  @override
  Stream<BluetoothPrinter> scan() {
    if (Platform.isAndroid) {
      return DragoBluePrinter.instance.scan().map(
        (d) => BluetoothPrinter(name: d.name, address: d.address, type: d.type),
      );
    }
    // Fallback for others or empty stream
    return Stream.empty();
  }

  /// [pair] pairs a Bluetooth device (Android only)
  @override
  Future<void> pair(POSPrinter device) async {
    if (Platform.isAndroid) {
      await DragoBluePrinter.instance.pairDevice(
        BluetoothDevice(device.name ?? "Unknown", device.address!),
      );
    }
  }

  /// Asks the connected printer whether it can take [job] (Android only;
  /// call after [connect]). [PrinterReadiness.unknown] when it won't say.
  Future<PrinterReadiness> checkStatus(List<int> job) async {
    if (!Platform.isAndroid) return PrinterReadiness.unknown;
    final q = PrinterStatusQuery.forJob(job);
    try {
      return q.parse(await DragoBluePrinter.instance.queryStatus(q.query));
    } catch (_) {
      return PrinterReadiness.unknown;
    }
  }

  /// [writeBytes] let you write raw list int data into socket
  @override
  Future writeBytes(
    List<int> bytes, {
    Duration? timeout = const Duration(milliseconds: 20),
  }) async {
    try {
      if (Platform.isAndroid) {
        final bluetooth = DragoBluePrinter.instance;
        // DragoBluePrinter likely has writeBytes. If not, this will fail at runtime or analysis.
        // Based on typical structure of such plugins.
        await bluetooth.writeBytes(Uint8List.fromList(bytes));
      } else if (Platform.isIOS) {
        Map<String, Object> args = Map();
        args['bytes'] = bytes;
        args['length'] = bytes.length;
        await iosChannel.invokeMethod('writeData', args);
      }
    } catch (e) {
      // A stale link (printer switched off): the next connect starts fresh.
      _connectedAddress = null;
      return Future.error(e.toString());
    }
  }

  /// [timeout]: milliseconds to wait after closing the socket
  @override
  Future disconnect({Duration? timeout}) async {
    try {
      _connectedAddress = null;
      if (Platform.isAndroid) {
        await DragoBluePrinter.instance.disconnect();
      } else if (Platform.isIOS)
        await iosChannel.invokeMethod('disconnect');
    } catch (e) {
      return Future.error(e.toString());
    }
    if (timeout != null) {
      await Future.delayed(timeout, () => null);
    }
  }
}
