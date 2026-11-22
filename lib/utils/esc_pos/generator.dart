import 'dart:convert';
import 'dart:typed_data' show Uint8List;
import 'package:flutter/services.dart';
import 'package:hex/hex.dart';
import 'package:image/image.dart';
import 'package:gbk_codec/gbk_codec.dart';
import '../../drago_pos_printer.dart';
import 'commands.dart';

class EscGenerator {
  EscGenerator(
    this.paperWidthMM,
    this.charPerLine,
    this._profile, {
    this.spaceBetweenRows = 5,
    this.codec = latin1,
    this.fontTwoCharPerLine = 0,
  });

  // Ticket config
  int paperWidthMM;
  int charPerLine;
  int fontTwoCharPerLine;

  CapabilityProfile _profile;
  int? _maxCharsPerLine;
  // Global styles
  String? _codeTable;
  PosFontType? _font;
  // Current styles
  PosStyles _styles = PosStyles();
  final Codec codec;
  int spaceBetweenRows;

  // ************************ Internal helpers ************************
  int _getMaxCharsPerLine(PosFontType? font) {
    if (fontTwoCharPerLine == 0) fontTwoCharPerLine = charPerLine;
    return (font == null || font == PosFontType.fontA)
        ? charPerLine
        : fontTwoCharPerLine;
  }

  // charWidth = default width * text size multiplier
  double _getCharWidth(PosStyles styles, {int? maxCharsPerLine}) {
    int charsPerLine = _getCharsPerLine(styles, maxCharsPerLine);
    double charWidth = (paperWidthMM / charsPerLine) * styles.width.value;
    return charWidth;
  }

  double _colIndToPosition(int colInd) {
    final int width = paperWidthMM;
    return colInd == 0 ? 0 : (width * colInd / 12 - 1);
  }

  int _getCharsPerLine(PosStyles styles, int? maxCharsPerLine) {
    int charsPerLine;
    if (maxCharsPerLine != null) {
      charsPerLine = maxCharsPerLine;
    } else {
      if (styles.fontType != null) {
        charsPerLine = _getMaxCharsPerLine(styles.fontType);
      } else {
        charsPerLine =
            _maxCharsPerLine ?? _getMaxCharsPerLine(_styles.fontType);
      }
    }
    return charsPerLine;
  }

  Uint8List _encode(String text, {bool isKanji = false}) {
    // replace some non-ascii characters
    text = text
        .replaceAll("’", "'")
        .replaceAll("´", "'")
        .replaceAll("»", '"')
        .replaceAll(" ", ' ')
        .replaceAll("•", '.');
    if (!isKanji) {
      return codec.encode(text);
    } else {
      return Uint8List.fromList(gbk_bytes.encode(text));
    }
  }

  List _getLexemes(String text) {
    final List<String> lexemes = [];
    final List<bool> isLexemeChinese = [];
    int start = 0;
    int end = 0;
    bool curLexemeChinese = _isChinese(text[0]);
    for (var i = 1; i < text.length; ++i) {
      if (curLexemeChinese == _isChinese(text[i])) {
        end += 1;
      } else {
        lexemes.add(text.substring(start, end + 1));
        isLexemeChinese.add(curLexemeChinese);
        start = i;
        end = i;
        curLexemeChinese = !curLexemeChinese;
      }
    }
    lexemes.add(text.substring(start, end + 1));
    isLexemeChinese.add(curLexemeChinese);

    return <dynamic>[lexemes, isLexemeChinese];
  }

  /// Break text into chinese/non-chinese lexemes
  bool _isChinese(String ch) {
    return ch.codeUnitAt(0) > 255;
  }

  /// Generate multiple bytes for a number: In lower and higher parts, or more parts as needed.
  ///
  /// [value] Input number
  /// [bytesNb] The number of bytes to output (1 - 4)
  List<int> _intLowHigh(int value, int bytesNb) {
    final dynamic maxInput = 256 << (bytesNb * 8) - 1;

    if (bytesNb < 1 || bytesNb > 4) {
      throw Exception('Can only output 1-4 bytes');
    }
    if (value < 0 || value > maxInput) {
      throw Exception(
        'Number is too large. Can only output up to $maxInput in $bytesNb bytes',
      );
    }

    final List<int> res = <int>[];
    int buf = value;
    for (int i = 0; i < bytesNb; ++i) {
      res.add(buf % 256);
      buf = buf ~/ 256;
    }
    return res;
  }

  /// Image rasterization: one pass over the RGBA bytes straight into the
  /// packed 1-bit rows (a pixel darker than mid grey prints). The old way
  /// copied, greyscaled and inverted the whole image, then grew a list one
  /// pixel at a time -- seconds on a long receipt on a cheap tablet.
  /// True when the RGBA pixel at [i] prints a dot: darker than mid grey
  /// once laid over white paper. The alpha counts -- Android renders a PDF
  /// onto a transparent bitmap, and reading only the colour printed that
  /// clear background solid black.
  static bool _isInk(Uint8List rgba, int i) {
    // Same luminance weights as image's grayscale().
    final int lum =
        (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
    return (255 - lum) * rgba[i + 3] > 127 * 255;
  }

  List<int> _toRasterFormat(Image imgSrc) {
    final Image image =
        imgSrc.format == Format.uint8 && imgSrc.numChannels == 4
            ? imgSrc
            : imgSrc.convert(format: Format.uint8, numChannels: 4);
    final int widthPx = image.width;
    final int heightPx = image.height;
    final int widthBytes = (widthPx + 7) >> 3;
    final Uint8List rgba = image.getBytes(order: ChannelOrder.rgba);
    final Uint8List out = Uint8List(widthBytes * heightPx);
    var src = 0;
    for (var y = 0; y < heightPx; y++) {
      final row = y * widthBytes;
      for (var x = 0; x < widthPx; x++, src += 4) {
        if (_isInk(rgba, src)) out[row + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    return out;
  }

  // ************************ (end) Internal helpers  ************************

  //**************************** Public command generators ************************
  /// Clear the buffer and reset text styles.
  ///
  /// Sends ESC @ to initialize the printer, which returns it to
  /// standard (continuous) mode — the default for roll paper printers.
  /// ESC @ already cancels page mode on compliant printers.
  List<int> reset() {
    List<int> bytes = [];
    bytes += cInit.codeUnits; // ESC @ — initialize / cancel page mode
    _styles = PosStyles();
    bytes += setGlobalCodeTable(_codeTable);
    bytes += setGlobalFont(_font);
    return bytes;
  }

  /// Explicitly set continuous roll paper mode.
  ///
  /// Call this after [reset] if your printer still prints with a fixed
  /// page height (e.g. A4). This sends CAN (0x18) to abort any active
  /// page mode data, then ESC @ to re-initialize, ensuring continuous
  /// roll paper printing with no fixed page length.
  List<int> setRollPaperMode() {
    List<int> bytes = [];
    // CAN (0x18) — cancel data in page mode without printing / advancing.
    bytes += [0x18];
    // ESC @ — re-initialize to standard (continuous) mode.
    bytes += cInit.codeUnits;
    _styles = PosStyles();
    return bytes;
  }

  /// Set global code table which will be used instead of the default printer's code table
  /// (even after resetting)
  List<int> setGlobalCodeTable(String? codeTable) {
    List<int> bytes = [];
    _codeTable = codeTable;
    if (codeTable != null) {
      bytes += Uint8List.fromList(
        List.from(cCodeTable.codeUnits)..add(_profile.getCodePageId(codeTable)),
      );
      _styles = _styles.copyWith(codeTable: codeTable);
    }
    return bytes;
  }

  /// Set global font which will be used instead of the default printer's font
  /// (even after resetting)
  List<int> setGlobalFont(PosFontType? font, {int? maxCharsPerLine}) {
    List<int> bytes = [];
    _font = font;
    if (font != null) {
      _maxCharsPerLine = maxCharsPerLine ?? _getMaxCharsPerLine(font);
      bytes += font == PosFontType.fontB ? cFontB.codeUnits : cFontA.codeUnits;
      _styles = _styles.copyWith(fontType: font);
    }
    return bytes;
  }

  List<int> setStyles(PosStyles styles, {bool isKanji = false}) {
    List<int> bytes = [];
    if (styles.align != _styles.align) {
      bytes += latin1.encode(
        styles.align == PosAlign.left
            ? cAlignLeft
            : (styles.align == PosAlign.center ? cAlignCenter : cAlignRight),
      );
      _styles = _styles.copyWith(align: styles.align);
    }

    if (styles.bold != _styles.bold) {
      bytes += styles.bold ? cBoldOn.codeUnits : cBoldOff.codeUnits;
      _styles = _styles.copyWith(bold: styles.bold);
    }
    if (styles.turn90 != _styles.turn90) {
      bytes += styles.turn90 ? cTurn90On.codeUnits : cTurn90Off.codeUnits;
      _styles = _styles.copyWith(turn90: styles.turn90);
    }
    if (styles.reverse != _styles.reverse) {
      bytes += styles.reverse ? cReverseOn.codeUnits : cReverseOff.codeUnits;
      _styles = _styles.copyWith(reverse: styles.reverse);
    }
    if (styles.underline != _styles.underline) {
      bytes +=
          styles.underline ? cUnderline1dot.codeUnits : cUnderlineOff.codeUnits;
      _styles = _styles.copyWith(underline: styles.underline);
    }

    // Set font
    if (styles.fontType != null && styles.fontType != _styles.fontType) {
      bytes +=
          styles.fontType == PosFontType.fontB
              ? cFontB.codeUnits
              : cFontA.codeUnits;
      _styles = _styles.copyWith(fontType: styles.fontType);
    } else if (_font != null && _font != _styles.fontType) {
      bytes += _font == PosFontType.fontB ? cFontB.codeUnits : cFontA.codeUnits;
      _styles = _styles.copyWith(fontType: _font);
    }

    // Characters size
    if (styles.height.value != _styles.height.value ||
        styles.width.value != _styles.width.value) {
      bytes += Uint8List.fromList(
        List.from(cSizeGSn.codeUnits)
          ..add(PosTextSize.decSize(styles.height, styles.width)),
      );
      _styles = _styles.copyWith(height: styles.height, width: styles.width);
    }

    // Set Kanji mode
    if (isKanji) {
      bytes += cKanjiOn.codeUnits;
    } else {
      bytes += cKanjiOff.codeUnits;
    }

    // Set local code table
    if (styles.codeTable != null) {
      bytes += Uint8List.fromList(
        List.from(cCodeTable.codeUnits)
          ..add(_profile.getCodePageId(styles.codeTable)),
      );
      _styles = _styles.copyWith(
        align: styles.align,
        codeTable: styles.codeTable,
      );
    } else if (_codeTable != null) {
      bytes += Uint8List.fromList(
        List.from(cCodeTable.codeUnits)
          ..add(_profile.getCodePageId(_codeTable)),
      );
      _styles = _styles.copyWith(align: styles.align, codeTable: _codeTable);
    }

    return bytes;
  }

  /// Sens raw command(s)
  List<int> rawBytes(List<int> cmd, {bool isKanji = false}) {
    List<int> bytes = [];
    if (!isKanji) {
      bytes += cKanjiOff.codeUnits;
    }
    bytes += Uint8List.fromList(cmd);
    return bytes;
  }

  List<int> text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  }) {
    List<int> bytes = [];
    if (!containsChinese) {
      bytes += _text(
        _encode(text, isKanji: containsChinese),
        styles: styles,
        isKanji: containsChinese,
        maxCharsPerLine: maxCharsPerLine,
      );
      // Ensure at least one line break after the text
      bytes += emptyLines(linesAfter + 1);
    } else {
      bytes += _mixedKanji(text, styles: styles, linesAfter: linesAfter);
    }
    return bytes;
  }

  /// Skips [n] lines
  ///
  /// Similar to [feed] but uses an alternative command
  List<int> emptyLines(int n) {
    List<int> bytes = [];
    if (n > 0) {
      bytes += List.filled(n, '\n').join().codeUnits;
    }
    return bytes;
  }

  /// Skips [n] lines
  ///
  /// Similar to [emptyLines] but uses an alternative command
  List<int> feed(int n) {
    List<int> bytes = [];
    if (n >= 0 && n <= 255) {
      bytes += Uint8List.fromList(List.from(cFeedN.codeUnits)..add(n));
    }
    return bytes;
  }

  /// Cut the paper
  ///
  /// [mode] is used to define the full or partial cut (if supported by the priner)
  List<int> cut({PosCutMode mode = PosCutMode.full, int? line}) {
    List<int> bytes = [];
    bytes += emptyLines(line ?? 3);
    if (mode == PosCutMode.partial) {
      bytes += cCutPart.codeUnits;
    } else {
      bytes += cCutFull.codeUnits;
    }
    return bytes;
  }

  /// Print selected code table.
  ///
  /// If [codeTable] is null, global code table is used.
  /// If global code table is null, default printer code table is used.
  List<int> printCodeTable({String? codeTable}) {
    List<int> bytes = [];
    bytes += cKanjiOff.codeUnits;

    if (codeTable != null) {
      bytes += Uint8List.fromList(
        List.from(cCodeTable.codeUnits)..add(_profile.getCodePageId(codeTable)),
      );
    }

    bytes += Uint8List.fromList(List<int>.generate(256, (i) => i));

    // Back to initial code table
    setGlobalCodeTable(_codeTable);
    return bytes;
  }

  /// Beeps [n] times
  ///
  /// Beep [duration] could be between 50 and 450 ms.
  List<int> beep({
    int n = 3,
    PosBeepDuration duration = PosBeepDuration.beep450ms,
  }) {
    List<int> bytes = [];
    if (n <= 0) {
      return [];
    }

    int beepCount = n;
    if (beepCount > 9) {
      beepCount = 9;
    }

    bytes += Uint8List.fromList(
      List.from(cBeep.codeUnits)..addAll([beepCount, duration.value]),
    );

    beep(n: n - 9, duration: duration);
    return bytes;
  }

  /// Reverse feed for [n] lines (if supported by the priner)
  List<int> reverseFeed(int n) {
    List<int> bytes = [];
    bytes += Uint8List.fromList(List.from(cReverseFeedN.codeUnits)..add(n));
    return bytes;
  }

  /// Print a row.
  ///
  /// A row contains up to 12 columns. A column has a width between 1 and 12.
  /// Total width of columns in one row must be equal 12.
  List<int> row(List<PosColumn> cols) {
    List<int> bytes = [];
    final isSumValid = cols.fold(0, (int sum, col) => sum + col.width) == 12;
    if (!isSumValid) {
      throw Exception('Total columns width must be equal to 12');
    }
    bool isNextRow = false;
    List<PosColumn> nextRow = <PosColumn>[];

    for (int i = 0; i < cols.length; ++i) {
      int colInd = cols
          .sublist(0, i)
          .fold(0, (int sum, col) => sum + col.width);
      double charWidth = _getCharWidth(cols[i].styles);
      double fromPos = _colIndToPosition(colInd);
      final double toPos =
          _colIndToPosition(colInd + cols[i].width) - spaceBetweenRows;
      int maxCharactersNb = ((toPos - fromPos) / charWidth).floor();

      if (!cols[i].containsChinese) {
        // CASE 1: containsChinese = false
        Uint8List encodedToPrint =
            cols[i].textEncoded != null
                ? cols[i].textEncoded!
                : _encode(cols[i].text);

        // If the col's content is too long, split it to the next row
        int realCharactersNb = encodedToPrint.length;
        if (realCharactersNb > maxCharactersNb) {
          // Print max possible and split to the next row
          Uint8List encodedToPrintNextRow = encodedToPrint.sublist(
            maxCharactersNb,
          );
          encodedToPrint = encodedToPrint.sublist(0, maxCharactersNb);
          isNextRow = true;
          nextRow.add(
            PosColumn(
              textEncoded: encodedToPrintNextRow,
              width: cols[i].width,
              styles: cols[i].styles,
            ),
          );
        } else {
          // Insert an empty col
          nextRow.add(
            PosColumn(text: '', width: cols[i].width, styles: cols[i].styles),
          );
        }
        // end rows splitting
        bytes += _text(
          encodedToPrint,
          styles: cols[i].styles,
          colInd: colInd,
          colWidth: cols[i].width,
        );
      } else {
        // CASE 1: containsChinese = true
        // Split text into multiple lines if it too long
        int counter = 0;
        int splitPos = 0;
        for (int p = 0; p < cols[i].text.length; ++p) {
          final int w = _isChinese(cols[i].text[p]) ? 2 : 1;
          if (counter + w >= maxCharactersNb) {
            break;
          }
          counter += w;
          splitPos += 1;
        }
        String toPrintNextRow = cols[i].text.substring(splitPos);
        String toPrint = cols[i].text.substring(0, splitPos);

        if (toPrintNextRow.isNotEmpty) {
          isNextRow = true;
          nextRow.add(
            PosColumn(
              text: toPrintNextRow,
              containsChinese: true,
              width: cols[i].width,
              styles: cols[i].styles,
            ),
          );
        } else {
          // Insert an empty col
          nextRow.add(
            PosColumn(text: '', width: cols[i].width, styles: cols[i].styles),
          );
        }

        // Print current row
        final list = _getLexemes(toPrint);
        final List<String> lexemes = list[0];
        final List<bool> isLexemeChinese = list[1];

        // Print each lexeme using codetable OR kanji
        for (var j = 0; j < lexemes.length; ++j) {
          bytes += _text(
            _encode(lexemes[j], isKanji: isLexemeChinese[j]),
            styles: cols[i].styles,
            colInd: colInd,
            colWidth: cols[i].width,
            isKanji: isLexemeChinese[j],
          );
          // Define the absolute position only once (we print one line only)
          // colInd = null;
        }
      }
    }

    bytes += emptyLines(1);

    if (isNextRow) {
      row(nextRow);
    }
    return bytes;
  }

  /// Print an image using (ESC *) command
  ///
  /// [image] is an instanse of class from [Image library](https://pub.dev/packages/image)
  List<int> image(Image imgSrc, {PosAlign align = PosAlign.center}) {
    final List<int> bytes = [];
    // Image alignment
    bytes.addAll(setStyles(PosStyles().copyWith(align: align)));

    // One pass straight from the RGBA bytes into 24-dot column strips. The
    // old way copied, inverted, flipped and rotated the whole receipt, padded
    // it into another copy, cropped and greyscaled every strip and packed
    // bits through a function call per pixel -- seconds on a long bill on a
    // TV box or cheap tablet, before the printer got a byte. The flip +
    // 270-degree rotation is a transpose, so a strip is just 24 source rows
    // read column by column; the bytes sent are the same (a pixel darker
    // than mid grey prints, top pixel in the high bit).
    final Image image =
        imgSrc.format == Format.uint8 && imgSrc.numChannels == 4
            ? imgSrc
            : imgSrc.convert(format: Format.uint8, numChannels: 4);
    final int width = image.width;
    final int height = image.height;
    final Uint8List rgba = image.getBytes(order: ChannelOrder.rgba);

    const int stripDots = 24; // 24-dot double density (m = 33)
    // As before: rows padded up past the last full strip (always at least
    // one blank strip more), so printers feed exactly as they did.
    final int strips = (height + stripDots - height % stripDots) ~/ stripDots;

    final List<int> header =
        List.from(cBitImg.codeUnits)
          ..add(1 + 32)
          ..addAll(_intLowHigh(width, 2));

    // A strip with no ink goes as a one-column white image (9 bytes, not
    // width x 3): still a 24-dot bit image, so the printer feeds exactly as
    // for the full strip. A receipt is a third or more white rows, and over
    // Bluetooth (10-30 KB/s) every byte is time.
    final List<int> blankStrip =
        List.from(cBitImg.codeUnits)
          ..add(1 + 32)
          ..addAll(_intLowHigh(1, 2))
          ..addAll(const [0, 0, 0, 0x0A]);

    // Adjust line spacing (for 16-unit line feeds): ESC 3 0x10
    bytes.addAll(const [27, 51, 16]);
    final Uint8List strip = Uint8List(width * 3);
    for (int s = 0; s < strips; s++) {
      strip.fillRange(0, strip.length, 0);
      var inked = false;
      final int top = s * stripDots;
      for (int dy = 0; dy < stripDots; dy++) {
        final int y = top + dy;
        if (y >= height) break;
        final int byteInCol = dy >> 3;
        final int bit = 0x80 >> (dy & 7);
        int src = y * width * 4;
        for (int x = 0; x < width; x++, src += 4) {
          if (_isInk(rgba, src)) {
            strip[x * 3 + byteInCol] |= bit;
            inked = true;
          }
        }
      }
      if (!inked) {
        bytes.addAll(blankStrip);
        continue;
      }
      bytes
        ..addAll(header)
        ..addAll(strip)
        ..add(0x0A);
    }
    // Reset line spacing: ESC 2
    bytes.addAll(const [27, 50]);
    return bytes;
  }

  /// Print an image using (GS v 0) obsolete command
  ///
  /// [image] is an instanse of class from [Image library](https://pub.dev/packages/image)
  List<int> imageRaster(
    Image image, {
    PosAlign align = PosAlign.center,
    bool highDensityHorizontal = true,
    bool highDensityVertical = true,
    PosImageFn imageFn = PosImageFn.bitImageRaster,
  }) {
    List<int> bytes = [];
    // Image alignment
    bytes += setStyles(PosStyles().copyWith(align: align));

    final int widthPx = image.width;
    final int heightPx = image.height;
    final int widthBytes = (widthPx + 7) ~/ 8;
    final List<int> resterizedData = _toRasterFormat(image);

    if (imageFn == PosImageFn.bitImageRaster) {
      // GS v 0
      final int densityByte =
          (highDensityVertical ? 0 : 1) + (highDensityHorizontal ? 0 : 2);

      void raster(int xBytes, int rows, Iterable<int> data) =>
          bytes
            ..addAll(cRasterImg2.codeUnits)
            ..add(densityByte) // m
            ..addAll(_intLowHigh(xBytes, 2)) // xL xH
            ..addAll(_intLowHigh(rows, 2)) // yL yH
            ..addAll(data);

      // A run of blank rows goes as a one-byte-wide white raster of the same
      // height: the printer feeds the same dots, but sends `rows` bytes, not
      // `widthBytes x rows` (receipts are a third or more white -- seconds
      // over Bluetooth). Short gaps (under [minBlankRun] rows, e.g. between
      // text lines) stay inside the image so it is not cut into slivers.
      const int minBlankRun = 8;
      bool blankRow(int y) {
        final int o = y * widthBytes;
        for (int i = 0; i < widthBytes; i++) {
          if (resterizedData[o + i] != 0) return false;
        }
        return true;
      }

      int y = 0;
      while (y < heightPx) {
        int end = y;
        while (end < heightPx && blankRow(end)) {
          end++;
        }
        if (end - y >= minBlankRun || (end == heightPx && end > y)) {
          raster(1, end - y, List<int>.filled(end - y, 0));
          y = end;
          continue;
        }
        // Ink from y up to the next blank run long enough to split at.
        int inkEnd = end;
        while (inkEnd < heightPx) {
          int b = inkEnd;
          while (b < heightPx && blankRow(b)) {
            b++;
          }
          if (b - inkEnd >= minBlankRun || b == heightPx) break;
          inkEnd = b + 1;
        }
        if (inkEnd > heightPx) inkEnd = heightPx;
        raster(
          widthBytes,
          inkEnd - y,
          resterizedData.sublist(y * widthBytes, inkEnd * widthBytes),
        );
        y = inkEnd;
      }
    } else if (imageFn == PosImageFn.graphics) {
      // 'GS ( L' - FN_112 (Image data)
      final List<int> header1 = List.from(cRasterImg.codeUnits);
      header1.addAll(_intLowHigh(widthBytes * heightPx + 10, 2)); // pL pH
      header1.addAll([48, 112, 48]); // m=48, fn=112, a=48
      header1.addAll([1, 1]); // bx=1, by=1
      header1.addAll([49]); // c=49
      header1.addAll(_intLowHigh(widthBytes, 2)); // xL xH
      header1.addAll(_intLowHigh(heightPx, 2)); // yL yH
      bytes += List.from(header1)..addAll(resterizedData);

      // 'GS ( L' - FN_50 (Run print)
      final List<int> header2 = List.from(cRasterImg.codeUnits);
      header2.addAll([2, 0]); // pL pH
      header2.addAll([48, 50]); // m fn[2,50]
      bytes += List.from(header2);
    }
    return bytes;
  }

  /// Print a barcode
  ///
  /// [width] range and units are different depending on the printer model (some printers use 1..5).
  /// [height] range: 1 - 255. The units depend on the printer model.
  /// Width, height, font, text position settings are effective until performing of ESC @, reset or power-off.
  List<int> barcode(
    Barcode barcode, {
    int? width,
    int? height,
    BarcodeFont? font,
    BarcodeText textPos = BarcodeText.below,
    PosAlign align = PosAlign.center,
  }) {
    List<int> bytes = [];
    // Set alignment
    bytes += setStyles(PosStyles().copyWith(align: align));

    // Set text position
    bytes += cBarcodeSelectPos.codeUnits + [textPos.value];

    // Set font
    if (font != null) {
      bytes += cBarcodeSelectFont.codeUnits + [font.value];
    }

    // Set width
    if (width != null && width >= 0) {
      bytes += cBarcodeSetW.codeUnits + [width];
    }
    // Set height
    if (height != null && height >= 1 && height <= 255) {
      bytes += cBarcodeSetH.codeUnits + [height];
    }

    // Print barcode
    final header = cBarcodePrint.codeUnits + [barcode.type.value];
    if (barcode.type.value <= 6) {
      // Function A
      bytes += header + barcode.data + [0];
    } else {
      // Function B
      bytes += header + [barcode.data.length] + barcode.data;
    }
    return bytes;
  }

  /// Print a QR Code
  List<int> qrcode(
    String text, {
    PosAlign align = PosAlign.center,
    QRSize size = QRSize.Size4,
    QRCorrection cor = QRCorrection.L,
  }) {
    List<int> bytes = [];
    // Set alignment
    bytes += setStyles(PosStyles().copyWith(align: align));
    QRCode qr = QRCode(text, size, cor);
    bytes += qr.bytes;
    return bytes;
  }

  /// Open cash drawer
  List<int> drawer({PosDrawer pin = PosDrawer.pin2}) {
    List<int> bytes = [];
    if (pin == PosDrawer.pin2) {
      bytes += cCashDrawerPin2.codeUnits;
    } else {
      bytes += cCashDrawerPin5.codeUnits;
    }
    return bytes;
  }

  /// Print horizontal full width separator
  /// If [len] is null, then it will be defined according to the paper width
  List<int> hr({String ch = '-', int? len, int linesAfter = 0}) {
    List<int> bytes = [];
    int n = len ?? _maxCharsPerLine ?? _getMaxCharsPerLine(_styles.fontType);
    String ch1 = ch.length == 1 ? ch : ch[0];
    bytes += text(List.filled(n, ch1).join(), linesAfter: linesAfter);
    return bytes;
  }

  List<int> textEncoded(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    List<int> bytes = [];
    bytes += _text(textBytes, styles: styles, maxCharsPerLine: maxCharsPerLine);
    // Ensure at least one line break after the text
    bytes += emptyLines(linesAfter + 1);
    return bytes;
  }

  // ************************ (end) Public command generators ************************

  // ************************ (end) Internal command generators ************************
  /// Generic print for internal use
  ///
  /// [colInd] range: 0..11. If null: do not define the position
  List<int> _text(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int? colInd = 0,
    bool isKanji = false,
    int colWidth = 12,
    int? maxCharsPerLine,
  }) {
    List<int> bytes = [];
    if (colInd != null) {
      double charWidth = _getCharWidth(
        styles,
        maxCharsPerLine: maxCharsPerLine,
      );
      double fromPos = _colIndToPosition(colInd);

      // Align
      if (colWidth != 12) {
        // Update fromPos
        final double toPos =
            _colIndToPosition(colInd + colWidth) - spaceBetweenRows;
        final double textLen = textBytes.length * charWidth;

        if (styles.align == PosAlign.right) {
          fromPos = toPos - textLen;
        } else if (styles.align == PosAlign.center) {
          fromPos = fromPos + (toPos - fromPos) / 2 - textLen / 2;
        }
        if (fromPos < 0) {
          fromPos = 0;
        }
      }

      final hexStr = fromPos.round().toRadixString(16).padLeft(3, '0');
      final hexPair = HEX.decode(hexStr);

      // Position
      bytes += Uint8List.fromList(
        List.from(cPos.codeUnits)..addAll([hexPair[1], hexPair[0]]),
      );
    }

    bytes += setStyles(styles, isKanji: isKanji);

    bytes += textBytes;
    return bytes;
  }

  /// Prints one line of styled mixed (chinese and latin symbols) text
  List<int> _mixedKanji(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    List<int> bytes = [];
    final list = _getLexemes(text);
    final List<String> lexemes = list[0];
    final List<bool> isLexemeChinese = list[1];

    // Print each lexeme using codetable OR kanji
    int? colInd = 0;
    for (var i = 0; i < lexemes.length; ++i) {
      bytes += _text(
        _encode(lexemes[i], isKanji: isLexemeChinese[i]),
        styles: styles,
        colInd: colInd,
        isKanji: isLexemeChinese[i],
        maxCharsPerLine: maxCharsPerLine,
      );
      // Define the absolute position only once (we print one line only)
      colInd = null;
    }

    bytes += emptyLines(linesAfter + 1);
    return bytes;
  }
  // ************************ (end) Internal command generators ************************
}
