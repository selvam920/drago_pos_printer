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

  /// [win32]
  Pointer<IntPtr>? phPrinter = calloc<HANDLE>();
  Pointer<Utf16> pDocName = 'My Document'.toNativeUtf16();
  Pointer<Utf16> pDataType = 'RAW'.toNativeUtf16();
  Pointer<Uint32>? dwBytesWritten = calloc<DWORD>();
  Pointer<DOC_INFO_1>? docInfo;
  late Pointer<Utf16> szPrinterName;
  late int hPrinter;
  int? dwCount;

  USBPrinterManager(POSPrinter printer) {
    super.printer = printer;
  }

  @override
  Future<ConnectionResponse> connect(
      {Duration? timeout = const Duration(seconds: 5)}) async {
    if (Platform.isWindows) {
      try {
        docInfo = calloc<DOC_INFO_1>()
          ..ref.pDocName = pDocName
          ..ref.pOutputFile = nullptr
          ..ref.pDatatype = pDataType;
        szPrinterName = printer.name!.toNativeUtf16();

        final phPrinter = calloc<HANDLE>();
        if (OpenPrinter(szPrinterName, phPrinter, nullptr) == FALSE) {
          this.printer.connected = false;
          return Future<ConnectionResponse>.value(
              ConnectionResponse.printerNotConnected);
        } else {
          this.hPrinter = phPrinter.value;

          this.printer.connected = true;
          return Future<ConnectionResponse>.value(ConnectionResponse.success);
        }
      } catch (e) {
        this.printer.connected = false;
        return Future<ConnectionResponse>.value(ConnectionResponse.timeout);
      }
    } else if (Platform.isAndroid) {
      var usbDevice =
          await usbPrinter.connect(printer.vendorId!, printer.productId!);
      if (usbDevice != null) {
        this.printer.connected = true;
        return Future<ConnectionResponse>.value(ConnectionResponse.success);
      } else {
        this.printer.connected = false;
        return Future<ConnectionResponse>.value(ConnectionResponse.timeout);
      }
    } else {
      return Future<ConnectionResponse>.value(ConnectionResponse.timeout);
    }
  }

  /// [discover] let you explore all netWork printer in your network
  static Future<List<USBPrinter>> discover() async {
    var results = await USBService.findUSBPrinter();
    return results;
  }

  @override
  Future<ConnectionResponse> disconnect({Duration? timeout}) async {
    if (Platform.isWindows) {
      // Tidy up the printer handle.
      ClosePrinter(hPrinter);
      free(phPrinter!);
      free(pDocName);
      free(pDataType);
      free(dwBytesWritten!);
      free(docInfo!);
      free(szPrinterName);

      this.printer.connected = false;
      if (timeout != null) {
        await Future.delayed(timeout, () => null);
      }
      return ConnectionResponse.success;
    } else if (Platform.isAndroid) {
      await usbPrinter.close();
      this.printer.connected = false;
      if (timeout != null) {
        await Future.delayed(timeout, () => null);
      }
      return ConnectionResponse.success;
    }
    return ConnectionResponse.timeout;
  }

  @override
  Future<ConnectionResponse> writeBytes(List<int> data,
      {int? vendorId, int? productId}) async {
    if (Platform.isWindows) {
      try {
        await connect();

        // Inform the spooler the document is beginning.
        final dwJob = StartDocPrinter(hPrinter, 1, docInfo!);
        if (dwJob == 0) {
          ClosePrinter(hPrinter);
          return ConnectionResponse.printInProgress;
        }
        // Start a page.
        if (StartPagePrinter(hPrinter) == 0) {
          EndDocPrinter(hPrinter);
          ClosePrinter(hPrinter);
          return ConnectionResponse.printerNotSelected;
        }

        // Send the data to the printer.
        final lpData = data.toUint8();
        dwCount = data.length;
        if (WritePrinter(hPrinter, lpData, dwCount!, dwBytesWritten!) == 0) {
          EndPagePrinter(hPrinter);
          EndDocPrinter(hPrinter);
          ClosePrinter(hPrinter);
          return ConnectionResponse.printerNotWritable;
        }

        // End the page.
        if (EndPagePrinter(hPrinter) == 0) {
          EndDocPrinter(hPrinter);
          ClosePrinter(hPrinter);
        }

        // Inform the spooler that the document is ending.
        if (EndDocPrinter(hPrinter) == 0) {
          ClosePrinter(hPrinter);
        }

        // Check to see if correct number of bytes were written.
        if (dwBytesWritten!.value != dwCount) {}

        // Tidy up the printer handle.
        ClosePrinter(hPrinter);
        // await disconnect();

        return ConnectionResponse.success;
      } catch (e) {
        return ConnectionResponse.unknown;
      }
    } else if (Platform.isAndroid) {
      var res = await connect();
      if (res == ConnectionResponse.success) {
        var bytes = Uint8List.fromList(data);
        int max = 16384;

        /// maxChunk limit on android
        var datas = bytes.chunkBy(max);
        for (var data in datas) {
          await usbPrinter.write(Uint8List.fromList(data));
        }

        try {
          await usbPrinter.close();
          this.printer.connected = false;
        } catch (e) {
          return ConnectionResponse.unknown;
        }

        return ConnectionResponse.success;
      } else {
        return res;
      }
    }
    return ConnectionResponse.unsupport;
  }
}
