import 'dart:io';
import 'dart:ui' as ui;

import 'package:drago_pos_printer/utils/label_job.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Manual calibration label (50 x 30 mm @ 203 dpi): a line every 1 mm for
/// the first and last 6 mm, numbered by distance from the image edge. The
/// number sitting on the die-cut edge = how many mm the printer is off.
void main() {
  testWidgets('make ruler label', (tester) async {
    await tester.runAsync(() async {
      final font = File(r'C:\Windows\Fonts\arialbd.ttf').readAsBytesSync();
      await (FontLoader('ArialB')
            ..addFont(Future.value(ByteData.sublistView(font))))
          .load();
      const dpi = PrinterDpi.dpi203;
      final w = dpi.mmToDots(50), h = dpi.mmToDots(30);
      final dpm = dpi.dotsPerMm;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final ink = Paint()..color = Colors.black;
      c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = Colors.white);
      void label(String s, double x, double y) {
        (TextPainter(
          text: TextSpan(
              text: s,
              style: const TextStyle(
                  fontFamily: 'ArialB', fontSize: 18, color: Colors.black)),
          textDirection: TextDirection.ltr,
        )..layout())
            .paint(c, Offset(x, y));
      }

      for (var mm = 0; mm <= 6; mm++) {
        final top = mm * dpm, bottom = h - 1 - mm * dpm;
        final len = mm.isEven ? 140.0 : 90.0;
        c.drawRect(Rect.fromLTWH(0, top, len, 2), ink);
        c.drawRect(Rect.fromLTWH(0, bottom - 1, len, 2), ink);
        if (mm.isEven) {
          label('$mm', len + 6, top - 4);
          label('$mm', len + 6, bottom - 18);
        }
      }
      label('TOP', 250, 6);
      label('BOTTOM', 250, h - 30);
      label('mm from image edge', 160, h / 2 - 10);

      final picture = await rec.endRecording().toImage(w, h);
      final data = await picture.toByteData(format: ui.ImageByteFormat.rawRgba);
      final image = img.Image.fromBytes(
          width: w, height: h, bytes: data!.buffer, numChannels: 4);
      final job = LabelJob.build(image,
          language: LabelLanguage.escPos,
          dpi: dpi,
          compression: LabelCompression.none,
          widthMm: 50,
          heightMm: 30);
      File(Platform.environment['OUT_FILE']!).writeAsBytesSync(job);
      File('${Platform.environment['OUT_FILE']}.png')
          .writeAsBytesSync(img.encodePng(image));
    });
  });
}
