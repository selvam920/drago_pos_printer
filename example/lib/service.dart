import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pf;
import 'package:pdf/widgets.dart' as pw;
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:printing/printing.dart';
// import 'package:qr_flutter/qr_flutter.dart';
import 'dart:math' as math;

class ESCPrinterService {
  final Uint8List? receipt;
  List<int>? _bytes;

  var dpi;
  List<int>? get bytes => _bytes;
  int? _paperSizeWidthMM;
  int? _maxPerLine;
  CapabilityProfile? _profile;

  ESCPrinterService(this.receipt);

  Future<List<int>> getBytes({
    int paperSizeWidthMM = PaperSizeWidth.mm80,
    int maxPerLine = PaperSizeMaxPerLine.mm80,
    CapabilityProfile? profile,
    String name = "default",
  }) async {
    List<int> bytes = [];
    _profile = profile ?? (await CapabilityProfile.load(name: name));
    print(_profile!.name);
    _paperSizeWidthMM = paperSizeWidthMM;
    _maxPerLine = maxPerLine;
    assert(receipt != null);
    assert(_profile != null);
    EscGenerator generator =
        EscGenerator(_paperSizeWidthMM!, _maxPerLine!, _profile!);
    var decodeImage = img.decodeImage(receipt!);
    if (decodeImage == null) throw Exception('decoded image is null');
    final img.Image _resize =
        img.copyResize(decodeImage, width: _paperSizeWidthMM);

    String dir = (await getTemporaryDirectory()).path;
    String fullPath = '$dir/abc.png';
    print("local file full path ${fullPath}");
    File file = File(fullPath);

    await file.writeAsBytes(img.encodePng(decodeImage));

    // OpenFile.open(fullPath);

    bytes += generator.image(_resize);
    bytes += generator.feed(2);
    bytes += generator.cut();
    return bytes;
  }

  Future<img.Image?> generateLabel(int width, int height, int labelWidth,
      double horizontalGap, int column) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pf.PdfPageFormat(
            width * pf.PdfPageFormat.mm, height * pf.PdfPageFormat.mm),
        build: (pw.Context context) => pw.Row(children: [
          for (int i = 0; i < column; i++)
            pw.Expanded(
                child: pw.Center(
                    child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                  pw.SizedBox(height: 5),
                  pw.Text('Bodi ananatham department',
                      style: pw.TextStyle(fontSize: 6),
                      overflow: pw.TextOverflow.clip),
                  pw.SizedBox(height: 1),
                  //barcode
                  pw.BarcodeWidget(
                      width: 90,
                      height: 28,
                      data: '324324',
                      barcode: pw.Barcode.code39()),
                  //qr code
                  pw.Row(children: [
                    pw.Container(
                      width: 3,
                      child: pw.Transform.rotateBox(
                        angle: math.pi / 180,
                        child: pw.Text(
                          '13232',
                          style: pw.TextStyle(fontSize: 5),
                        ),
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
                      pw.Row(children: [
                        pw.Expanded(
                            child: pw.Text('Rate',
                                style: pw.TextStyle(fontSize: 6))),
                        pw.Expanded(
                            child: pw.Text('0.52',
                                style: pw.TextStyle(fontSize: 6))),
                      ]),
                      pw.Row(children: [
                        pw.Expanded(
                            child: pw.Text('MRP',
                                style: pw.TextStyle(fontSize: 6))),
                        pw.Expanded(
                            child: pw.Text('0.52',
                                style: pw.TextStyle(fontSize: 6))),
                      ]),
                      pw.Row(children: [
                        pw.Expanded(
                            child: pw.Text('Mfd',
                                style: pw.TextStyle(fontSize: 6))),
                        pw.Expanded(
                            child: pw.Text('02/20/23',
                                style: pw.TextStyle(fontSize: 6))),
                      ]),
                      pw.Row(children: [
                        pw.Expanded(
                            child: pw.Text('Expiry',
                                style: pw.TextStyle(fontSize: 6))),
                        pw.Expanded(
                            child: pw.Text('02/20/23',
                                style: pw.TextStyle(fontSize: 6))),
                      ]),
                    ])),
                    pw.SizedBox(width: 3),
                  ]),
                  pw.SizedBox(height: 1.5),
                  pw.Text('200g Horlicks Choclate flavor [iyj fdgdfgdf dfgdfg]',
                      style: pw.TextStyle(fontSize: 6)),
                ])))
        ]),
      ),
    );

    await for (var page in Printing.raster(await doc.save(), dpi: 203)) {
      return page.asImage();
    }
    return null;
  }

  Future<Uint8List> _generatePdf() async {
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

  Future<List<int>> getPdfBytes({
    int paperSizeWidthMM = PaperSizeMaxPerLine.mm80,
    int maxPerLine = PaperSizeMaxPerLine.mm80,
    CapabilityProfile? profile,
    String name = "default",
  }) async {
    List<int> bytes = [];
    _profile = profile ?? (await CapabilityProfile.load(name: name));
    print(_profile!.name);
    _paperSizeWidthMM = paperSizeWidthMM;
    _maxPerLine = maxPerLine;

    EscGenerator generator =
        EscGenerator(_paperSizeWidthMM!, _maxPerLine!, _profile!);

    await for (var page in Printing.raster(await _generatePdf(), dpi: 96)) {
      final image = page.asImage();
      bytes += generator.image(image);
      bytes += generator.reset();
      bytes += generator.cut();
    }
    return bytes;
  }

  Future<List<int>> getSamplePosBytes({
    int paperSizeWidthMM = PaperSizeMaxPerLine.mm80,
    int maxPerLine = PaperSizeMaxPerLine.mm80,
    CapabilityProfile? profile,
    String name = "default",
  }) async {
    List<int> bytes = [];
    _profile = profile ?? (await CapabilityProfile.load(name: name));
    print(_profile!.name);
    _paperSizeWidthMM = paperSizeWidthMM;
    _maxPerLine = maxPerLine;
    EscGenerator ticket =
        EscGenerator(_paperSizeWidthMM!, _maxPerLine!, _profile!);
    bytes += ticket.reset();
    //Print image
    // final ByteData data = await rootBundle.load('assets/logo.png');
    // final Uint8List imageBytes = data.buffer.asUint8List();
    // final img.Image? image = img.decodeImage(imageBytes);
    // if (image != null) {
    //   img.Image thumbnail = img.copyResize(image, width: 400);
    //   bytes += ticket.image(thumbnail);
    //   bytes += ticket.reset();
    // }

    // bytes += ticket.text(
    //     'Regular: aA bB cC dD eE fF gG hH iI jJ kK lL mM nN oO pP qQ rR sS tT uU vV wW xX yY zZ');
    // bytes += ticket.text('Special 1: ', styles: PosStyles(codeTable: 'CP1252'));
    // bytes += ticket.text('Special 2: blåbærgrød',
    //     styles: PosStyles(codeTable: 'CP1252'));

    // bytes += ticket.text('Bold text', styles: PosStyles(bold: true));
    // bytes += ticket.text('Reverse text', styles: PosStyles(reverse: true));
    // bytes += ticket.text('Underlined text',
    //     styles: PosStyles(underline: true), linesAfter: 1);
    // bytes += ticket.text('Align left', styles: PosStyles(align: PosAlign.left));
    // bytes +=
    //     ticket.text('Align center', styles: PosStyles(align: PosAlign.center));
    // bytes += ticket.text('Align right',
    //     styles: PosStyles(align: PosAlign.right), linesAfter: 1);

    // bytes += ticket.text('SKS DEPARTMENT STORE',
    //     styles: PosStyles(
    //       align: PosAlign.center,
    //       height: PosTextSize.size1,
    //       width: PosTextSize.size1,
    //     ));

    // bytes += ticket.text('889  Watson Lane',
    //     styles: PosStyles(align: PosAlign.center));
    // bytes += ticket.text('New Braunfels, TX',
    //     styles: PosStyles(align: PosAlign.center));
    // bytes += ticket.text('Tel: 830-221-1234',
    //     styles: PosStyles(align: PosAlign.center));
    // bytes +=
    //     ticket.text('Web: .com', styles: PosStyles(align: PosAlign.center));

    // bytes += ticket.hr();
    // bytes += ticket.row([
    //   PosColumn(text: 'Qty', width: 1),
    //   PosColumn(text: 'Item', width: 5),
    //   PosColumn(
    //       text: 'Price', width: 3, styles: PosStyles(align: PosAlign.right)),
    //   PosColumn(
    //       text: 'Total ', width: 3, styles: PosStyles(align: PosAlign.right)),
    // ]);
    // bytes += ticket.hr();

    // bytes += ticket.row([
    //   PosColumn(text: '2', width: 1),
    //   PosColumn(text: 'ONION RINGS ONION RINGS ONION', width: 5),
    //   PosColumn(
    //       text: '0.99', width: 3, styles: PosStyles(align: PosAlign.right)),
    //   PosColumn(
    //       text: '1.98', width: 3, styles: PosStyles(align: PosAlign.right)),
    // ]);
    // bytes += ticket.row([
    //   PosColumn(text: '1', width: 1),
    //   PosColumn(text: 'PIZZA', width: 7),
    //   PosColumn(
    //       text: '3.45', width: 2, styles: PosStyles(align: PosAlign.right)),
    //   PosColumn(
    //       text: '3.45', width: 2, styles: PosStyles(align: PosAlign.right)),
    // ]);
    // bytes += ticket.row([
    //   PosColumn(text: '1', width: 1),
    //   PosColumn(text: 'SPRING ROLLS', width: 7),
    //   PosColumn(
    //       text: '2.99', width: 2, styles: PosStyles(align: PosAlign.right)),
    //   PosColumn(
    //       text: '2.99', width: 2, styles: PosStyles(align: PosAlign.right)),
    // ]);
    // bytes += ticket.row([
    //   PosColumn(text: '3', width: 1),
    //   PosColumn(text: 'CRUNCHY STICKS', width: 7),
    //   PosColumn(
    //       text: '0.85', width: 2, styles: PosStyles(align: PosAlign.right)),
    //   PosColumn(
    //       text: '2.55', width: 2, styles: PosStyles(align: PosAlign.right)),
    // ]);
    // bytes += ticket.hr();

    // bytes += ticket.row([
    //   PosColumn(
    //       text: 'TOTAL',
    //       width: 6,
    //       styles: PosStyles(
    //         height: PosTextSize.size2,
    //         width: PosTextSize.size2,
    //       )),
    //   PosColumn(
    //       text: '\$10.97',
    //       width: 6,
    //       styles: PosStyles(
    //         align: PosAlign.right,
    //         height: PosTextSize.size2,
    //         width: PosTextSize.size2,
    //       )),
    // ]);

    // bytes += ticket.hr(ch: '=', linesAfter: 1);

    // bytes += ticket.row([
    //   PosColumn(
    //       text: 'CASH',
    //       width: 7,
    //       styles: PosStyles(align: PosAlign.right, width: PosTextSize.size2)),
    //   PosColumn(
    //       text: '\$15.00',
    //       width: 5,
    //       styles: PosStyles(align: PosAlign.right, width: PosTextSize.size2)),
    // ]);
    // bytes += ticket.row([
    //   PosColumn(
    //       text: 'CHANGE',
    //       width: 7,
    //       styles: PosStyles(align: PosAlign.right, width: PosTextSize.size2)),
    //   PosColumn(
    //       text: '\$4.03',
    //       width: 5,
    //       styles: PosStyles(align: PosAlign.right, width: PosTextSize.size2)),
    // ]);

    // bytes += ticket.feed(1);
    bytes += ticket.text('Thank you!',
        styles: PosStyles(align: PosAlign.center, bold: true));

    // final now = DateTime.now();
    // final formatter = DateFormat('MM/dd/yyyy H:m');
    // final String timestamp = formatter.format(now);
    // bytes += ticket.text(timestamp,
    //     styles: PosStyles(align: PosAlign.center), linesAfter: 2);

    //Print QR Code from image
    // try {
    //   const String qrData = 'example.com';
    //   const double qrSize = 100;
    //   final uiImg = await QrPainter(
    //     data: qrData,
    //     version: QrVersions.auto,
    //     gapless: false,
    //   ).toImageData(qrSize);
    //   final dir = await getTemporaryDirectory();
    //   final pathName = '${dir.path}/qr_tmp.png';
    //   final qrFile = File(pathName);
    //   final imgFile = await qrFile.writeAsBytes(uiImg!.buffer.asUint8List());
    //   final image = img.decodeImage(imgFile.readAsBytesSync());

    //   bytes += ticket.image(image!);
    // } catch (e) {
    //   print(e);
    // }

    // Print QR Code using native function
    // bytes += ticket.qrcode('example.com');

    bytes += ticket.feed(1);
    bytes += ticket.cut();

    return bytes;
  }
}
