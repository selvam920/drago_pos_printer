import 'dart:math';

import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

/// The ESC * encoder before the one-pass rewrite (copy, invert, flip,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
