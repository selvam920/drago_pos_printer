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
  Future connect({Duration? timeout = const Duration(seconds: 5)}) async {
    if (Platform.isWindows) {
      try {
        docInfo =
            calloc<DOC_INFO_1>()
              ..ref.pDocName = pDocName
              ..ref.pOutputFile = nullptr
              ..ref.pDatatype = pDataType;
        szPrinterName = printer.name!.toNativeUtf16();

        final phPrinter = calloc<HANDLE>();
        if (OpenPrinter(szPrinterName, phPrinter, nullptr) == FALSE) {
          return Future.error('Failed to open printer: ${printer.name}');
        }
        this.hPrinter = phPrinter.value;
      } catch (e) {
        return Future.error(e.toString());
      }
    } else if (Platform.isAndroid) {
      var usbDevice = await usbPrinter.connect(
        printer.vendorId!,
        printer.productId!,
      );
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
    if (Platform.isWindows) {
      await connect();

      // Inform the spooler the document is beginning.
      final dwJob = StartDocPrinter(hPrinter, 1, docInfo!);
      if (dwJob == 0) {
        ClosePrinter(hPrinter);
        return Future.error('StartDocPrinter failed');
      }
      // Start a page.
      if (StartPagePrinter(hPrinter) == 0) {
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
        return Future.error('StartPagePrinter failed');
      }

      // Send data to the printer in chunks to avoid buffer overflow.
      // Writing all data at once can cause some printers to paginate
      // (e.g., printing at A4 height) instead of continuous roll paper.
      const int chunkSize = 4096;
      int totalWritten = 0;
      final chunks = data.chunkBy(chunkSize);

      for (var chunk in chunks) {
        final lpData = chunk.toUint8();
        final chunkLen = chunk.length;

        final writeResult =
            WritePrinter(hPrinter, lpData, chunkLen, dwBytesWritten!);
        totalWritten += dwBytesWritten!.value;

        // Free the native memory after each chunk write.
        free(lpData);

        if (writeResult == 0) {
          EndPagePrinter(hPrinter);
          EndDocPrinter(hPrinter);
          ClosePrinter(hPrinter);
          return Future.error('WritePrinter failed after $totalWritten bytes');
        }
      }

      // End the page.
      if (EndPagePrinter(hPrinter) == 0) {
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
        return Future.error('EndPagePrinter failed');
      }

      // Inform the spooler that the document is ending.
      if (EndDocPrinter(hPrinter) == 0) {
        ClosePrinter(hPrinter);
        return Future.error('EndDocPrinter failed');
      }

      // Tidy up the printer handle.
      ClosePrinter(hPrinter);
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

  @override
  Future<void> pair(POSPrinter device) {
    // TODO: implement pair
    throw UnimplementedError();
  }

  @override
  Stream<POSPrinter> scan() async* {
    final results = await discover();
    for (final device in results) {
      yield device;
    }
  }
}
