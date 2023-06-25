import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'drago_pos_printer_method_channel.dart';

abstract class DragoPosPrinterPlatform extends PlatformInterface {
  /// Constructs a DragoPosPrinterPlatform.
  DragoPosPrinterPlatform() : super(token: _token);

  static final Object _token = Object();

  static DragoPosPrinterPlatform _instance = MethodChannelDragoPosPrinter();

  /// The default instance of [DragoPosPrinterPlatform] to use.
  ///
  /// Defaults to [MethodChannelDragoPosPrinter].
  static DragoPosPrinterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DragoPosPrinterPlatform] when
  /// they register themselves.
  static set instance(DragoPosPrinterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
