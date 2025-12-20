import 'dart:async';
import 'package:drago_pos_printer/models/pos_printer.dart';
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
  String _name = "default";
  StreamSubscription<POSPrinter>? _scanSubscription;

  int paperWidth = PaperSizeWidth.mm80;
  int charPerLine = PaperSizeMaxPerLine.mm80;
  String _selectedPaperSize = '80mm';

  final TextEditingController _customWidthController = TextEditingController();
  final TextEditingController _customCharsController = TextEditingController();
  bool showCustom = false;

  // Dummy manager for scanning
  final _manager = NetworkPrinterManager(
      NetWorkPrinter(id: '0', name: 'Manager', address: '0.0.0.0', type: 0));

  @override
  void initState() {
    super.initState();
    // Auto-start scan
    _scan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _customWidthController.dispose();
    _customCharsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          "Network Printers",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        elevation: 0,
        actions: [
          PopupMenuButton(
            icon: Icon(Icons.print_disabled, color: Colors.white),
            tooltip: 'Select Profile',
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
          ),
          if (_isLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo,
        onPressed: _isLoading ? _stopScan : _scan,
        icon: Icon(_isLoading ? Icons.stop : Icons.search, color: Colors.white),
        label: Text(
          _isLoading ? "Stop Scanning" : "Scan Network",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSettingsCard(),
            SizedBox(height: 24),
            Row(
              children: [
                Text(
                  "Found Printers",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo[900],
                  ),
                ),
                if (_isLoading) ...[
                  SizedBox(width: 12),
                  SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ]
              ],
            ),
            SizedBox(height: 12),
            if (_printers.isEmpty && !_isLoading)
              _buildEmptyState("No network printers found.")
            else if (_printers.isEmpty && _isLoading)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(child: Text("Scanning network...")),
              ),
            ..._printers.map((printer) => _buildPrinterCard(printer)).toList(),
            SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: EdgeInsets.all(20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        message,
        style: TextStyle(color: Colors.grey[600]),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Printer Settings",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            SizedBox(height: 16),
            DropdownButtonHideUnderline(
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Paper Size',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                child: DropdownButton<String>(
                  value: _selectedPaperSize,
                  isDense: true,
                  items: ['58mm', '80mmOld', '80mm', 'Custom'].map((item) {
                    return DropdownMenuItem(value: item, child: Text(item));
                  }).toList(),
                  onChanged: (String? selected) {
                    if (selected == null) return;
                    setState(() {
                      _selectedPaperSize = selected;
                      showCustom = selected == 'Custom';
                      switch (selected) {
                        case "58mm":
                          paperWidth = PaperSizeWidth.mm58;
                          charPerLine = PaperSizeMaxPerLine.mm58;
                          break;
                        case "80mmOld":
                          paperWidth = PaperSizeWidth.mm80_Old;
                          charPerLine = PaperSizeMaxPerLine.mm80_Old;
                          break;
                        case "80mm":
                          paperWidth = PaperSizeWidth.mm80;
                          charPerLine = PaperSizeMaxPerLine.mm80;
                          break;
                        case "Custom":
                          break;
                      }
                      if (showCustom) {
                        _customWidthController.text = paperWidth.toString();
                        _customCharsController.text = charPerLine.toString();
                      }
                    });
                  },
                ),
              ),
            ),
            if (showCustom) ...[
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customWidthController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Width (mm)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) => paperWidth = int.tryParse(val) ?? 0,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _customCharsController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Chars/Line',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) => charPerLine = int.tryParse(val) ?? 0,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterCard(NetWorkPrinter printer) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: EdgeInsets.all(16),
        leading: Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.cable, color: Colors.indigo),
        ),
        title: Text(
          printer.name ?? "Unknown Device",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          printer.address ?? "",
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionButton(
              icon: Icons.receipt_long,
              label: "TEST",
              onPressed: () => _print(1, printer),
              color: Colors.blue,
            ),
            SizedBox(width: 8),
            _ActionButton(
              icon: Icons.html,
              label: "HTML",
              onPressed: () => _print(3, printer),
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  void _stopScan() {
    _scanSubscription?.cancel();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _scan() async {
    setState(() {
      _isLoading = true;
      _printers = [];
    });

    _scanSubscription?.cancel();
    try {
      _scanSubscription = _manager.scan().listen((printer) {
        if (printer is NetWorkPrinter) {
          setState(() {
            if (!_printers.any((p) => p.address == printer.address)) {
              _printers.add(printer);
            }
          });
        }
      }, onError: (err) {
        print("Scan error: $err");
        _stopScan();
      }, onDone: () {
        _stopScan();
      });
    } catch (e) {
      print("Error starting scan: $e");
      _stopScan();
    }
  }

  Future<void> _print(int byteType, NetWorkPrinter printer) async {
    try {
      var manager = NetworkPrinterManager(printer);
      await manager.connect();

      final content = Demo.getShortReceiptContent();
      var profile = await CapabilityProfile.load();
      late List<int> data;

      if (byteType == 1) {
        data = await ESCPrinterService(null).getSamplePosBytes(
            paperSizeWidthMM: paperWidth,
            maxPerLine: charPerLine,
            profile: profile,
            name: _name);
      } else if (byteType == 3) {
        var service =
            ESCPrinterService(await WebcontentConverter.contentToImage(
          content: content,
          executablePath: WebViewHelper.executablePath(),
        ));
        data = await service.getBytes(name: _name);
      } else {
        return;
      }

      await manager.writeBytes(data);
      await manager.disconnect();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Print error: $e"), backgroundColor: Colors.red),
      );
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;

  const _ActionButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
