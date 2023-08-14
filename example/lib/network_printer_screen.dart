import 'package:flutter/material.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:webcontent_converter/webcontent_converter.dart';
import 'demo.dart';
import 'service.dart';

class NetWorkPrinterScreen extends StatefulWidget {
  @override
  _NetWorkPrinterScreenState createState() => _NetWorkPrinterScreenState();
}

class _NetWorkPrinterScreenState extends State<NetWorkPrinterScreen> {
  bool _isLoading = false;
  List<NetWorkPrinter> _printers = [];
  NetworkPrinterManager? _manager;
  List<int> _data = [];
  String _name = "default";

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
        title: Text("Network Printer Screen ${printProfiles.length}"),
        actions: [
          PopupMenuButton(
            itemBuilder: (_) => printProfiles
                .map(
                  (e) => PopupMenuItem(
                    enabled: e["key"] != _name,
                    child: Text("${e["key"]}"),
                    onTap: () {
                      setState(() {
                        _name = e["key"];
                      });
                    },
                  ),
                )
                .toList(),
          )
        ],
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
                    leading: Icon(Icons.cable),
                    onTap: () => _connect(printer),
                    trailing: printer.connected
                        ? Wrap(
                            children: [
                              IconButton(
                                  tooltip: 'ESC POS Command',
                                  onPressed: () => _startPrinter(1, printer),
                                  icon: Icon(Icons.print)),
                              IconButton(
                                  tooltip: 'Html Print',
                                  onPressed: () => _startPrinter(3, printer),
                                  icon: Icon(Icons.image)),
                            ],
                          )
                        : null,
                    selected: printer.connected,
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
    var printers = await NetworkPrinterManager.discover();
    setState(() {
      _isLoading = false;
      _printers = printers;
    });
  }

  Future _connect(NetWorkPrinter printer) async {
    var manager = NetworkPrinterManager(printer);
    await manager.connect();
    setState(() {
      _manager = manager;
      printer.connected = true;
    });
  }

  _startPrinter(int byteType, NetWorkPrinter printer) async {
    await _connect(printer);
    // if (_data.isEmpty) {
    final content = Demo.getShortReceiptContent();

    var stopwatch = Stopwatch()..start();
    List<int> data = [];
    var profile = await CapabilityProfile.load();
    if (byteType == 1) {
      data = await ESCPrinterService(null).getSamplePosBytes(
          paperSizeWidthMM: paperWidth,
          maxPerLine: charPerLine,
          profile: profile,
          name: _name);
    } else if (byteType == 2) {
      data = await ESCPrinterService(null).getPdfBytes(
          paperSizeWidthMM: paperWidth,
          maxPerLine: charPerLine,
          profile: profile,
          name: _name);
    } else if (byteType == 3) {
      var service = ESCPrinterService(await WebcontentConverter.contentToImage(
        content: content,
        executablePath: WebViewHelper.executablePath(),
      ));
      data = await service.getBytes(name: _name);
    }

    print("Start print data $_name");

    if (mounted) setState(() => _data = data);

    if (_manager != null) {
      print("isConnected ${_manager!.printer.connected}");
      await _manager!.writeBytes(_data, isDisconnect: true);
      WebcontentConverter.logger
          .info("completed executed in ${stopwatch.elapsed}");
    }
  }
}
