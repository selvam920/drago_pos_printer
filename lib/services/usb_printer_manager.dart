import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:drago_usb_printer/drago_usb_printer.dart';
import 'package:win32/win32.dart';
import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:drago_pos_printer/services/printer_manager.dart';
import 'extension.dart';
import 'usb_service.dart';

/// USB Printer
class USBPrinterManager extends PrinterManager {
  /// usb_serial
  var usbPrinter = DragoUsbPrinter();

  /// [win32] spooler handle, open between [connect] and [disconnect].
  PRINTER_HANDLE? _hPrinter;

  /// [android] true between a successful [connect] and [disconnect].
  bool _androidConnected = false;

  USBPrinterManager(POSPrinter printer) {
    super.printer = printer;
  }

  /// Opens a spooler handle for [printer]; throws on failure, leaks nothing.
  PRINTER_HANDLE _openWindowsPrinter() {
    final name = printer.name;
    if (name == null || name.isEmpty) {
      throw Exception('Printer name is empty');
    }
    final szPrinterName = name.toNativeUtf16();
    final phPrinterPtr = calloc<Pointer>();
    try {
      final ok = OpenPrinter(PCWSTR(szPrinterName), phPrinterPtr, nullptr);
      if (!ok.value || phPrinterPtr.value == nullptr) {
        throw Exception('Failed to open printer: $name');
      }
      return PRINTER_HANDLE(phPrinterPtr.value);
    } finally {
      calloc.free(phPrinterPtr);
      calloc.free(szPrinterName);
    }
  }

  void _closeWindowsPrinter() {
    final h = _hPrinter;
    _hPrinter = null;
    if (h != null) {
      try {
        ClosePrinter(h);
      } catch (_) {}
    }
  }

  @override
  Future connect({Duration? timeout = const Duration(seconds: 5)}) async {
    if (Platform.isWindows) {
      if (_hPrinter != null) return;
      try {
        _hPrinter = _openWindowsPrinter();
      } catch (e) {
        _hPrinter = null;
        return Future.error(e.toString());
      }
    } else if (Platform.isAndroid) {
      if (_androidConnected) return;
      final vendorId = printer.vendorId;
      final productId = printer.productId;
      if (vendorId == null || productId == null) {
        return Future.error('USB printer has no vendorId/productId');
      }
      bool? ok;
      try {
        ok = await usbPrinter.connect(vendorId, productId);
      } catch (e) {
        return Future.error('Failed to connect USB printer: $e');
      }
      if (ok != true) {
        return Future.error(
            'Failed to connect USB printer ($vendorId:$productId)');
      }
      _androidConnected = true;
    }
  }

  /// [discover] let you explore all netWork printer in your network
  static Future<List<USBPrinter>> discover() async {
    var results = await USBService.findUSBPrinter();
    return results;
  }

  @override
  Future disconnect({Duration? timeout}) async {
    if (Platform.isWindows) {
      _closeWindowsPrinter();
    } else if (Platform.isAndroid) {
      if (_androidConnected) {
        _androidConnected = false;
        try {
          await usbPrinter.close();
        } catch (_) {
          // Already closed / detached: nothing to clean up.
        }
      }
    }
    if (timeout != null) {
      await Future.delayed(timeout);
    }
    return true;
  }

  /// Writes [data] as one RAW spooler job (Windows) or bulk transfer
  /// (Android). Uses the connection opened by [connect]; if none is open,
  /// opens one for this write and closes it again afterwards.
  @override
  Future writeBytes(List<int> data, {int? vendorId, int? productId}) async {
    if (Platform.isWindows) {
      final ownHandle = _hPrinter == null;
      PRINTER_HANDLE h;
      try {
        h = _hPrinter ?? _openWindowsPrinter();
      } catch (e) {
        return Future.error(e.toString());
      }
      final pDocName = 'My Document'.toNativeUtf16();
      final pDataType = 'RAW'.toNativeUtf16();
      final dwBytesWritten = calloc<DWORD>();
      final docInfo = calloc<DOC_INFO_1>()
        ..ref.pDocName = PWSTR(pDocName)
        ..ref.pOutputFile = PWSTR(nullptr.cast<Utf16>())
        ..ref.pDatatype = PWSTR(pDataType);
      var docStarted = false;
      var pageStarted = false;
      try {
        if (StartDocPrinter(h, 1, docInfo) == 0) {
          throw Exception('StartDocPrinter failed');
        }
        docStarted = true;
        if (!StartPagePrinter(h)) throw Exception('StartPagePrinter failed');
        pageStarted = true;

        // Send in chunks: writing all at once makes some drivers paginate.
        const int chunkSize = 4096;
        int totalWritten = 0;
        for (final chunk in data.chunkBy(chunkSize)) {
          final lpData = chunk.toUint8();
          try {
            final ok = WritePrinter(h, lpData, chunk.length, dwBytesWritten);
            if (!ok) {
              throw Exception('WritePrinter failed after $totalWritten bytes');
            }
            totalWritten += dwBytesWritten.value;
          } finally {
            calloc.free(lpData);
          }
        }

        pageStarted = false;
        if (!EndPagePrinter(h)) throw Exception('EndPagePrinter failed');
        docStarted = false;
        if (!EndDocPrinter(h)) throw Exception('EndDocPrinter failed');
      } catch (e) {
        return Future.error(e.toString());
      } finally {
        if (pageStarted) EndPagePrinter(h);
        if (docStarted) EndDocPrinter(h);
        if (ownHandle) {
          try {
            ClosePrinter(h);
          } catch (_) {}
        }
        calloc.free(docInfo);
        calloc.free(dwBytesWritten);
        calloc.free(pDocName);
        calloc.free(pDataType);
      }
    } else if (Platform.isAndroid) {
      final ownConnection = !_androidConnected;
      try {
        await connect();
        // maxChunk limit on android
        for (final chunk in data.chunkBy(16384)) {
          final ok = await usbPrinter.write(Uint8List.fromList(chunk));
          if (ok == false) throw Exception('USB write failed');
        }
      } catch (e) {
        return Future.error(e.toString());
      } finally {
        if (ownConnection) await disconnect();
      }
    }
  }

  /// Asks the printer whether it can take [job] (Android only; uses the
  /// vendor/product id stored by [connect]). [PrinterReadiness.unknown] on
  /// any error, timeout or other platform.
  Future<PrinterReadiness> checkStatus(List<int> job) async {
    if (!Platform.isAndroid) return PrinterReadiness.unknown;
    final q = PrinterStatusQuery.forJob(job);
    try {
      // Dynamic so this builds against drago_usb_printer versions that do
      // not have queryStatus yet (NoSuchMethodError -> unknown).
      final Uint8List? reply = await (usbPrinter as dynamic).queryStatus(
        q.query,
        timeout: const Duration(milliseconds: 1500),
      ) as Uint8List?;
      return q.parse(reply);
    } catch (_) {
      return PrinterReadiness.unknown;
    }
  }

  @override
  Future<void> pair(POSPrinter device) async {
    // USB printers do not require pairing.
  }

  @override
  Stream<POSPrinter> scan() async* {
    final results = await discover();
    for (final device in results) {
      yield device;
    }
  }
}
