import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:drago_pos_printer/utils/esc_pos/commands.dart';
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
  Future connect({Duration? timeout = const Duration(seconds: 5)}) async {
    if (Platform.isWindows) {
      try {
        docInfo = calloc<DOC_INFO_1>()
          ..ref.pDocName = pDocName
          ..ref.pOutputFile = nullptr
          ..ref.pDatatype = pDataType;
        szPrinterName = printer.name!.toNativeUtf16();

        final phPrinter = calloc<HANDLE>();
        if (OpenPrinter(szPrinterName, phPrinter, nullptr) == FALSE) {
          return true;
        } else {
          this.hPrinter = phPrinter.value;
        }
      } catch (e) {
        return Future.error(e.toString());
      }
    } else if (Platform.isAndroid) {
      var usbDevice =
          await usbPrinter.connect(printer.vendorId!, printer.productId!);
      if (usbDevice == null) {
        return Future.error('Usb device is empty');
      }
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
      // Tidy up the printer handle.
      ClosePrinter(hPrinter);
      free(phPrinter!);
      free(pDocName);
      free(pDataType);
      free(dwBytesWritten!);
      free(docInfo!);
      free(szPrinterName);

      if (timeout != null) {
        await Future.delayed(timeout, () => null);
      }
      return true;
    } else if (Platform.isAndroid) {
      await usbPrinter.close();
      if (timeout != null) {
        await Future.delayed(timeout, () => null);
      }
    }
  }

  @override
  Future writeBytes(List<int> data, {int? vendorId, int? productId}) async {
    data += cCutFull.codeUnits;
    if (Platform.isWindows) {
      await connect();

      // Inform the spooler the document is beginning.
      final dwJob = StartDocPrinter(hPrinter, 1, docInfo!);
      if (dwJob == 0) {
        ClosePrinter(hPrinter);
      }
      // Start a page.
      if (StartPagePrinter(hPrinter) == 0) {
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
      }

      // Send the data to the printer.
      final lpData = data.toUint8();
      dwCount = data.length;
      if (WritePrinter(hPrinter, lpData, dwCount!, dwBytesWritten!) == 0) {
        EndPagePrinter(hPrinter);
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
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
    } else if (Platform.isAndroid) {
      try {
        await connect();

        var bytes = Uint8List.fromList(data);

        int max = 16384;

        /// maxChunk limit on android
        var datas = bytes.chunkBy(max);
        for (var data in datas) {
          await usbPrinter.write(Uint8List.fromList(data));
        }

        await usbPrinter.close();
      } catch (e) {
        return Future.error(e.toString());
      }
    }
  }
}
