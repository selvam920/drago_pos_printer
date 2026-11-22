import 'dart:math';

import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

/// The ESC * encoder before the one-pass rewrite (plus the blank-strip
/// shortcut, applied the same way) (copy, invert, flip,
/// rotate, pad, slice, greyscale, pack bit by bit), kept here as the
/// reference the fast one must match byte for byte.
List<int> legacyImage(EscGenerator g, Image imgSrc) {
  List<int> lowHigh(int value) => [value & 0xFF, (value >> 8) & 0xFF];

  List<List<int>> toColumnFormat(Image imgSrc, int lineHeight) {
    final Image image = Image.from(imgSrc);
    final int widthPx = (image.width + lineHeight) - (image.width % lineHeight);
    final int heightPx = image.height;
    final biggerImage = copyResize(image, width: widthPx, height: heightPx);
    fill(biggerImage, color: ColorInt8(0));
    compositeImage(biggerImage, image, dstX: 0, dstY: 0);
    int left = 0;
    final List<List<int>> blobs = [];
    while (left < widthPx) {
      final Image slice = copyCrop(
        biggerImage,
        x: left,
        y: 0,
        width: lineHeight,
        height: heightPx,
      );
      grayscale(slice);
      blobs.add(slice.convert(numChannels: 1).getBytes());
      left += lineHeight;
    }
    return blobs;
  }

  List<int> packBits(List<int> bytes) {
    final res = <int>[];
    for (int i = 0; i < bytes.length; i += 8) {
      int v = 0;
      for (int j = 0; j < 8; j++) {
        if (bytes[i + j] > 127) v |= 0x80 >> j;
      }
      res.add(v);
    }
    return res;
  }

  final bytes = <int>[];
  bytes.addAll(g.setStyles(PosStyles().copyWith(align: PosAlign.center)));
  final Image image = Image.from(imgSrc);
  invert(image);
  flip(image, direction: FlipDirection.horizontal);
  final Image rotated = copyRotate(image, angle: 270);
  final blobs = toColumnFormat(rotated, 24).map(packBits).toList();
  final header = [0x1B, 0x2A, 33, ...lowHigh(rotated.height)];
  bytes.addAll([27, 51, 16]);
  for (final b in blobs) {
    // A strip with no ink: the one-column white strip the encoder sends
    // instead (same 24-dot feed, 9 bytes).
    if (b.every((v) => v == 0)) {
      bytes.addAll([0x1B, 0x2A, 33, 1, 0, 0, 0, 0, 0x0A]);
      continue;
    }
    bytes
      ..addAll(header)
      ..addAll(b)
      ..add(0x0A);
  }
  bytes.addAll([27, 50]);
  return bytes;
}

/// A receipt-like image: pure black / white pixels (what the app sends after
/// thresholding), random so every bit position is exercised.
Image receipt(int width, int height, Random rnd) {
  final img = Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = rnd.nextBool() ? 0 : 255;
      img.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return img;
}

/// What Android's PDF raster gives: black ink on a transparent (0,0,0,0)
/// background, with some see-through anti-aliased edge pixels when
/// [edges] is set.
Image androidReceipt(int width, int height, Random rnd, {bool edges = false}) {
  final img = Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final r = rnd.nextInt(10);
      final a =
          r < 4
              ? 255
              : edges && r < 6
              ? rnd.nextInt(256)
              : 0;
      img.setPixelRgba(x, y, 0, 0, 0, a);
    }
  }
  return img;
}

/// Rebuilds the full 1-bit picture from a run of GS v 0 commands: each
/// command's rows are widened to [widthBytes] (a narrow one is white).
List<int> unpackRaster(List<int> bytes, int widthBytes) {
  final out = <int>[];
  var i = 0;
  while (i + 7 < bytes.length) {
    if (bytes[i] == 0x1D && bytes[i + 1] == 0x76 && bytes[i + 2] == 0x30) {
      final xb = bytes[i + 4] | bytes[i + 5] << 8;
      final rows = bytes[i + 6] | bytes[i + 7] << 8;
      var p = i + 8;
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < widthBytes; c++) {
          out.add(c < xb ? bytes[p + c] : 0);
        }
        p += xb;
      }
      i = p;
    } else {
      i++;
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('blank strips go as one white column, same feed', () async {
    final profile = await CapabilityProfile.load();
    // 48 rows: a black line in strip 0, strip 1 white, plus the padding strip.
    final img = Image(width: 64, height: 48, numChannels: 4);
    for (var y = 0; y < 48; y++) {
      for (var x = 0; x < 64; x++) {
        final v = y == 3 ? 0 : 255;
        img.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    final out = EscGenerator(576, 48, profile).image(img);
    final legacy = legacyImage(EscGenerator(576, 48, profile), img);
    expect(out, legacy);
    // One full strip (5 + 192 + 1) and two blank ones (9 each), not three
    // full ones.
    final full = <int>[0x1B, 0x2A, 33, 64, 0];
    var fullCount = 0, blankCount = 0;
    for (var i = 0; i + 4 < out.length; i++) {
      if (out[i] == 0x1B && out[i + 1] == 0x2A) {
        if (out[i + 3] == 1 && out[i + 4] == 0) blankCount++;
        if (out[i + 3] == full[3] && out[i + 4] == 0) fullCount++;
      }
    }
    expect(fullCount, 1);
    expect(blankCount, 2);
  });

  test('GS v 0: blank runs shrink, the picture is unchanged', () async {
    final profile = await CapabilityProfile.load();
    final rnd = Random(3);
    // Text-like bands of ink with white gaps of 2..40 rows between them.
    final img = Image(width: 100, height: 300, numChannels: 4);
    var y = 0;
    var ink = true;
    while (y < 300) {
      final h = ink ? 5 + rnd.nextInt(20) : 2 + rnd.nextInt(39);
      for (var r = y; r < y + h && r < 300; r++) {
        for (var x = 0; x < 100; x++) {
          final v = ink && rnd.nextInt(3) == 0 ? 0 : 255;
          img.setPixelRgba(x, r, v, v, v, 255);
        }
      }
      y += h;
      ink = !ink;
    }
    final g = EscGenerator(576, 48, profile);
    final out = g.imageRaster(img);
    final widthBytes = (100 + 7) ~/ 8;
    // The plain one-command picture, row by row.
    final plain = <int>[];
    for (var r = 0; r < 300; r++) {
      for (var c = 0; c < widthBytes; c++) {
        var v = 0;
        for (var b = 0; b < 8; b++) {
          final x = c * 8 + b;
          if (x < 100 && img.getPixel(x, r).r < 128) v |= 0x80 >> b;
        }
        plain.add(v);
      }
    }
    expect(unpackRaster(out, widthBytes), plain);
    expect(out.length, lessThan(plain.length));
  });

  test('ESC * one-pass encoder matches the old one byte for byte', () async {
    final profile = await CapabilityProfile.load();
    final rnd = Random(7);
    for (final (w, h) in const [
      (8, 1),
      (16, 23),
      (16, 24),
      (16, 25),
      (100, 47),
      (100, 48),
      (576, 300),
    ]) {
      final img = receipt(w, h, rnd);
      final fast = EscGenerator(576, 48, profile).image(img);
      final legacy = legacyImage(EscGenerator(576, 48, profile), img);
      expect(fast, legacy, reason: 'size ${w}x$h');
    }
  });

  test('transparent background prints white, as before', () async {
    final profile = await CapabilityProfile.load();
    final rnd = Random(11);
    for (final (w, h) in const [(16, 25), (100, 48), (576, 120)]) {
      final img = androidReceipt(w, h, rnd);
      final fast = EscGenerator(576, 48, profile).image(img);
      final legacy = legacyImage(EscGenerator(576, 48, profile), img);
      expect(fast, legacy, reason: 'size ${w}x$h');
    }
    final blank = Image(width: 64, height: 24, numChannels: 4); // all clear
    final out = EscGenerator(576, 48, profile).image(blank);
    final legacy = legacyImage(EscGenerator(576, 48, profile), blank);
    expect(out, legacy);
  });

  // Half see-through pixels near the 50% cut may round the other way from
  // the old blend; only a sliver of bytes may differ.
  test('see-through edge pixels stay close to the old output', () async {
    final profile = await CapabilityProfile.load();
    final img = androidReceipt(576, 96, Random(5), edges: true);
    final fast = EscGenerator(576, 48, profile).image(img);
    final legacy = legacyImage(EscGenerator(576, 48, profile), img);
    expect(fast.length, legacy.length);
    var diff = 0;
    for (var i = 0; i < fast.length; i++) {
      if (fast[i] != legacy[i]) diff++;
    }
    expect(diff, lessThan(fast.length ~/ 100));
  });
}
