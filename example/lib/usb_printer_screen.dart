import 'package:image/image.dart' as img;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:webcontent_converter/webcontent_converter.dart';
import 'demo.dart';
import 'service.dart';
import 'widgets.dart';

class USBPrinterScreen extends StatefulWidget {
  const USBPrinterScreen({super.key});

  @override
  State<USBPrinterScreen> createState() => _USBPrinterScreenState();
}

class _USBPrinterScreenState extends State<USBPrinterScreen> {
  bool _isScanning = false;
  bool _isPrinting = false;
  List<USBPrinter> _printers = [];

  int _paperWidth = PaperSizeWidth.mm80;
  int _charPerLine = PaperSizeMaxPerLine.mm80;
  String _profileName = 'default';

  @override
  void initState() {
    super.initState();
    _scan();
  }

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  Future<void> _scan() async {
    setState(() {
      _isScanning = true;
      _printers = [];
    });
    try {
      final printers = await USBPrinterManager.discover();
      if (mounted) setState(() => _printers = printers);
    } catch (e) {
      if (mounted) showStatusSnackbar(context, 'Scan error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Print
  // ---------------------------------------------------------------------------

  Future<void> _print(_PrintMode mode, USBPrinter printer) async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);

    try {
      final profile = await CapabilityProfile.load(name: _profileName);
      final manager = USBPrinterManager(printer);
      await manager.connect();

      late List<int> data;
      switch (mode) {
        case _PrintMode.escPos:
          data = await ESCPrinterService(null).getSamplePosBytes(
            paperSizeWidthMM: _paperWidth,
            maxPerLine: _charPerLine,
            profile: profile,
            name: _profileName,
          );
          break;
        case _PrintMode.pdf:
          data = await ESCPrinterService(null).getPdfBytes(
            paperSizeWidthMM: _paperWidth,
            maxPerLine: _charPerLine,
            profile: profile,
            name: _profileName,
          );
          break;
        case _PrintMode.html:
          final content = Demo.getShortReceiptContent();
          final bytes = await WebcontentConverter.contentToImage(
            content: content,
            executablePath: WebViewHelper.executablePath(),
          );
          data = await ESCPrinterService(bytes).getBytes(
            paperSizeWidthMM: _paperWidth,
            maxPerLine: _charPerLine,
            profile: profile,
            name: _profileName,
          );
          break;
        case _PrintMode.tspl:
          await _tsplPrint(printer);
          return; // tspl handles its own flow
      }

      await manager.writeBytes(data);
      if (mounted) showStatusSnackbar(context, 'Printed to ${printer.name}');
    } catch (e) {
      if (mounted) showStatusSnackbar(context, 'Print error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _tsplPrint(USBPrinter printer) async {
    const int width = 105, height = 22, labelWidth = 35;
    try {
      final image = await ESCPrinterService(null)
          .generateLabel(width, height, labelWidth, 1.5, 3);
      if (image != null) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}${Platform.pathSeparator}receipt.png';
        await File(path).writeAsBytes(img.encodePng(image));
        if (mounted) {
          showStatusSnackbar(context, 'Label generated at $path');
        }
      }
    } catch (e) {
      if (mounted) showStatusSnackbar(context, 'TSPL error: $e', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: const Text('USB Printers'),
            actions: [
              if (_isScanning)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList.list(
              children: [
                PaperSettingsCard(
                  paperWidth: _paperWidth,
                  charPerLine: _charPerLine,
                  profileName: _profileName,
                  onPaperWidthChanged: (v) => setState(() => _paperWidth = v),
                  onCharPerLineChanged: (v) =>
                      setState(() => _charPerLine = v),
                  onProfileChanged: (v) => setState(() => _profileName = v),
                ),
                const SizedBox(height: 24),
                SectionTitle(
                    title: 'Connected Printers', isLoading: _isScanning),
                if (_printers.isEmpty && !_isScanning)
                  const EmptyState(
                      message: 'No USB printers found',
                      icon: Icons.usb_off),
                if (_printers.isEmpty && _isScanning)
                  const EmptyState(
                      message: 'Checking USB connections...',
                      icon: Icons.usb),
                ..._printers.map(_buildPrinterTile),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? null : _scan,
        icon: Icon(_isScanning ? Icons.hourglass_top : Icons.refresh),
        label: Text(_isScanning ? 'Scanning...' : 'Refresh'),
      ),
    );
  }

  Widget _buildPrinterTile(USBPrinter printer) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.usb, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(printer.name ?? 'Unknown',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(printer.address ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                PrintActionChip(
                  icon: Icons.receipt_long,
                  label: 'ESC/POS',
                  color: Colors.blue,
                  onPressed: () => _print(_PrintMode.escPos, printer),
                ),
                PrintActionChip(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF',
                  color: Colors.red,
                  onPressed: () => _print(_PrintMode.pdf, printer),
                ),
                PrintActionChip(
                  icon: Icons.language,
                  label: 'HTML',
                  color: Colors.orange,
                  onPressed: () => _print(_PrintMode.html, printer),
                ),
                PrintActionChip(
                  icon: Icons.qr_code,
                  label: 'TSPL',
                  color: Colors.purple,
                  onPressed: () => _print(_PrintMode.tspl, printer),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _PrintMode { escPos, pdf, html, tspl }
