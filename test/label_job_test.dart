import 'dart:convert';

import 'package:drago_pos_printer/utils/label_job.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

/// 16 x 40 white image with a black bar on rows 10..11 and 30.
Image _sample() {
  final img = Image(width: 16, height: 40);
  fill(img, color: ColorRgb8(255, 255, 255));
  for (final y in [10, 11, 30]) {
    for (var x = 0; x < 16; x++) {
      img.setPixelRgb(x, y, 0, 0, 0);
    }
  }
  return img;
}

void main() {
  test('dpi converts mm to dots', () {
    expect(PrinterDpi.dpi203.mmToDots(50), 400);
    expect(PrinterDpi.dpi300.mmToDots(50), 591);
  });

  test('bitmap packs black as 1 and finds ink runs', () {
    final bmp = MonoBitmap.fromImage(_sample());
    expect(bmp.widthBytes, 2);
    expect(bmp.rows(const RowRun(10, 1)), [0xFF, 0xFF]);
    expect(bmp.rows(const RowRun(0, 1)), [0, 0]);
    final runs = bmp.inkRuns();
    expect(runs.map((r) => [r.start, r.length]), [
      [10, 2],
      [30, 1],
    ]);
  });

  test('TSPL inverts bits and compressed skips blank rows', () {
    final full = LabelJob.build(_sample(), language: LabelLanguage.tspl);
    final small = LabelJob.build(_sample(),
        language: LabelLanguage.tspl,
        compression: LabelCompression.compressed);
    final text = latin1.decode(full);
    expect(text, contains('SIZE 2 mm,5 mm'));
    expect(text, contains('BITMAP 0,0,2,40,0,'));
    expect(latin1.decode(small), contains('BITMAP 0,10,2,2,0,'));
    expect(latin1.decode(small), contains('BITMAP 0,30,2,1,0,'));
    expect(small.length, lessThan(full.length));
    // white row 0 inverted -> 0xFF in TSPL
    const header = 'BITMAP 0,0,2,40,0,';
    final dataAt = text.indexOf(header) + header.length;
    expect(full.sublist(dataAt, dataAt + 2), [0xFF, 0xFF]); // row 0 white
    expect(full.sublist(dataAt + 20, dataAt + 22), [0, 0]); // row 10 black
  });

  test('ESC/POS uses GS v 0 and feeds over blank bands', () {
    final tall = Image(width: 16, height: 300);
    fill(tall, color: ColorRgb8(255, 255, 255));
    tall.setPixelRgb(0, 280, 0, 0, 0);
    final full = LabelJob.build(tall, language: LabelLanguage.escPos);
    final small = LabelJob.build(tall,
        language: LabelLanguage.escPos,
        compression: LabelCompression.compressed);
    expect(full.sublist(2, 5), [0x1D, 0x76, 0x30]);
    // blank rows above the ink are fed, not sent: 280 = 255 + 25
    expect(small.sublist(2, 8), [0x1B, 0x4A, 255, 0x1B, 0x4A, 25]);
    // one raster block for the whole (inked part of the) label
    expect(_count(full, [0x1D, 0x76, 0x30]), 1);
    expect(small.length, lessThan(full.length));
    expect(full.sublist(full.length - 2), [0x1D, 0x0C]); // GS FF: next label
    final roll = LabelJob.build(tall,
        language: LabelLanguage.escPos, media: LabelMedia.continuous);
    expect(roll.sublist(roll.length - 3), [0x1B, 0x64, 0x03]);
    final shifted = LabelJob.build(tall,
        language: LabelLanguage.escPos, topOffsetMm: 1);
    expect(shifted.sublist(2, 5), [0x1B, 0x4A, 8]); // 1 mm = 8 dots
  });

  test('CPCL hex EG vs binary CG', () {
    final eg = latin1.decode(LabelJob.build(_sample(),
        language: LabelLanguage.cpcl, dpi: PrinterDpi.dpi300));
    expect(eg, startsWith('! 0 300 300 40 1\r\n'));
    expect(eg, contains('EG 2 40 0 0 '));
    expect(eg, endsWith('FORM\r\nPRINT\r\n'));
    final cg = latin1.decode(LabelJob.build(_sample(),
        language: LabelLanguage.cpcl,
        compression: LabelCompression.compressed));
    expect(cg, contains('CG 2 2 0 10 '));
    expect(cg, contains('CG 2 1 0 30 '));
  });
}

int _count(List<int> h, List<int> n) {
  var c = 0;
  for (var i = 0; i + n.length <= h.length; i++) {
    var ok = true;
    for (var j = 0; j < n.length; j++) {
      if (h[i + j] != n[j]) {
        ok = false;
        break;
      }
    }
    if (ok) c++;
  }
  return c;
}
