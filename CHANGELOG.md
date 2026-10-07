## 0.0.1

* Initial Release

## 0.0.2
* Updated to Android 12

## 0.0.4
* Updated latest packages

## 0.0.5
* Updated image v4

## 0.0.6
* Page bottom extra line optional

## 0.0.7
* Updated to flutter 3.10

## 0.0.8
* Fix package version

## 0.0.9
* USB Printer by vendor Id and product id

## 1.0.0
* Fix usb disconnect after print

## 1.0.1
* Upgrade gradle to > 8.0

## 1.0.2
* Update network discovery logic

## 1.0.3
* Issue fix

## 1.0.4
* Fixes Bluetooth

## 1.0.5
* Update gradle version to 8.9.2

## 1.0.6
* Update dependancies

## 1.0.7
* Removed auto cut

## 1.0.8
* Improved bluetooth list only show printers

## 1.0.9
* Fixed bluetooth initialization issue

## 1.1.0
* Fixed usb initialization issue

## 1.1.1
* Update package version

## 1.1.2
* Added bluetooth scan & pair feature

## 1.1.3
* Improved printing

## 1.1.4
* Improved usb printing

## 1.1.6
* Support android 17

## 1.1.7 
Fix android build issue

## 1.1.8
Upgrade android AGP

## 1.1.9
Fix android AGP
## 1.1.10
* New `PrinterReadiness` / `PrinterStatusQuery` (TSPL `<ESC>!?`, ESC/POS `DLE EOT 4`) and `checkStatus(job)` on Bluetooth, USB and network managers.
* `BluetoothPrinter.battery` and `connected`.
* USB (Windows): native memory and printer handle freed per job in `finally`; no leak or double free; failed jobs still end page/doc.
* USB (Android): no reconnect inside `writeBytes` when already connected; failed connect / write now reported as errors; `disconnect` safe when not connected; `pair()` is a no-op.
* Network: socket errors handled (no unhandled isolate crash), dead sockets detected, connect timeout default, flush/close with timeout, always destroyed.
* Bluetooth: no `NoSuchMethodError` in connect error handling, "already connected" retried once (no infinite loop), iOS write awaited.
* Android: `onActivityResult` no longer swallows other plugins' results; duplicate listeners removed.
* New `LabelJob.build(image, language:, dpi:, compression:)`: one label image to a TSPL, ESC/POS or CPCL job at 203 or 300 dpi. Compression skips blank rows (ESC/POS feeds over them, CPCL sends binary `CG` instead of hex `EG`), so jobs are smaller and faster over Bluetooth; works on any printer of that language.
* `LabelJob`: `media` (gap / black mark / continuous) and `topOffsetMm`. ESC/POS label jobs now end with GS FF (feed to next label start) -- verified on an LD0801 / DeTong DP27 raster label printer, which speaks ESC/POS raster only (no TSPL, no text font). `LabelCommands`: TSPL calibrate (GAPDETECT/BLINEDETECT), self test, text-only test.
* `LabelLanguage.detong`: DeTong DP27 / LD0801 own raster protocol (as sent by the maker's Windows driver) -- row run-length + repeat, ~2.5x smaller than ESC/POS raster; `1F 27` darkness.
* ESC/POS label jobs are sent as one raster block (blank rows above/below trimmed) instead of 128-row bands.
* Example: Label settings card (language, DPI, compression, size, gap) and a Label print button on the USB, Bluetooth and network screens.
* Requires drago_blue_printer ^1.0.4 and drago_usb_printer ^0.1.7.