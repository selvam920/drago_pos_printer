import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:webcontent_converter/webcontent_converter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'demo.dart';
import 'service.dart';

class BluetoothPrinterScreen extends StatefulWidget {
  @override
  _BluetoothPrinterScreenState createState() => _BluetoothPrinterScreenState();
}

class _BluetoothPrinterScreenState extends State<BluetoothPrinterScreen> {
  bool _isLoading = false;

  List<BluetoothPrinter> _bondedPrinters = [];
  List<BluetoothPrinter> _scannedPrinters = [];
  StreamSubscription<BluetoothPrinter>? _scanSubscription;

  int paperWidth = PaperSizeWidth.mm80;
  int charPerLine = PaperSizeMaxPerLine.mm80;
  String _selectedPaperSize = '80mm';

  final TextEditingController _customWidthController = TextEditingController();
  final TextEditingController _customCharsController = TextEditingController();
  bool showCustom = false;

  // Dummy manager instance for scanning since method is instance-based
  final _manager = BluetoothPrinterManager(
      BluetoothPrinter(name: 'Manager', address: '00:00:00:00:00:00'));

  @override
  void initState() {
    super.initState();
    _refreshBondedDevices();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _customWidthController.dispose();
    _customCharsController.dispose();
    super.dispose();
  }

  Future<void> _refreshBondedDevices() async {
    try {
      var val = await BluetoothPrinterManager.discover();
      setState(() {
        _bondedPrinters = val;
      });
    } catch (err) {
      print("Error getting bonded: $err");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          "Bluetooth Printers",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        elevation: 0,
        actions: [
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
          _isLoading ? "Stop Scanning" : "Scan Devices",
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
            Text(
              "Bonded Devices",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo[900],
              ),
            ),
            SizedBox(height: 12),
            if (_bondedPrinters.isEmpty)
              _buildEmptyState("No bonded printers found."),
            ..._bondedPrinters
                .map((printer) => _buildPrinterCard(printer, isBonded: true))
                .toList(),
            SizedBox(height: 24),
            Row(
              children: [
                Text(
                  "Available Devices",
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
            if (_scannedPrinters.isEmpty && !_isLoading)
              _buildEmptyState("No devices found nearby.")
            else if (_scannedPrinters.isEmpty && _isLoading)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(child: Text("Scanning...")),
              ),
            ..._scannedPrinters
                .map((printer) => _buildPrinterCard(printer, isBonded: false))
                .toList(),
            SizedBox(height: 80), // Fab spacing
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
                          // Keep current or set defaults
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

  Widget _buildPrinterCard(BluetoothPrinter printer, {required bool isBonded}) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: EdgeInsets.all(16),
        leading: Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isBonded
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.indigo.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.print,
            color: isBonded ? Colors.green : Colors.indigo,
          ),
        ),
        title: Text(
          printer.name ?? "Unknown Device",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text(
              printer.address ?? "",
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (!isBonded) ...[
              SizedBox(height: 4),
              Text(
                "Tap 'Link' to pair",
                style: TextStyle(fontSize: 12, color: Colors.indigoAccent),
              ),
            ]
          ],
        ),
        trailing: isBonded
            ? Row(
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
              )
            : IconButton(
                onPressed: () => _pairDevice(printer),
                icon: Icon(Icons.link, color: Colors.indigo),
                tooltip: "Pair Device",
              ),
      ),
    );
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    print("Permissions: $statuses");
  }

  void _stopScan() {
    _scanSubscription?.cancel();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _scan() async {
    await _requestPermissions();

    setState(() {
      _isLoading = true;
      _scannedPrinters = [];
    });

    // Refresh bonded list
    await _refreshBondedDevices();

    // Start scanning
    _scanSubscription?.cancel();
    try {
      _scanSubscription = _manager.scan().listen((printer) {
        if (printer.name == null || printer.name!.isEmpty) return;

        setState(() {
          bool alreadyInScanned =
              _scannedPrinters.any((p) => p.address == printer.address);
          bool alreadyBonded =
              _bondedPrinters.any((p) => p.address == printer.address);

          if (!alreadyInScanned && !alreadyBonded) {
            _scannedPrinters.add(printer);
          }
        });
      }, onError: (err) {
        print("Scan error: $err");
        _stopScan();
      });
    } catch (e) {
      print("Error starting scan: $e");
      _stopScan();
    }
  }

  Future<void> _pairDevice(BluetoothPrinter printer) async {
    try {
      // Use the manager instance to pair.
      // Note: BluetoothPrinterManager.pair takes the device as arg.
      await _manager.pair(printer);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Pairing request sent to ${printer.name}"),
          backgroundColor: Colors.green,
        ),
      );

      // Delay to allow pairing to process then refresh
      Future.delayed(Duration(seconds: 5), () => _refreshBondedDevices());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Pairing failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _print(int byteType, BluetoothPrinter printer) async {
    try {
      var profile = await CapabilityProfile.load();
      var manager = BluetoothPrinterManager(printer);
      await manager.connect();

      late List<int> data;
      if (byteType == 1) {
        data = await ESCPrinterService(null).getSamplePosBytes(
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
      } else {
        return;
      }

      await manager.writeBytes(data);
      // await manager.disconnect(); // Optional, depending on printer behavior
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
