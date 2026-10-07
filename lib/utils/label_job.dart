import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart';

/// Command language the printer speaks.
/// Saved by index -- only append. [detong]: the DeTong raster protocol of
/// DP27 / LD0801 printers (`1F .. 88` commands, run-length rows) -- what the
/// maker's own driver sends; prints dense areas (barcodes) without the stalls
/// their ESC/POS raster mode shows.
enum LabelLanguage { tspl, escPos, cpcl, detong }

/// Printer head resolution. Use the one printed on the printer's label;
/// sending a 203 dpi image to a 300 dpi head prints it ~2/3 size.
enum PrinterDpi {
  dpi203(203),
  dpi300(300);

  const PrinterDpi(this.value);
  final int value;

  /// Dots per millimetre (8 at 203 dpi, ~11.8 at 300 dpi).
  double get dotsPerMm => value / 25.4;

  int mmToDots(double mm) => (mm * dotsPerMm).round();
}

/// How the bitmap is sent.
///
/// [none] sends every row. [compressed] uses tricks every printer of the
/// language accepts -- no firmware-specific modes:
/// * all languages: blank (white) row runs are skipped instead of sent,
/// * ESC/POS: skipped bands become a paper feed (`ESC J`),
/// * CPCL: binary `CG` instead of hex `EG` (half the bytes).
/// Labels are mostly white, so this is often 3-10x smaller -- which is what
/// makes Bluetooth label printing fast.
enum LabelCompression { none, compressed }

/// How the printer finds the start of each label. Wrong media is the usual
/// cause of "blank label and the roll keeps feeding": the printer hunts for
/// a gap that isn't there.
enum LabelMedia {
  /// Die-cut labels with a see-through gap between them (most rolls).
  gap,

  /// Black mark printed on the back of the liner.
  blackMark,

  /// Continuous roll / receipt paper -- no gap, cut by length.
  continuous,
}

/// Printer maintenance commands (TSPL).
class LabelCommands {
  LabelCommands._();

  /// Measures the gap / label length with the sensor (feeds a few labels).
  /// Run after loading a new roll.
  static List<int> tsplCalibrate({LabelMedia media = LabelMedia.gap}) =>
      latin1.encode(
        media == LabelMedia.blackMark ? 'BLINEDETECT\r\n' : 'GAPDETECT\r\n',
      );

  /// Prints the printer's own configuration page.
  static List<int> tsplSelfTest() => latin1.encode('SELFTEST\r\n');

  /// Text and a box with printer fonts only -- no bitmap. If this prints but
  /// image labels don't, the printer is fine and the image job is the issue;
  /// if this doesn't print either, check the language / media / size.
  static List<int> tsplTextTest({
    double widthMm = 50,
    double heightMm = 30,
    double gapMm = 2,
    LabelMedia media = LabelMedia.gap,
    PrinterDpi dpi = PrinterDpi.dpi203,
  }) {
    final w = dpi.mmToDots(widthMm), h = dpi.mmToDots(heightMm);
    return latin1.encode(
      [
        'SIZE ${LabelJob._mm(widthMm)} mm,${LabelJob._mm(heightMm)} mm',
        LabelJob._mediaLine(media, gapMm),
        'DIRECTION 1',
        'CLS',
        'BOX 8,8,${w - 8},${h - 8},3',
        'TEXT 24,24,"3",0,1,1,"TSPL TEXT TEST"',
        'TEXT 24,64,"2",0,1,1,"${LabelJob._mm(widthMm)}x${LabelJob._mm(heightMm)} mm ${dpi.value}dpi"',
        'PRINT 1,1',
        '',
      ].join('\r\n'),
    );
  }
}

/// Builds a complete print job for one label (or roll slice) from [image].
///
/// [image] should already be rendered at [dpi] -- its width in pixels is the
/// width in printer dots. Black/dark pixels print.
class LabelJob {
  LabelJob._();

  static List<int> build(
    Image image, {
    required LabelLanguage language,
    PrinterDpi dpi = PrinterDpi.dpi203,
    LabelCompression compression = LabelCompression.none,
    double? widthMm,
    double? heightMm,
    double gapMm = 2,
    LabelMedia media = LabelMedia.gap,
    int copies = 1,
    int threshold = 127,
    double topOffsetMm = 0,
  }) {
    final bitmap = MonoBitmap.fromImage(image, threshold: threshold);
    final wMm = widthMm ?? image.width / dpi.dotsPerMm;
    final hMm = heightMm ?? image.height / dpi.dotsPerMm;
    final compress = compression == LabelCompression.compressed;
    switch (language) {
      case LabelLanguage.tspl:
        return _tspl(bitmap, wMm, hMm, gapMm, media, copies, compress);
      case LabelLanguage.escPos:
        return _escPos(
          bitmap,
          media,
          copies,
          compress,
          dpi.mmToDots(topOffsetMm),
        );
      case LabelLanguage.detong:
        return _detong(bitmap, media, copies, dpi.mmToDots(topOffsetMm));
      case LabelLanguage.cpcl:
        return _cpcl(bitmap, dpi, media, copies, compress);
    }
  }

  // --------------------------------------------------------------- TSPL

  /// TSPL media line: GAP / BLINE, or GAP 0 for continuous paper.
  static String _mediaLine(LabelMedia media, double gapMm) {
    switch (media) {
      case LabelMedia.gap:
        return 'GAP ${_mm(gapMm)} mm,0 mm';
      case LabelMedia.blackMark:
        return 'BLINE ${_mm(gapMm)} mm,0 mm';
      case LabelMedia.continuous:
        return 'GAP 0 mm,0 mm';
    }
  }

  static List<int> _tspl(
    MonoBitmap bmp,
    double wMm,
    double hMm,
    double gapMm,
    LabelMedia media,
    int copies,
    bool compress,
  ) {
    final out = BytesBuilder();
    void line(String s) => out.add(latin1.encode('$s\r\n'));
    line('SIZE ${_mm(wMm)} mm,${_mm(hMm)} mm');
    line(_mediaLine(media, gapMm));
    line('DIRECTION 1');
    line('CLS');
    for (final run in compress ? bmp.inkRuns() : [RowRun(0, bmp.height)]) {
      // TSPL BITMAP: bit 1 = white, so invert our 1 = black rows.
      out.add(
        latin1.encode(
          'BITMAP 0,${run.start},${bmp.widthBytes},${run.length},0,',
        ),
      );
      out.add(bmp.rows(run, invert: true));
      out.add(latin1.encode('\r\n'));
    }
    line('PRINT 1,${copies < 1 ? 1 : copies}');
    return out.takeBytes();
  }

  // ------------------------------------------------------------- ESC/POS

  /// `GS v 0` raster in bands; blank bands become `ESC J` feeds.
  /// [topDots]: paper fed before the image. Raster label printers start
  /// printing a little before the label edge they detected; this moves the
  /// image down onto the label.
  static List<int> _escPos(
    MonoBitmap bmp,
    LabelMedia media,
    int copies,
    bool compress,
    int topDots,
  ) {
    final job = BytesBuilder()..add([0x1B, 0x40]); // ESC @
    void feed(int dots) {
      for (var left = dots; left > 0; left -= 255) {
        job.add([0x1B, 0x4A, left > 255 ? 255 : left]); // ESC J n
      }
    }

    feed(topDots);
    // Send the label as ONE raster image. Splitting it into bands makes
    // raster label printers print the first band, then stall while the next
    // command arrives (visible pause part-way down the label). Compression
    // only trims blank rows above / below the ink; only very tall jobs are
    // split, in big blocks.
    final wb = bmp.widthBytes;
    var start = 0, end = bmp.height;
    if (compress) {
      final runs = bmp.inkRuns(minGap: bmp.height);
      if (runs.isEmpty) {
        start = end = bmp.height; // nothing to print
      } else {
        start = runs.first.start;
        end = runs.last.start + runs.last.length;
      }
    }
    feed(start);
    const maxBlockBytes = 60 * 1024;
    final blockRows = (maxBlockBytes ~/ (wb == 0 ? 1 : wb)).clamp(1, 65535);
    for (var y = start; y < end; y += blockRows) {
      final h = (end - y) < blockRows ? end - y : blockRows;
      job.add([0x1D, 0x76, 0x30, 0x00, wb & 0xFF, wb >> 8, h & 0xFF, h >> 8]);
      job.add(bmp.rows(RowRun(y, h)));
    }
    // Blank rows below the ink: on labels GS FF skips them anyway; on
    // continuous paper keep the paper length.
    if (media == LabelMedia.continuous) feed(bmp.height - end);
    // Label printers that speak ESC/POS (raster-only, e.g. LD0801/DP27)
    // advance to the next gap/mark on a form feed; receipt paper just feeds.
    job.add(
      media == LabelMedia.continuous
          ? [0x1B, 0x64, 0x03] // ESC d 3 -- feed 3 lines
          // GS FF: feed to the next label's print start position (what the
          // printer makers' own drivers send). Plain FF only reaches the gap,
          // which leaves the next image starting on the gap edge.
          : [0x1D, 0x0C],
    );
    final one = job.takeBytes();
    return [for (var i = 0; i < (copies < 1 ? 1 : copies); i++) ...one];
  }

  // --------------------------------------------------------------- DeTong

  /// DeTong DP27 / LD0801 protocol, as captured from the maker's Windows
  /// driver: every command is `1F <op> ... 88`.
  /// * `1F 20 00` start, `1F 27 01 30` / `1F 25 02 7A 7A` driver defaults,
  ///   `1F 42 01 g` media (2 = gap),
  /// * `1F 22 01 n` skip n blank dot rows,
  /// * `1F 21 len [repeat-1] [byteOffset] [row bytes]` one row (bit 1 =
  ///   black) printed repeat times, starting at byteOffset,
  /// * `1F 28 00` end of label (feeds to the next one).
  static List<int> _detong(
    MonoBitmap bmp,
    LabelMedia media,
    int copies,
    int topDots,
  ) {
    final out = BytesBuilder();
    void cmd(List<int> body) =>
        out
          ..add([0x1F])
          ..add(body)
          ..add([0x88]);
    void skip(int dots) {
      for (var left = dots; left > 0; left -= 255) {
        cmd([0x22, 0x01, left > 255 ? 255 : left]);
      }
    }

    cmd([0x20, 0x00]);
    cmd([0x27, 0x01, 0x30]);
    cmd([0x25, 0x02, 0x7A, 0x7A]);
    cmd([
      0x42,
      0x01,
      media == LabelMedia.continuous
          ? 0x00
          : (media == LabelMedia.blackMark ? 0x01 : 0x02),
    ]);
    skip(topDots);

    final wb = bmp.widthBytes;
    var blank = 0;
    var y = 0;
    while (y < bmp.height) {
      final row = bmp.rows(RowRun(y, 1));
      var first = 0, last = wb - 1;
      while (first < wb && row[first] == 0) {
        first++;
      }
      if (first == wb) {
        blank++;
        y++;
        continue;
      }
      while (row[last] == 0) {
        last--;
      }
      skip(blank);
      blank = 0;
      // Identical rows below (barcode bars) are sent once with a repeat.
      var repeat = 1;
      while (repeat < 256 && y + repeat < bmp.height) {
        final next = bmp.rows(RowRun(y + repeat, 1));
        var same = true;
        for (var i = 0; i < wb; i++) {
          if (next[i] != row[i]) {
            same = false;
            break;
          }
        }
        if (!same) break;
        repeat++;
      }
      // len counts [repeat-1][offset][data]; max 255 -> split wide rows.
      for (var start = first; start <= last; start += 253) {
        final end = (start + 253 <= last + 1) ? start + 253 : last + 1;
        final data = row.sublist(start, end);
        cmd([0x21, data.length + 2, repeat - 1, start, ...data]);
      }
      y += repeat;
    }
    if (media == LabelMedia.continuous) skip(blank);
    cmd([0x28, 0x00]);
    final one = out.takeBytes();
    return [for (var i = 0; i < (copies < 1 ? 1 : copies); i++) ...one];
  }

  // ----------------------------------------------------------------- CPCL

  static List<int> _cpcl(
    MonoBitmap bmp,
    PrinterDpi dpi,
    LabelMedia media,
    int copies,
    bool compress,
  ) {
    final out = BytesBuilder();
    void line(String s) => out.add(latin1.encode('$s\r\n'));
    line(
      '! 0 ${dpi.value} ${dpi.value} ${bmp.height} '
      '${copies < 1 ? 1 : copies}',
    );
    final wb = bmp.widthBytes;
    for (final run in compress ? bmp.inkRuns() : [RowRun(0, bmp.height)]) {
      final data = bmp.rows(run); // CPCL: bit 1 = black
      if (compress) {
        out.add(latin1.encode('CG $wb ${run.length} 0 ${run.start} '));
        out.add(data);
        out.add(latin1.encode('\r\n'));
      } else {
        final hex = StringBuffer();
        for (final b in data) {
          hex.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
        }
        line('EG $wb ${run.length} 0 ${run.start} $hex');
      }
    }
    // FORM feeds to the next gap/mark; continuous paper just stops.
    if (media != LabelMedia.continuous) line('FORM');
    line('PRINT');
    return out.takeBytes();
  }

  /// One decimal, without a trailing ".0" (203 dpi isn't exactly 8/mm).
  static String _mm(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}

/// A run of [length] rows starting at row [start].
class RowRun {
  const RowRun(this.start, this.length);
  final int start;
  final int length;
}

/// 1-bit image, rows packed MSB first, bit 1 = black (ink).
class MonoBitmap {
  MonoBitmap._(this.width, this.height, this.widthBytes, this._data);

  final int width;
  final int height;
  final int widthBytes;
  final Uint8List _data;

  factory MonoBitmap.fromImage(Image image, {int threshold = 127}) {
    final w = image.width, h = image.height;
    final wb = (w + 7) >> 3;
    final data = Uint8List(wb * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        // Transparent counts as white (PNG backgrounds).
        final a = p.length > 3 ? p.aNormalized : 1.0;
        final lum = a == 0 ? 255 : getLuminanceRgb(p.r, p.g, p.b);
        if (lum <= threshold) {
          data[y * wb + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }
    return MonoBitmap._(w, h, wb, data);
  }

  bool _rowBlank(int y) {
    final o = y * widthBytes;
    for (var i = 0; i < widthBytes; i++) {
      if (_data[o + i] != 0) return false;
    }
    return true;
  }

  bool isBlank(RowRun run) {
    for (var y = run.start; y < run.start + run.length; y++) {
      if (!_rowBlank(y)) return false;
    }
    return true;
  }

  /// Runs of rows that contain ink. Short white gaps (< [minGap] rows) are
  /// kept inside a run -- each run costs a command header.
  List<RowRun> inkRuns({int minGap = 8}) {
    final runs = <RowRun>[];
    int? start;
    var lastInk = -1;
    for (var y = 0; y < height; y++) {
      if (_rowBlank(y)) continue;
      if (start != null && y - lastInk > minGap) {
        runs.add(RowRun(start, lastInk - start + 1));
        start = null;
      }
      start ??= y;
      lastInk = y;
    }
    if (start != null) runs.add(RowRun(start, lastInk - start + 1));
    return runs;
  }

  Uint8List rows(RowRun run, {bool invert = false}) {
    final from = run.start * widthBytes;
    final slice = Uint8List.sublistView(
      _data,
      from,
      from + run.length * widthBytes,
    );
    if (!invert) return Uint8List.fromList(slice);
    return Uint8List.fromList([for (final b in slice) (~b) & 0xFF]);
  }
}
