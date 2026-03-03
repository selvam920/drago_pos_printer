import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as pf;
import 'package:pdf/widgets.dart' as pw;
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:printing/printing.dart';
import 'dart:math' as math;

/// Service that generates ESC/POS byte data for printing.
class ESCPrinterService {
  final Uint8List? receipt;

  ESCPrinterService(this.receipt);

  // ---------------------------------------------------------------------------
  // Image receipt → ESC/POS bytes
  // ---------------------------------------------------------------------------

  /// Convert an image [receipt] to ESC/POS bytes.
  Future<List<int>> getBytes({
    int paperSizeWidthMM = PaperSizeWidth.mm80,
    int maxPerLine = PaperSizeMaxPerLine.mm80,
    CapabilityProfile? profile,
    String name = 'default',
  }) async {
    final p = profile ?? await CapabilityProfile.load(name: name);
    final generator = EscGenerator(paperSizeWidthMM, maxPerLine, p);

    assert(receipt != null, 'receipt bytes must not be null');
    final decoded = img.decodeImage(receipt!);
    if (decoded == null) throw Exception('Failed to decode image');

    final resized = img.copyResize(decoded, width: paperSizeWidthMM);

    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.image(resized);
    bytes += generator.feed(2);
    bytes += generator.cut();
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // PDF receipt → ESC/POS bytes
  // ---------------------------------------------------------------------------

  Future<Uint8List> _generateSamplePdf() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pf.PdfPageFormat.roll57,
        build: (pw.Context context) => pw.SizedBox(
          height: 10 * pf.PdfPageFormat.mm,
          child: pw.Center(
            child: pw.Text('Hello World', style: pw.TextStyle(fontSize: 20)),
          ),
        ),
      ),
    );
    return doc.save();
  }

  /// Rasterize a sample PDF and convert to ESC/POS bytes.
  Future<List<int>> getPdfBytes({
    int paperSizeWidthMM = PaperSizeWidth.mm80,
    int maxPerLine = PaperSizeMaxPerLine.mm80,
    CapabilityProfile? profile,
    String name = 'default',
  }) async {
    final p = profile ?? await CapabilityProfile.load(name: name);
    final generator = EscGenerator(paperSizeWidthMM, maxPerLine, p);

    List<int> bytes = [];
    await for (var page
        in Printing.raster(await _generateSamplePdf(), dpi: 96)) {
      final image = page.asImage();
      bytes += generator.image(image);
      bytes += generator.reset();
      bytes += generator.cut();
    }
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // TSPL label image generation
  // ---------------------------------------------------------------------------

  /// Generate a sample label image for TSPL printers.
  Future<img.Image?> generateLabel(
    int width,
    int height,
    int labelWidth,
    double horizontalGap,
    int column,
  ) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pf.PdfPageFormat(
            width * pf.PdfPageFormat.mm, height * pf.PdfPageFormat.mm),
        build: (pw.Context context) => pw.Row(
          children: [
            for (int i = 0; i < column; i++)
              pw.Expanded(
                child: pw.Center(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.SizedBox(height: 5),
                      pw.Text('Sample Department Store',
                          style: pw.TextStyle(fontSize: 6),
                          overflow: pw.TextOverflow.clip),
                      pw.SizedBox(height: 1),
                      pw.BarcodeWidget(
                          width: 90,
                          height: 28,
                          data: '324324',
                          barcode: pw.Barcode.code39()),
                      pw.Row(children: [
                        pw.Container(
                          width: 3,
                          child: pw.Transform.rotateBox(
                            angle: math.pi / 180,
                            child: pw.Text('13232',
                                style: pw.TextStyle(fontSize: 5)),
                          ),
                        ),
                        pw.SizedBox(width: 2),
                        pw.BarcodeWidget(
                            width: 26,
                            height: 26,
                            data: '324324',
                            barcode: pw.Barcode.qrCode()),
                        pw.SizedBox(width: 5),
                        pw.Expanded(
                          child: pw.Column(children: [
                            _labelRow('Rate', '0.52'),
                            _labelRow('MRP', '0.52'),
                            _labelRow('Mfd', '02/20/23'),
                            _labelRow('Expiry', '02/20/23'),
                          ]),
                        ),
                        pw.SizedBox(width: 3),
                      ]),
                      pw.SizedBox(height: 1.5),
                      pw.Text('200g Horlicks Chocolate Flavor',
                          style: pw.TextStyle(fontSize: 6)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    await for (var page in Printing.raster(await doc.save(), dpi: 203)) {
      return page.asImage();
    }
    return null;
  }

  static pw.Widget _labelRow(String label, String value) {
    return pw.Row(children: [
      pw.Expanded(
          child: pw.Text(label, style: pw.TextStyle(fontSize: 6))),
      pw.Expanded(
          child: pw.Text(value, style: pw.TextStyle(fontSize: 6))),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Sample ESC/POS text receipt (no image needed)
  // ---------------------------------------------------------------------------

  /// Generate a sample POS receipt using ESC/POS text commands.
  ///
  /// This demonstrates text, rows, styles, QR codes, and cut.
  Future<List<int>> getSamplePosBytes({
    int paperSizeWidthMM = PaperSizeWidth.mm80,
    int maxPerLine = PaperSizeMaxPerLine.mm80,
    CapabilityProfile? profile,
    String name = 'default',
  }) async {
    final p = profile ?? await CapabilityProfile.load(name: name);
    final gen = EscGenerator(paperSizeWidthMM, maxPerLine, p);

    List<int> bytes = [];
    bytes += gen.reset();

    // -- Header --
    bytes += gen.text('DRAGO POS PRINTER',
        styles: PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ));
    bytes += gen.text('Sample Receipt',
        styles: PosStyles(align: PosAlign.center));
    bytes += gen.text('123 Main Street',
        styles: PosStyles(align: PosAlign.center));
    bytes += gen.text('Tel: 555-0100',
        styles: PosStyles(align: PosAlign.center), linesAfter: 0);

    bytes += gen.hr();

    // -- Items --
    bytes += gen.row([
      PosColumn(text: 'Qty', width: 1, styles: PosStyles(bold: true)),
      PosColumn(text: 'Item', width: 5, styles: PosStyles(bold: true)),
      PosColumn(
          text: 'Price',
          width: 3,
          styles: PosStyles(align: PosAlign.right, bold: true)),
      PosColumn(
          text: 'Total',
          width: 3,
          styles: PosStyles(align: PosAlign.right, bold: true)),
    ]);

    bytes += gen.hr();

    bytes += gen.row([
      PosColumn(text: '2', width: 1),
      PosColumn(text: 'Cappuccino', width: 5),
      PosColumn(
          text: '3.50', width: 3, styles: PosStyles(align: PosAlign.right)),
      PosColumn(
          text: '7.00', width: 3, styles: PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.row([
      PosColumn(text: '1', width: 1),
      PosColumn(text: 'Croissant', width: 5),
      PosColumn(
          text: '2.50', width: 3, styles: PosStyles(align: PosAlign.right)),
      PosColumn(
          text: '2.50', width: 3, styles: PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.row([
      PosColumn(text: '3', width: 1),
      PosColumn(text: 'Espresso', width: 5),
      PosColumn(
          text: '2.00', width: 3, styles: PosStyles(align: PosAlign.right)),
      PosColumn(
          text: '6.00', width: 3, styles: PosStyles(align: PosAlign.right)),
    ]);

    bytes += gen.hr();

    // -- Totals --
    bytes += gen.row([
      PosColumn(
          text: 'TOTAL',
          width: 6,
          styles: PosStyles(
              height: PosTextSize.size2,
              width: PosTextSize.size2,
              bold: true)),
      PosColumn(
          text: '\$15.50',
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
            bold: true,
          )),
    ]);

    bytes += gen.hr(ch: '=', linesAfter: 0);

    bytes += gen.row([
      PosColumn(
          text: 'Cash',
          width: 7,
          styles: PosStyles(align: PosAlign.right)),
      PosColumn(
          text: '\$20.00',
          width: 5,
          styles: PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.row([
      PosColumn(
          text: 'Change',
          width: 7,
          styles: PosStyles(align: PosAlign.right)),
      PosColumn(
          text: '\$4.50',
          width: 5,
          styles: PosStyles(align: PosAlign.right)),
    ]);

    bytes += gen.feed(1);
    bytes += gen.text('Thank you for your purchase!',
        styles: PosStyles(align: PosAlign.center, bold: true));
    bytes += gen.text('drago-pos-printer',
        styles: PosStyles(align: PosAlign.center), linesAfter: 0);

    bytes += gen.feed(1);
    bytes += gen.cut();

    return bytes;
  }
}
