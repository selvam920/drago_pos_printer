import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as pf;
import 'package:pdf/widgets.dart' as pw;
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:printing/printing.dart';
import 'dart:math' as math;

/// Barcode / QR symbologies the example can print.
enum CodeType {
  qr('QR code'),
  code128('Code 128'),
  ean13('EAN-13'),
  code39('Code 39');

  const CodeType(this.title);
  final String title;
}

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
    int column, {
    double dpi = 203,
  }) async {
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

    await for (var page in Printing.raster(await doc.save(), dpi: dpi)) {
      return page.asImage();
    }
    return null;
  }

  /// One sample label in [language], rendered at the printer's [dpi] so one
  /// image pixel = one printer dot.
  Future<List<int>> getLabelBytes({
    required LabelLanguage language,
    PrinterDpi dpi = PrinterDpi.dpi203,
    LabelCompression compression = LabelCompression.compressed,
    double widthMm = 50,
    double heightMm = 25,
    double gapMm = 2,
    LabelMedia media = LabelMedia.gap,
  }) async {
    final image = await renderSampleLabel(widthMm, heightMm, dpi);
    return LabelJob.build(
      image,
      language: language,
      dpi: dpi,
      compression: compression,
      widthMm: widthMm,
      heightMm: heightMm,
      gapMm: gapMm,
      media: media,
    );
  }

  /// A test label that fits any size: a border 1 mm inside the edge (shows
  /// alignment / gap problems at a glance), title, barcode, QR and the size +
  /// dpi it was made for, all scaled to the label. Rendered at [dpi] so one
  /// pixel = one printer dot.
  Future<img.Image> renderSampleLabel(
      double widthMm, double heightMm, PrinterDpi dpi) async {
    final mm = pf.PdfPageFormat.mm;
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: pf.PdfPageFormat(widthMm * mm, heightMm * mm),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Container(
        margin: pw.EdgeInsets.all(1 * mm),
        padding: pw.EdgeInsets.all(1 * mm),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
        child: pw.FittedBox(
          fit: pw.BoxFit.contain,
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text('SAMPLE LABEL',
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Item 200g  MRP 99.00',
                      style: const pw.TextStyle(fontSize: 7)),
                  pw.SizedBox(height: 2),
                  pw.BarcodeWidget(
                    width: 110,
                    height: 30,
                    data: '8901234567890',
                    barcode: pw.Barcode.code128(),
                    textStyle: const pw.TextStyle(fontSize: 6),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                      '${_fmt(widthMm)} x ${_fmt(heightMm)} mm  '
                      '${dpi.value} dpi',
                      style: const pw.TextStyle(fontSize: 6)),
                ],
              ),
              pw.SizedBox(width: 6),
              pw.BarcodeWidget(
                width: 40,
                height: 40,
                data: 'drago-pos-printer',
                barcode: pw.Barcode.qrCode(),
              ),
            ],
          ),
        ),
      ),
    ));
    await for (final page
        in Printing.raster(await doc.save(), dpi: dpi.value.toDouble())) {
      return page.asImage();
    }
    throw Exception('Failed to render label');
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// Receipt printer self test: paper width ruler, alignment, styles, text
  /// sizes, symbols, barcode, QR and cut -- shows at a glance whether the
  /// paper width / chars-per-line / profile settings match the printer.
  Future<List<int>> getReceiptTestBytes({
    int paperSizeWidthMM = PaperSizeWidth.mm80,
    int maxPerLine = PaperSizeMaxPerLine.mm80,
    CapabilityProfile? profile,
    String name = 'default',
  }) async {
    final p = profile ?? await CapabilityProfile.load(name: name);
    final gen = EscGenerator(paperSizeWidthMM, maxPerLine, p);
    const center = PosStyles(align: PosAlign.center);
    final b = <int>[];

    b.addAll(gen.reset());
    b.addAll(gen.text('PRINTER TEST',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        )));
    final now = DateTime.now();
    b.addAll(gen.text(
        '${now.day}/${now.month}/${now.year} '
        '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
        styles: center));
    b.addAll(gen.text('Width $paperSizeWidthMM dots, $maxPerLine chars/line',
        styles: center));
    b.addAll(gen.text('Profile: $name', styles: center, linesAfter: 1));

    // Ruler: must exactly fill one line. Wraps = chars/line too high,
    // short = too low.
    b.addAll(gen.text('Ruler (should fill one line):'));
    b.addAll(
        gen.text(List.generate(maxPerLine, (i) => '${(i + 1) % 10}').join()));
    b.addAll(gen.hr());

    b.addAll(gen.text('Left'));
    b.addAll(gen.text('Center', styles: center));
    b.addAll(gen.text('Right', styles: const PosStyles(align: PosAlign.right)));
    b.addAll(gen.hr());

    b.addAll(gen.text('Bold', styles: const PosStyles(bold: true)));
    b.addAll(gen.text('Underline', styles: const PosStyles(underline: true)));
    b.addAll(gen.text(' Reverse ', styles: const PosStyles(reverse: true)));
    b.addAll(gen.text('Size 2x',
        styles: const PosStyles(
            height: PosTextSize.size2, width: PosTextSize.size2)));
    b.addAll(gen.text('Size 3x',
        styles: const PosStyles(
            height: PosTextSize.size3, width: PosTextSize.size3)));
    b.addAll(gen.hr());

    b.addAll(gen.text('0123456789 ABCDEFGHIJKLM abcdefghijklm'));
    b.addAll(gen.text(r'!@#$%^&*()_+-=[]{};:,./<>?'));
    b.addAll(gen.row([
      PosColumn(text: 'Item', width: 6),
      PosColumn(
          text: 'Qty',
          width: 2,
          styles: const PosStyles(align: PosAlign.right)),
      PosColumn(
          text: 'Amount',
          width: 4,
          styles: const PosStyles(align: PosAlign.right)),
    ]));
    b.addAll(gen.hr(linesAfter: 1));

    b.addAll(gen.text('CODE128', styles: center));
    b.addAll(gen.barcode(Barcode.code128('{B12345678'.split(''))));
    b.addAll(gen.feed(1));
    b.addAll(gen.text('QR', styles: center));
    b.addAll(gen.qrcode('drago-pos-printer'));
    b.addAll(gen.feed(1));
    b.addAll(gen.text('-- end of test --', styles: center));
    b.addAll(gen.cut());
    return b;
  }

  // ---------------------------------------------------------------------------
  // Barcode / QR
  // ---------------------------------------------------------------------------

  static pw.Barcode _pdfCode(CodeType type) => switch (type) {
        CodeType.qr => pw.Barcode.qrCode(),
        CodeType.code128 => pw.Barcode.code128(),
        CodeType.ean13 => pw.Barcode.ean13(),
        CodeType.code39 => pw.Barcode.code39(),
      };

  /// Throws a readable error when [data] can't be encoded as [type].
  static void validateCode(CodeType type, String data) {
    if (data.isEmpty) throw Exception('Enter the code data');
    _pdfCode(type).verify(data);
  }

  /// One code as a white image [widthDots] wide, with the data printed
  /// under 1D codes. Works on every printer (it's just a picture).
  Future<img.Image> renderCode(
    CodeType type,
    String data, {
    required double widthMm,
    required double heightMm,
    PrinterDpi dpi = PrinterDpi.dpi203,
    String? caption,
  }) async {
    validateCode(type, data);
    final mm = pf.PdfPageFormat.mm;
    final square = type == CodeType.qr;
    final doc = pw.Document()
      ..addPage(pw.Page(
        pageFormat: pf.PdfPageFormat(widthMm * mm, heightMm * mm),
        margin: pw.EdgeInsets.all(2 * mm),
        build: (_) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            if (caption != null && caption.isNotEmpty)
              pw.Padding(
                padding: pw.EdgeInsets.only(bottom: 1 * mm),
                child: pw.Text(caption,
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
            pw.Expanded(
              child: pw.Center(
                child: pw.AspectRatio(
                  aspectRatio: square ? 1 : 2.4,
                  child: pw.BarcodeWidget(
                    barcode: _pdfCode(type),
                    data: data,
                    drawText: !square,
                    textStyle: const pw.TextStyle(fontSize: 7),
                  ),
                ),
              ),
            ),
          ],
        ),
      ));
    await for (final page
        in Printing.raster(await doc.save(), dpi: dpi.value.toDouble())) {
      return page.asImage();
    }
    throw Exception('Failed to render code');
  }

  /// Receipt with the code: native ESC/POS barcode / QR commands, or (with
  /// [asImage]) the code drawn as a raster image for printers that only
  /// print images.
  Future<List<int>> getReceiptCodeBytes({
    required CodeType type,
    required String data,
    required bool asImage,
    int paperSizeWidthMM = PaperSizeWidth.mm80,
    int maxPerLine = PaperSizeMaxPerLine.mm80,
    CapabilityProfile? profile,
    String name = 'default',
  }) async {
    validateCode(type, data);
    final p = profile ?? await CapabilityProfile.load(name: name);
    final gen = EscGenerator(paperSizeWidthMM, maxPerLine, p);
    const center = PosStyles(align: PosAlign.center, bold: true);
    final b = <int>[...gen.reset()];
    b.addAll(gen.text('${type.title}: $data', styles: center, linesAfter: 1));
    if (asImage) {
      final widthMm = paperSizeWidthMM / 8; // printer dots -> mm at 203 dpi
      final image = await renderCode(type, data,
          widthMm: widthMm, heightMm: type == CodeType.qr ? widthMm : 25);
      b.addAll(gen.imageRaster(image));
    } else {
      switch (type) {
        case CodeType.qr:
          b.addAll(gen.qrcode(data, size: QRSize.Size6));
          break;
        case CodeType.code128:
          b.addAll(
              gen.barcode(Barcode.code128('{B$data'.split('')), height: 80));
          break;
        case CodeType.ean13:
          final digits = data.length == 13 ? data.substring(0, 12) : data;
          b.addAll(gen.barcode(
              Barcode.ean13(digits.split('').map(int.parse).toList()),
              height: 80));
          break;
        case CodeType.code39:
          b.addAll(gen.barcode(Barcode.code39(data.split('')), height: 80));
          break;
      }
    }
    b.addAll(gen.feed(2));
    b.addAll(gen.cut());
    return b;
  }

  /// A label that is just the code (plus an optional caption), sized to the
  /// label and sent in the label settings' language.
  Future<List<int>> getCodeLabelBytes({
    required CodeType type,
    required String data,
    String? caption,
    required LabelLanguage language,
    PrinterDpi dpi = PrinterDpi.dpi203,
    LabelCompression compression = LabelCompression.compressed,
    double widthMm = 50,
    double heightMm = 25,
    double gapMm = 2,
    LabelMedia media = LabelMedia.gap,
  }) async {
    final image = await renderCode(type, data,
        widthMm: widthMm, heightMm: heightMm, dpi: dpi, caption: caption);
    return LabelJob.build(
      image,
      language: language,
      dpi: dpi,
      compression: compression,
      widthMm: widthMm,
      heightMm: heightMm,
      gapMm: gapMm,
      media: media,
    );
  }

  static pw.Widget _labelRow(String label, String value) {
    return pw.Row(children: [
      pw.Expanded(child: pw.Text(label, style: pw.TextStyle(fontSize: 6))),
      pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 6))),
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
    bytes +=
        gen.text('Sample Receipt', styles: PosStyles(align: PosAlign.center));
    bytes +=
        gen.text('123 Main Street', styles: PosStyles(align: PosAlign.center));
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
              height: PosTextSize.size2, width: PosTextSize.size2, bold: true)),
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
          text: 'Cash', width: 7, styles: PosStyles(align: PosAlign.right)),
      PosColumn(
          text: '\$20.00', width: 5, styles: PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.row([
      PosColumn(
          text: 'Change', width: 7, styles: PosStyles(align: PosAlign.right)),
      PosColumn(
          text: '\$4.50', width: 5, styles: PosStyles(align: PosAlign.right)),
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
