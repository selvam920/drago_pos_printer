import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:webcontent_converter/webcontent_converter.dart';
import 'demo.dart';
import 'service.dart';

class BluetoothPrinterScreen extends StatefulWidget {
  @override
  _BluetoothPrinterScreenState createState() => _BluetoothPrinterScreenState();
}

class _BluetoothPrinterScreenState extends State<BluetoothPrinterScreen> {
  bool _isLoading = false;
  List<BluetoothPrinter> _printers = [];

  int paperWidth = 0;
  int charPerLine = 0;

  List<String> paperTypes = [];
  bool showCustom = false;
  @override
  void initState() {
    paperWidth = PaperSizeWidth.mm80;
    charPerLine = PaperSizeMaxPerLine.mm80;

    paperTypes.add('58mm');
    paperTypes.add('80mmOld');
    paperTypes.add('80mm');
    paperTypes.add('Custom');

    super.initState();
    _scan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Bluetooth Printer Screen"),
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
                    leading: Icon(Icons.bluetooth),
                    trailing: Wrap(
                      children: [
                        IconButton(
                            tooltip: 'ESC POS Command',
                            onPressed: () => _print(1, printer),
                            icon: Icon(Icons.print)),
                        IconButton(
                            tooltip: 'Html Print',
                            onPressed: () => _print(3, printer),
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
    print("scan");
    setState(() {
      _isLoading = true;
      _printers = [];
    });
    BluetoothPrinterManager.discover().then((val) {
      print(val);
      setState(() {
        _isLoading = false;
        _printers = val;
      });
    }).catchError((err) {
      var snackBar = SnackBar(
        content: Text(err.toString()),
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    });
  }

  _print(int byteType, BluetoothPrinter printer) async {
    var profile = await CapabilityProfile.load();
    var manager = BluetoothPrinterManager(printer);
    await manager.connect();
    late List<int> data;
    if (byteType == 1) {
      data = await ESCPrinterService(null).getSamplePosBytes(
          paperSizeWidthMM: paperWidth,
          maxPerLine: charPerLine,
          profile: profile);
    } else if (byteType == 2) {
      data = await ESCPrinterService(null).getPdfBytes(
          paperSizeWidthMM: paperWidth,
          maxPerLine: charPerLine,
          profile: profile);
    } else if (byteType == 3) {
      final content = Demo.getShortReceiptContent();

      Uint8List? htmlBytes = await WebcontentConverter.contentToImage(
        content: content,
        executablePath: WebViewHelper.executablePath(),
      );

      var service = ESCPrinterService(htmlBytes);
      data = await service.getBytes(
          paperSizeWidthMM: paperWidth,
          maxPerLine: charPerLine,
          profile: profile);
    }

    manager.writeBytes(data).then((val) {}).catchError((err) {
      var snackBar = SnackBar(
        content: Text(err.toString()),
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }).whenComplete(() {
      //manager.disconnect();
    });
  }
}
