import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'drago_pos_printer_platform_interface.dart';

/// An implementation of [DragoPosPrinterPlatform] that uses method channels.
class MethodChannelDragoPosPrinter extends DragoPosPrinterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('drago_pos_printer');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
