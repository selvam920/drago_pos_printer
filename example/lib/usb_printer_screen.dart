import 'package:image/image.dart' as img;
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

  int paperWidth = PaperSizeWidth.mm80;
  int charPerLine = PaperSizeMaxPerLine.mm80;
  String _selectedPaperSize = '80mm';

  final TextEditingController _customWidthController = TextEditingController();
  final TextEditingController _customCharsController = TextEditingController();
  bool showCustom = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
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
          "USB Printers",
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
        onPressed: _isLoading ? null : _scan,
        icon: Icon(_isLoading ? Icons.hourglass_top : Icons.refresh,
            color: Colors.white),
        label: Text(
          _isLoading ? "Scanning..." : "Refresh",
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
                  "Connected Printers",
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
              _buildEmptyState("No USB printers found.")
            else if (_printers.isEmpty && _isLoading)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(child: Text("Checking USB connections...")),
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

  Widget _buildPrinterCard(USBPrinter printer) {
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
          child: Icon(Icons.usb, color: Colors.indigo),
        ),
        title: Text(
          printer.name ?? "Unknown Device",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          printer.address ?? "",
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            IconButton(
              tooltip: 'TSPL Label',
              onPressed: () => _tsplPrint(printer),
              icon: Icon(Icons.qr_code),
              color: Colors.purple,
            ),
            IconButton(
              tooltip: 'Test Print',
              onPressed: () => _startPrinter(1, printer),
              icon: Icon(Icons.receipt_long),
              color: Colors.blue,
            ),
            IconButton(
              tooltip: 'PDF Print',
              onPressed: () => _startPrinter(2, printer),
              icon: Icon(Icons.picture_as_pdf),
              color: Colors.red,
            ),
            IconButton(
              tooltip: 'HTML Print',
              onPressed: () => _startPrinter(3, printer),
              icon: Icon(Icons.html),
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  _scan() async {
    setState(() {
      _isLoading = true;
      _printers = [];
    });
    USBPrinterManager.discover().then((val) {
      setState(() {
        _isLoading = false;
        _printers = val;
      });
    }).catchError((err) {
      setState(() {
        _isLoading = false;
      });
      var snackBar = SnackBar(
        content: Text(err.toString()),
        backgroundColor: Colors.red,
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    });
  }

  _startPrinter(int byteType, USBPrinter printer) async {
    try {
      var profile = await CapabilityProfile.load();
      var manager = USBPrinterManager(printer);
      await manager.connect();

      final content = Demo.getShortReceiptContent();
      var bytes = byteType == 1
          ? await ESCPrinterService(null).getSamplePosBytes(
              paperSizeWidthMM: paperWidth,
              maxPerLine: charPerLine,
              profile: profile)
          : byteType == 2
              ? await ESCPrinterService(null).getPdfBytes(
                  paperSizeWidthMM: paperWidth,
                  maxPerLine: charPerLine,
                  profile: profile)
              : (await WebcontentConverter.contentToImage(
                  content: content,
                  executablePath: WebViewHelper.executablePath(),
                ))
                  .toList();
      List<int> data = [];
      if (byteType == 3) {
        var service = ESCPrinterService(Uint8List.fromList(bytes));
        data = await service.getBytes(
          paperSizeWidthMM: paperWidth,
          maxPerLine: charPerLine,
        );
        if (bytes.length > 0) {
          var dir = await getTemporaryDirectory();
          var path = dir.path + "\\receipt.jpg";
          File file = File(path);
          await file.writeAsBytes(bytes);
        }
      } else
        data = bytes;

      await manager.writeBytes(data);
    } catch (e) {
      var snackBar = SnackBar(
        content: Text(e.toString()),
        backgroundColor: Colors.red,
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }

  _tsplPrint(USBPrinter printer) async {
    try {
      int width = 105;
      int height = 22;
      int labelWidth = 35;

      var image = await ESCPrinterService(null)
          .generateLabel(width, height, labelWidth, 1.5, 3);

      if (image != null) {
        var dir = await getTemporaryDirectory();
        var path = dir.path + "\\receipt.png";
        File file = File(path);
        await file.writeAsBytes(img.encodePng(image));

        // TODO: Implement actual TSPL sending logic if required,
        // currently code only generated image.
        // Logic from original file seemed incomplete/commented out for sending.
        // Alerting user of success generation.

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Label generated at $path"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("TSPL Error: $e"), backgroundColor: Colors.red),
      );
    }
  }
}
