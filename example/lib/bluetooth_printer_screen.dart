import 'dart:async';
import 'package:flutter/material.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:webcontent_converter/webcontent_converter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'demo.dart';
import 'service.dart';
import 'widgets.dart';

class BluetoothPrinterScreen extends StatefulWidget {
  const BluetoothPrinterScreen({super.key});

  @override
  State<BluetoothPrinterScreen> createState() =>
      _BluetoothPrinterScreenState();
}

class _BluetoothPrinterScreenState extends State<BluetoothPrinterScreen> {
  bool _isScanning = false;
  bool _isPrinting = false;

  List<BluetoothPrinter> _bondedPrinters = [];
  List<BluetoothPrinter> _scannedPrinters = [];
  StreamSubscription<BluetoothPrinter>? _scanSub;

  int _paperWidth = PaperSizeWidth.mm80;
  int _charPerLine = PaperSizeMaxPerLine.mm80;
  String _profileName = 'default';

  final _manager = BluetoothPrinterManager(
      BluetoothPrinter(name: 'Scanner', address: '00:00:00:00:00:00'));

  @override
  void initState() {
    super.initState();
    _refreshBonded();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  Future<void> _refreshBonded() async {
    try {
      final list = await BluetoothPrinterManager.discover();
      if (mounted) setState(() => _bondedPrinters = list);
    } catch (e) {
      debugPrint('Bonded fetch error: $e');
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> _scan() async {
    await _requestPermissions();
    await _refreshBonded();

    setState(() {
      _isScanning = true;
      _scannedPrinters = [];
    });

    _scanSub?.cancel();
    _scanSub = _manager.scan().listen(
      (printer) {
        if (printer.name == null || printer.name!.isEmpty) return;
        if (!mounted) return;
        setState(() {
          final isDup = _scannedPrinters.any((p) => p.address == printer.address);
          final isBonded =
              _bondedPrinters.any((p) => p.address == printer.address);
          if (!isDup && !isBonded) _scannedPrinters.add(printer);
        });
      },
      onError: (_) => _stopScan(),
    );
  }

  void _stopScan() {
    _scanSub?.cancel();
    if (mounted) setState(() => _isScanning = false);
  }

  // ---------------------------------------------------------------------------
  // Pair
  // ---------------------------------------------------------------------------

  Future<void> _pair(BluetoothPrinter printer) async {
    try {
      await _manager.pair(printer);
      if (mounted) {
        showStatusSnackbar(
            context, 'Pairing request sent to ${printer.name}');
      }
      Future.delayed(const Duration(seconds: 5), _refreshBonded);
    } catch (e) {
      if (mounted) {
        showStatusSnackbar(context, 'Pairing failed: $e', isError: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Print
  // ---------------------------------------------------------------------------

  Future<void> _print(_PrintMode mode, BluetoothPrinter printer) async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);

    try {
      final profile = await CapabilityProfile.load(name: _profileName);
      final manager = BluetoothPrinterManager(printer);
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
      if (mounted) {
        showStatusSnackbar(context, 'Printed to ${printer.name}');
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
            title: const Text('Bluetooth Printers'),
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

                // -- Bonded --
                const SizedBox(height: 24),
                const SectionTitle(title: 'Bonded Devices'),
                if (_bondedPrinters.isEmpty)
                  const EmptyState(
                      message: 'No bonded printers',
                      icon: Icons.bluetooth_disabled),
                ..._bondedPrinters
                    .map((p) => _buildPrinterTile(p, bonded: true)),

                // -- Scanned --
                const SizedBox(height: 24),
                SectionTitle(
                    title: 'Nearby Devices', isLoading: _isScanning),
                if (_scannedPrinters.isEmpty && !_isScanning)
                  const EmptyState(
                      message: 'No devices found nearby',
                      icon: Icons.bluetooth_searching),
                if (_scannedPrinters.isEmpty && _isScanning)
                  const EmptyState(
                      message: 'Scanning...', icon: Icons.radar),
                ..._scannedPrinters
                    .map((p) => _buildPrinterTile(p, bonded: false)),
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

  Widget _buildPrinterTile(BluetoothPrinter printer, {required bool bonded}) {
    final theme = Theme.of(context);
    final accentColor =
        bonded ? theme.colorScheme.primary : theme.colorScheme.tertiary;

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
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                bonded ? Icons.bluetooth_connected : Icons.bluetooth,
                color: accentColor,
              ),
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
            if (bonded)
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
              )
            else
              FilledButton.tonalIcon(
                onPressed: () => _pair(printer),
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Pair'),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PrintMode { escPos, html }
