import 'dart:async';
import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:flutter/material.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:webcontent_converter/webcontent_converter.dart';
import 'demo.dart';
import 'service.dart';
import 'widgets.dart';

class NetWorkPrinterScreen extends StatefulWidget {
  const NetWorkPrinterScreen({super.key});

  @override
  State<NetWorkPrinterScreen> createState() => _NetWorkPrinterScreenState();
}

class _NetWorkPrinterScreenState extends State<NetWorkPrinterScreen> {
  bool _isScanning = false;
  bool _isPrinting = false;
  List<NetWorkPrinter> _printers = [];
  StreamSubscription<POSPrinter>? _scanSub;

  int _paperWidth = PaperSizeWidth.mm80;
  int _charPerLine = PaperSizeMaxPerLine.mm80;
  String _profileName = 'default';

  final _manager = NetworkPrinterManager(
      NetWorkPrinter(id: '0', name: 'Scanner', address: '0.0.0.0', type: 0));

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------

  void _scan() {
    _scanSub?.cancel();
    setState(() {
      _isScanning = true;
      _printers = [];
    });

    _scanSub = _manager.scan().listen(
      (printer) {
        if (printer is NetWorkPrinter && mounted) {
          setState(() {
            if (!_printers.any((p) => p.address == printer.address)) {
              _printers.add(printer);
            }
          });
        }
      },
      onError: (_) => _stopScan(),
      onDone: _stopScan,
    );
  }

  void _stopScan() {
    _scanSub?.cancel();
    if (mounted) setState(() => _isScanning = false);
  }

  // ---------------------------------------------------------------------------
  // Print
  // ---------------------------------------------------------------------------

  Future<void> _print(_PrintMode mode, NetWorkPrinter printer) async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);

    try {
      final manager = NetworkPrinterManager(printer);
      await manager.connect();

      final profile = await CapabilityProfile.load(name: _profileName);
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
      }

      await manager.writeBytes(data);
      await manager.disconnect();

      if (mounted) {
        showStatusSnackbar(context, 'Printed successfully to ${printer.address}');
      }
    } catch (e) {
      if (mounted) showStatusSnackbar(context, 'Print error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
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
            title: const Text('Network Printers'),
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
                    title: 'Found Printers', isLoading: _isScanning),
                if (_printers.isEmpty && !_isScanning)
                  const EmptyState(
                      message: 'No network printers found', icon: Icons.wifi_off),
                if (_printers.isEmpty && _isScanning)
                  const EmptyState(
                      message: 'Scanning network...', icon: Icons.radar),
                ..._printers.map(_buildPrinterTile),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? _stopScan : _scan,
        icon: Icon(_isScanning ? Icons.stop : Icons.search),
        label: Text(_isScanning ? 'Stop' : 'Scan'),
      ),
    );
  }

  Widget _buildPrinterTile(NetWorkPrinter printer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.print,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(printer.name ?? 'Unknown',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(printer.address ?? '',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
                ],
              ),
            ),
            Wrap(
              spacing: 6,
              children: [
                PrintActionChip(
                  icon: Icons.receipt_long,
                  label: 'ESC/POS',
                  color: Colors.blue,
                  onPressed: () => _print(_PrintMode.escPos, printer),
                ),
                PrintActionChip(
                  icon: Icons.language,
                  label: 'HTML',
                  color: Colors.orange,
                  onPressed: () => _print(_PrintMode.html, printer),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _PrintMode { escPos, html }
