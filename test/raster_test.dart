import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('GS v 0 raster: black left half, white right half', () async {
    final img = Image(width: 16, height: 2, numChannels: 4);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 16; x++) {
        final v = x < 8 ? 0 : 255;
        img.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    final g = EscGenerator(576, 48, await CapabilityProfile.load());
    final bytes = g.imageRaster(img);
    final data = bytes.sublist(bytes.length - 4);
    expect(data, [0xFF, 0x00, 0xFF, 0x00]);
  });
}
