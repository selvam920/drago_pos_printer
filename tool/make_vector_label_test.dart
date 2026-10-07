import 'dart:io';
import 'dart:ui' as ui;

import 'package:drago_pos_printer/utils/label_job.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Manual hardware check: 50 x 30 mm label drawn with Flutter (real Arial
/// from Windows, as the app renders) at 203 dpi, ESC/POS job to OUT_FILE.
/// TOP_MM sets the top offset.
void main() {
  testWidgets('make vector label', (tester) async {
    await tester.runAsync(() async {
      final font = File(r'C:\Windows\Fonts\arial.ttf').readAsBytesSync();
      final bold = File(r'C:\Windows\Fonts\arialbd.ttf').readAsBytesSync();
      await (FontLoader('Arial')
            ..addFont(Future.value(ByteData.sublistView(font)))
            ..addFont(Future.value(ByteData.sublistView(bold))))
          .load();

      const dpi = PrinterDpi.dpi203;
      final w = dpi.mmToDots(50), h = dpi.mmToDots(30);
      final dpm = dpi.dotsPerMm;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final black = Paint()..color = Colors.black;
      c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = Colors.white);
      c.drawRect(
          Rect.fromLTWH(dpm, dpm, w - 2 * dpm, h - 2 * dpm),
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);

      void text(String s, double x, double y, double pt, FontWeight wt) {
        // pt -> dots: 1 pt = 1/72 inch.
        final tp = TextPainter(
          text: TextSpan(
            text: s,
            style: TextStyle(
                fontFamily: 'Arial',
                fontSize: pt * dpi.value / 72,
                fontWeight: wt,
                color: Colors.black),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset(x, y));
      }

      text('LD0801 ESC/POS', 20, 16, 10, FontWeight.bold);
      text('Vector Arial 203 dpi  Rs.99.00', 20, 52, 7, FontWeight.normal);
      var x = 20.0;
      for (var i = 0; i < 40; i++) {
        final bar = (i % 3 + 1) * 2.0;
        if (i.isEven) c.drawRect(Rect.fromLTWH(x, 84, bar, 76), black);
        x += bar + 2;
      }
      text('Small 6pt text: 0123456789 ABCDEF', 20, 170, 6, FontWeight.normal);
      text('Bold 8pt', 20, 196, 8, FontWeight.bold);

      final picture = await rec.endRecording().toImage(w, h);
      final data = await picture.toByteData(format: ui.ImageByteFormat.rawRgba);
      final image = img.Image.fromBytes(
          width: w, height: h, bytes: data!.buffer, numChannels: 4);
      final top = double.tryParse(Platform.environment['TOP_MM'] ?? '') ?? 0;
      final job = LabelJob.build(image,
          language: Platform.environment['LANG_JOB'] == 'detong'
              ? LabelLanguage.detong
              : LabelLanguage.escPos,
          dpi: dpi,
          compression: LabelCompression.compressed,
          widthMm: 50,
          heightMm: 30,
          topOffsetMm: top);
      File(Platform.environment['OUT_FILE']!).writeAsBytesSync(job);
      File('${Platform.environment['OUT_FILE']}.png')
          .writeAsBytesSync(img.encodePng(image));
      // ignore: avoid_print
      print('${w}x$h dots, ${job.length} bytes, top $top mm');
    });
  });
}
