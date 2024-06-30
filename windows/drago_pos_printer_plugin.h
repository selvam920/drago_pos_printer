#ifndef FLUTTER_PLUGIN_DRAGO_POS_PRINTER_PLUGIN_H_
#define FLUTTER_PLUGIN_DRAGO_POS_PRINTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace drago_pos_printer {

class DragoPosPrinterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DragoPosPrinterPlugin();

  virtual ~DragoPosPrinterPlugin();

  // Disallow copy and assign.
  DragoPosPrinterPlugin(const DragoPosPrinterPlugin&) = delete;
  DragoPosPrinterPlugin& operator=(const DragoPosPrinterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace drago_pos_printer

#endif  // FLUTTER_PLUGIN_DRAGO_POS_PRINTER_PLUGIN_H_
