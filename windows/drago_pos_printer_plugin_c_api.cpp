#include "include/drago_pos_printer/drago_pos_printer_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "drago_pos_printer_plugin.h"

void DragoPosPrinterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  drago_pos_printer::DragoPosPrinterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
