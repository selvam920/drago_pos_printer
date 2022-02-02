/*
 * esc_pos_utils
 * Created by Andrey U.
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

enum PosAlign { left, center, right }
enum PosCutMode { full, partial }
enum PosFontType { fontA, fontB }
enum PosDrawer { pin2, pin5 }

/// Choose image printing function
/// bitImageRaster: GS v 0 (obsolete)
/// graphics: GS ( L
enum PosImageFn { bitImageRaster, graphics }

class PosTextSize {
  static const size1 = 1;
  static const size2 = 2;
  static const size3 = 3;
  static const size4 = 4;
  static const size5 = 5;
  static const size6 = 6;
  static const size7 = 7;
  static const size8 = 8;

  static int decSize(int height, int width) => 16 * (width - 1) + (height - 1);
}

class PaperSizeWidth {
  static int mm58 = 384;
  static const mm80_Old = 500;
  static const mm80 = 570;

  // static const mm70 = 500;
  // static const mm72 = 512;
  // static const mm80 = 576;
}

class PaperSizeMaxPerLine {
  static int mm58 = 32;
  static const mm80_Old = 42;
  static const mm80 = 48;
  // static const mm70 = 42;
  // static const mm72 = 48;
  // static const mm80 = 48;
}

// class PaperSize {
//   const PaperSize._internal(this.value);
//   final int value;
//   static const mm58 = PaperSize._internal(1);
//   static const mm70 = PaperSize._internal(2);
//   static const mm72 = PaperSize._internal(3);
//   static const mm80 = PaperSize._internal(4);

//   int get width {
//     if (value == PaperSize.mm58.value) {
//       return 384;
//     } else if (value == PaperSize.mm70.value) {
//       return 500;
//     } else if (value == PaperSize.mm72.value) {
//       return 512;
//     } else {
//       return 576;
//     }
//     // value == PaperSize.mm58.value ? 384 : 558;
//   }
// }

class PosBeepDuration {
  const PosBeepDuration._internal(this.value);
  final int value;
  static const beep50ms = PosBeepDuration._internal(1);
  static const beep100ms = PosBeepDuration._internal(2);
  static const beep150ms = PosBeepDuration._internal(3);
  static const beep200ms = PosBeepDuration._internal(4);
  static const beep250ms = PosBeepDuration._internal(5);
  static const beep300ms = PosBeepDuration._internal(6);
  static const beep350ms = PosBeepDuration._internal(7);
  static const beep400ms = PosBeepDuration._internal(8);
  static const beep450ms = PosBeepDuration._internal(9);
}
