import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:webcontent_converter/webcontent_converter.dart';
import 'demo.dart';
import 'service.dart';

class USBPrinterScreen extends StatefulWidget {
  @override
  _USBPrinterScreenState createState() => _USBPrinterScreenState();
}

class _USBPrinterScreenState extends State<USBPrinterScreen> {
  bool _isLoading = false;
  List<USBPrinter> _printers = [];
  USBPrinterManager? _manager;
  List<int> _data = [];

  int paperWidth = 0;
  int charPerLine = 0;

  List<String> paperTypes = [];
  bool showCustom = false;

  @override
  void initState() {
    _scan();
    paperWidth = PaperSizeWidth.mm80;
    charPerLine = PaperSizeMaxPerLine.mm80;

    paperTypes.add('58mm');
    paperTypes.add('80mmOld');
    paperTypes.add('80mm');
    paperTypes.add('Custom');

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("USB Printer Screen"),
      ),
      body: ListView(
        padding: EdgeInsets.all(20),
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButtonFormField(
              decoration: InputDecoration(labelText: 'Paper Size'),
              items: paperTypes.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
              onChanged: (String? selected) async {
                showCustom = false;
                if (selected != null) {
                  if (selected == "58mm") {
                    paperWidth = PaperSizeWidth.mm58;
                    charPerLine = PaperSizeMaxPerLine.mm58;
                  } else if (selected == "80mmOld") {
                    paperWidth = PaperSizeWidth.mm80_Old;
                    charPerLine = PaperSizeMaxPerLine.mm80_Old;
                  } else if (selected == "80mm") {
                    paperWidth = PaperSizeWidth.mm80;
                    charPerLine = PaperSizeMaxPerLine.mm80;
                  } else if (selected == "Custom") {
                    paperWidth = PaperSizeWidth.mm80;
                    charPerLine = PaperSizeMaxPerLine.mm80;
                    showCustom = true;
                  }
                  setState(() {});
                }
              },
            ),
          ),
          if (showCustom)
            Row(
              children: [
                Expanded(
                    child: TextFormField(
                  initialValue: paperWidth.toString(),
                  onChanged: (val) {
                    if (val.isNotEmpty) {
                      paperWidth = int.parse(val);
                    } else
                      paperWidth = 0;
                  },
                )),
                SizedBox(width: 20),
                Expanded(
                    child: TextFormField(
                  initialValue: charPerLine.toString(),
                  onChanged: (val) {
                    if (val.isNotEmpty) {
                      charPerLine = int.parse(val);
                    } else
                      charPerLine = 0;
                  },
                ))
              ],
            ),
          SizedBox(height: 10),
          ..._printers
              .map((printer) => ListTile(
                    title: Text("${printer.name}"),
                    subtitle: Text("${printer.address}"),
                    leading: Icon(Icons.usb),
                    trailing: Wrap(
                      children: [
                        IconButton(
                            tooltip: 'ESC POS Command',
                            onPressed: () => _startPrinter(1, printer),
                            icon: Icon(Icons.print)),
                        IconButton(
                            tooltip: 'Pdf',
                            onPressed: () => _startPrinter(2, printer),
                            icon: Icon(Icons.picture_as_pdf)),
                        IconButton(
                            tooltip: 'Html Print',
                            onPressed: () => _startPrinter(3, printer),
                            icon: Icon(Icons.image)),
                      ],
                    ),
                  ))
              .toList(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: _isLoading ? Icon(Icons.stop) : Icon(Icons.play_arrow),
        onPressed: _isLoading ? null : _scan,
      ),
    );
  }

  _scan() async {
    setState(() {
      _isLoading = true;
      _printers = [];
    });
    var printers = await USBPrinterManager.discover();
    setState(() {
      _isLoading = false;
      _printers = printers;
    });
  }

  Future _connect(USBPrinter printer) async {
    var profile = await CapabilityProfile.load();
    var manager = USBPrinterManager(printer, paperWidth, charPerLine, profile);
    await manager.connect();
    setState(() {
      _manager = manager;
      printer.connected = true;
    });
  }

  _startPrinter(int byteType, USBPrinter printer) async {
    // await _connect(printer);
    var profile = await CapabilityProfile.load();
    var manager = USBPrinterManager(printer, paperWidth, charPerLine, profile);
    _manager = manager;

    final content = Demo.getShortReceiptContent();
    var bytes = byteType == 1
        ? await ESCPrinterService(null).getSamplePosBytes(
            paperSizeWidthMM: _manager!.paperSizeWidthMM,
            maxPerLine: _manager!.maxPerLine,
            profile: _manager!.profile)
        : byteType == 2
            ? await ESCPrinterService(null).getPdfBytes(
                paperSizeWidthMM: _manager!.paperSizeWidthMM,
                maxPerLine: _manager!.maxPerLine,
                profile: _manager!.profile)
            : (await WebcontentConverter.contentToImage(
                content: content,
                executablePath: WebViewHelper.executablePath(),
              ))
                .toList();
    List<int> data;
    if (byteType == 3) {
      var service = ESCPrinterService(Uint8List.fromList(bytes));
      data = await service.getBytes(
        paperSizeWidthMM: _manager!.paperSizeWidthMM,
        maxPerLine: _manager!.maxPerLine,
      );
      if (bytes.length > 0) {
        var dir = await getTemporaryDirectory();
        var path = dir.path + "\\receipt.jpg";
        File file = File(path);
        await file.writeAsBytes(bytes);
      }
    } else
      data = bytes;
    if (mounted) setState(() => _data = data);

    _manager!.writeBytes(_data, isDisconnect: true);
  }
}
