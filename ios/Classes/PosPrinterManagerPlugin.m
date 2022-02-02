#import "DragoPrinterManagerPlugin.h"
#if __has_include(<pos_printing/pos_printing-Swift.h>)
#import <pos_printing/pos_printing-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "pos_printing-Swift.h"
#endif

@implementation DragoPrinterManagerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftDragoPrinterManagerPlugin registerWithRegistrar:registrar];
}
@end
