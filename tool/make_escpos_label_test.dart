import 'dart:io';

import 'package:drago_pos_printer/utils/label_job.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

/// Manual hardware check: writes a 50 x 30 mm @ 203 dpi ESC/POS label job to
/// OUT_FILE (border 1 mm in, text, fake barcode bars).
void main() {
  test('make label', () {
    const dpi = PrinterDpi.dpi203;
    final w = dpi.mmToDots(50), h = dpi.mmToDots(30);
    final img = Image(width: w, height: h);
    fill(img, color: ColorRgb8(255, 255, 255));
    final black = ColorRgb8(0, 0, 0);
    final m = dpi.mmToDots(1);
    drawRect(img, x1: m, y1: m, x2: w - m, y2: h - m, color: black, thickness: 3);
    drawString(img, 'LD0801 ESC/POS', font: arial24, x: 20, y: 20, color: black);
    drawString(img, '50 x 30 mm  203 dpi', font: arial14, x: 20, y: 56, color: black);
    var x = 20;
    for (var i = 0; i < 40; i++) {
      final bar = (i % 3) + 1;
      if (i.isEven) fillRect(img, x1: x, y1: 90, x2: x + bar * 2, y2: 170, color: black);
      x += bar * 2 + 2;
    }
    drawString(img, 'compressed + form feed', font: arial14, x: 20, y: 185, color: black);
    final job = LabelJob.build(
      img,
      language: LabelLanguage.escPos,
      dpi: dpi,
      compression: LabelCompression.compressed,
      widthMm: 50,
      heightMm: 30,
    );
    File(Platform.environment['OUT_FILE']!).writeAsBytesSync(job);
    // ignore: avoid_print
    print('${w}x$h dots, ${job.length} bytes, ends ${job.last}');
  });
}
