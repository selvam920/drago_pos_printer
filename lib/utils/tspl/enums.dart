enum Direction {
  forWord,
  backWord,
}

extension ExDirection on Direction {
  int get value {
    switch (this) {
      case Direction.forWord:
        return 0;
      case Direction.backWord:
        return 1;
    }
  }
}

enum Density {
  density0,
  density1,
  density2,
  density3,
  density4,
  density5,
  density6,
  density7,
  density8,
  density9,
  density10,
  density11,
  density12,
  density13,
  density14,
  density15,
}

extension ExDensity on Density {
  int get value {
    switch (this) {
      case Density.density0:
        return 0;
      case Density.density1:
        return 1;
      case Density.density2:
        return 2;
      case Density.density3:
        return 3;
      case Density.density4:
        return 4;
      case Density.density5:
        return 5;
      case Density.density6:
        return 6;
      case Density.density7:
        return 7;
      case Density.density8:
        return 8;
      case Density.density9:
        return 9;
      case Density.density10:
        return 10;
      case Density.density11:
        return 11;
      case Density.density12:
        return 12;
      case Density.density13:
        return 13;
      case Density.density14:
        return 14;
      case Density.density15:
        return 15;
    }
  }
}

//启用/禁用撕纸位置走到撕纸处，此设置关掉电源后将保存在打印机内
enum Tear {
  on,
  off,
}

extension ExTear on Tear {
  String get value {
    switch (this) {
      case Tear.on:
        return 'ON';
      case Tear.off:
        return 'OFF';
    }
  }
}
