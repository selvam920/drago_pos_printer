import 'dart:async';
import 'dart:io';

import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webcontent_converter/webcontent_converter.dart';

import 'demo.dart';
import 'service.dart';
import 'widgets.dart';

enum Connection { usb, bluetooth, network }

/// What the selected printer is used for -- decides which tabs show.
enum PrinterUse { receipt, label, both }

extension on Connection {
  String get label => switch (this) {
        Connection.usb => 'USB',
        Connection.bluetooth => 'Bluetooth',
        Connection.network => 'Network',
      };
  IconData get icon => switch (this) {
        Connection.usb => Icons.usb,
        Connection.bluetooth => Icons.bluetooth,
        Connection.network => Icons.lan_outlined,
      };
}

/// One screen for every connection: pick a printer, say what it's used for,
/// then print from the Receipt and/or Label tab.
class PrinterStudioScreen extends StatefulWidget {
  const PrinterStudioScreen({super.key});

  @override
  State<PrinterStudioScreen> createState() => _PrinterStudioScreenState();
}

class _PrinterStudioScreenState extends State<PrinterStudioScreen> {
  static final bool _hasBluetooth = Platform.isAndroid || Platform.isIOS;
  static final bool _hasUsb = Platform.isAndroid || Platform.isWindows;

  late Connection _connection = _hasUsb ? Connection.usb : Connection.network;
  PrinterUse _use = PrinterUse.both;

  final Map<Connection, List<POSPrinter>> _printers = {
    for (final c in Connection.values) c: [],
  };
  final List<BluetoothPrinter> _nearby = [];
  POSPrinter? _selected;

  bool _scanning = false;
  bool _printing = false;
  StreamSubscription? _scanSub;
  String? _lastResult;
  bool _lastOk = true;

  // Receipt options
  int _paperWidth = PaperSizeWidth.mm80;
  int _charPerLine = PaperSizeMaxPerLine.mm80;
  String _profileName = 'default';

  // Label options
  final _label = LabelSettings();

  // Barcode / QR (one set per tab: receipts often use native codes, labels
  // always print the code as part of the label image).
  final _receiptCode = CodeSettings();
  final _labelCode = CodeSettings()
    ..type = CodeType.code128
    ..data = 'SKU-12345';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  List<Connection> get _connections => [
        if (_hasUsb) Connection.usb,
        if (_hasBluetooth) Connection.bluetooth,
        Connection.network,
      ];

  // --------------------------------------------------------------- discovery

  Future<void> _refresh() async {
    _scanSub?.cancel();
    setState(() {
      _scanning = true;
      _nearby.clear();
    });
    try {
      switch (_connection) {
        case Connection.usb:
          _printers[Connection.usb] = await USBPrinterManager.discover();
          _stopScanning();
          break;
        case Connection.bluetooth:
          await [
            Permission.bluetoothScan,
            Permission.bluetoothConnect,
            Permission.location,
          ].request();
          _printers[Connection.bluetooth] =
              await BluetoothPrinterManager.discover();
          _scanSub = BluetoothPrinterManager(
                  BluetoothPrinter(name: 'scan', address: '00:00:00:00:00:00'))
              .scan()
              .listen((p) {
            final known = [..._printers[Connection.bluetooth]!, ..._nearby]
                .any((e) => e.address == p.address);
            if (!known && (p.name ?? '').isNotEmpty && mounted) {
              setState(() => _nearby.add(p));
            }
          }, onError: (_) => _stopScanning());
          Future.delayed(const Duration(seconds: 15), _stopScanning);
          break;
        case Connection.network:
          final manual = _printers[Connection.network]!
              .where((p) => p.id == 'manual')
              .toList();
          _printers[Connection.network] = [...manual];
          _scanSub = NetworkPrinterManager(NetWorkPrinter(
                  id: 'scan', name: 'scan', address: '0.0.0.0', type: 0))
              .scan()
              .listen((p) {
            final list = _printers[Connection.network]!;
            if (!list.any((e) => e.address == p.address) && mounted) {
              setState(() => list.add(p));
            }
          }, onError: (_) => _stopScanning(), onDone: _stopScanning);
          break;
      }
    } catch (e) {
      _report(false, 'Scan failed: $e');
      _stopScanning();
    }
    if (mounted) setState(() {});
  }

  void _stopScanning() {
    _scanSub?.cancel();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _addNetworkPrinter() async {
    final ctrl = TextEditingController();
    final ip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add network printer'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'IP address',
            hintText: '192.168.1.50  (port 9100)',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Add')),
        ],
      ),
    );
    final value = ip?.trim() ?? '';
    if (value.isEmpty) return;
    final printer =
        NetWorkPrinter(id: 'manual', name: 'Printer $value', address: value);
    setState(() {
      _printers[Connection.network]!.insert(0, printer);
      _selected = printer;
    });
  }

  Future<void> _pair(BluetoothPrinter p) async {
    try {
      await BluetoothPrinterManager(p).pair(p);
      _report(true, 'Pairing request sent to ${p.name}');
      Future.delayed(const Duration(seconds: 5), _refresh);
    } catch (e) {
      _report(false, 'Pairing failed: $e');
    }
  }

  // ------------------------------------------------------------------ print

  void _report(bool ok, String message) {
    if (!mounted) return;
    setState(() {
      _lastOk = ok;
      _lastResult = message;
    });
    showStatusSnackbar(context, message, isError: !ok);
  }

  /// Connect -> ask the printer if it's ready -> write -> disconnect.
  Future<void> _send(String what, Future<List<int>> Function() build) async {
    final printer = _selected;
    if (printer == null || _printing) return;
    setState(() => _printing = true);
    final dynamic manager = switch (printer) {
      USBPrinter p => USBPrinterManager(p),
      BluetoothPrinter p => BluetoothPrinterManager(p),
      NetWorkPrinter p => NetworkPrinterManager(p),
      _ => null,
    };
    try {
      if (manager == null) throw Exception('Unsupported printer');
      final bytes = await build();
      await manager.connect();
      final PrinterReadiness status = await manager.checkStatus(bytes);
      if (status.blocksPrint) {
        _report(false, '${status.message} -- $what not printed');
        return;
      }
      await manager.writeBytes(bytes);
      _report(true, '$what sent to ${printer.name} (${bytes.length} bytes)');
    } catch (e) {
      _report(false, '$what failed: $e');
    } finally {
      try {
        await manager?.disconnect();
      } catch (_) {}
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<CapabilityProfile> _profile() =>
      CapabilityProfile.load(name: _profileName);

  Future<List<int>> _receiptTest() async =>
      ESCPrinterService(null).getReceiptTestBytes(
        paperSizeWidthMM: _paperWidth,
        maxPerLine: _charPerLine,
        profile: await _profile(),
        name: _profileName,
      );

  Future<List<int>> _sampleReceipt() async =>
      ESCPrinterService(null).getSamplePosBytes(
        paperSizeWidthMM: _paperWidth,
        maxPerLine: _charPerLine,
        profile: await _profile(),
        name: _profileName,
      );

  Future<List<int>> _pdfReceipt() async => ESCPrinterService(null).getPdfBytes(
        paperSizeWidthMM: _paperWidth,
        maxPerLine: _charPerLine,
        profile: await _profile(),
        name: _profileName,
      );

  Future<List<int>> _htmlReceipt() async {
    final image = await WebcontentConverter.contentToImage(
      content: Demo.getShortReceiptContent(),
      executablePath: WebViewHelper.executablePath(),
    );
    return ESCPrinterService(image).getBytes(
      paperSizeWidthMM: _paperWidth,
      maxPerLine: _charPerLine,
      profile: await _profile(),
      name: _profileName,
    );
  }

  Future<List<int>> _sampleLabel() => ESCPrinterService(null).getLabelBytes(
        language: _label.language,
        dpi: _label.dpi,
        compression: _label.compression,
        widthMm: _label.widthMm,
        heightMm: _label.heightMm,
        gapMm: _label.gapMm,
        media: _label.media,
      );

  Future<List<int>> _receiptCodeJob() async =>
      ESCPrinterService(null).getReceiptCodeBytes(
        type: _receiptCode.type,
        data: _receiptCode.data,
        asImage: _receiptCode.asImage,
        paperSizeWidthMM: _paperWidth,
        maxPerLine: _charPerLine,
        profile: await _profile(),
        name: _profileName,
      );

  Future<List<int>> _codeLabel() => ESCPrinterService(null).getCodeLabelBytes(
        type: _labelCode.type,
        data: _labelCode.data,
        caption: _labelCode.caption,
        language: _label.language,
        dpi: _label.dpi,
        compression: _label.compression,
        widthMm: _label.widthMm,
        heightMm: _label.heightMm,
        gapMm: _label.gapMm,
        media: _label.media,
      );

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, IconData, Widget)>[
      if (_use != PrinterUse.label)
        ('Receipt', Icons.receipt_long_outlined, _receiptTab()),
      if (_use != PrinterUse.receipt)
        ('Label', Icons.label_outline, _labelTab()),
    ];

    final printersPane = _printersPane();
    final printPane = DefaultTabController(
      key: ValueKey(_use), // rebuild tabs when the set changes
      length: tabs.length,
      child: Column(
        children: [
          if (tabs.length > 1)
            TabBar(tabs: [
              for (final t in tabs) Tab(icon: Icon(t.$2), text: t.$1),
            ]),
          Expanded(
            child: tabs.length > 1
                ? TabBarView(children: [for (final t in tabs) t.$3])
                : tabs.first.$3,
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Printer'),
        actions: [
          IconButton(
            tooltip: 'Rescan',
            onPressed: _scanning ? null : _refresh,
            icon: _scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final body = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 380, child: printersPane),
                  const VerticalDivider(width: 1),
                  Expanded(child: printPane),
                ],
              )
            : Column(
                children: [
                  // Printer list collapses to the selection on phones.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: c.maxHeight * 0.45),
                    child: printersPane,
                  ),
                  const Divider(height: 1),
                  Expanded(child: printPane),
                ],
              );
        return Column(
          children: [
            Expanded(child: body),
            _resultBar(),
          ],
        );
      }),
    );
  }

  Widget _printersPane() {
    final theme = Theme.of(context);
    final list = _printers[_connection]!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<Connection>(
          segments: [
            for (final c in _connections)
              ButtonSegment(value: c, icon: Icon(c.icon), label: Text(c.label)),
          ],
          selected: {_connection},
          onSelectionChanged: (s) {
            setState(() {
              _connection = s.first;
              _selected = null;
            });
            _refresh();
          },
        ),
        const SizedBox(height: 12),
        Text('Use as', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        SegmentedButton<PrinterUse>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
                value: PrinterUse.receipt,
                icon: Icon(Icons.receipt_long_outlined),
                label: Text('Receipt')),
            ButtonSegment(
                value: PrinterUse.label,
                icon: Icon(Icons.label_outline),
                label: Text('Label')),
            ButtonSegment(
                value: PrinterUse.both,
                icon: Icon(Icons.dashboard_outlined),
                label: Text('Both')),
          ],
          selected: {_use},
          onSelectionChanged: (s) => setState(() => _use = s.first),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SectionTitle(
                  title: '${_connection.label} printers', isLoading: _scanning),
            ),
            if (_connection == Connection.network)
              TextButton.icon(
                onPressed: _addNetworkPrinter,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add IP'),
              ),
          ],
        ),
        if (list.isEmpty)
          EmptyState(
            message: _scanning ? 'Searching...' : 'No printers found',
            icon: _connection.icon,
          ),
        for (final p in list) _printerTile(p),
        if (_nearby.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SectionTitle(title: 'Nearby (not paired)'),
          for (final p in _nearby)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.bluetooth_searching),
                title: Text(p.name ?? 'Unknown'),
                subtitle: Text(p.address ?? ''),
                trailing: FilledButton.tonal(
                    onPressed: () => _pair(p), child: const Text('Pair')),
              ),
            ),
        ],
      ],
    );
  }

  Widget _printerTile(POSPrinter p) {
    final theme = Theme.of(context);
    final selected = identical(p, _selected) ||
        (_selected != null &&
            _selected!.name == p.name &&
            _selected!.address == p.address);
    final details = <String>[
      if ((p.address ?? '').isNotEmpty && p.address != p.name) p.address!,
      if (p is BluetoothPrinter && p.connected) 'Connected',
      if (p is BluetoothPrinter && p.battery != null) 'Battery ${p.battery}%',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        onTap: () => setState(() {
          _selected = p;
          // Raster-only label printers: TSPL would only feed blank labels.
          if (RegExp(r'LD0801|DP27', caseSensitive: false)
              .hasMatch(p.name ?? '')) {
            _label.language = LabelLanguage.escPos;
            _use = PrinterUse.label;
          }
        }),
        leading: Icon(
          selected ? Icons.check_circle : _connection.icon,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Text(p.name ?? 'Unknown',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: details.isEmpty ? null : Text(details.join('  ·  ')),
      ),
    );
  }

  Widget _actions(List<(String, IconData, Future<List<int>> Function())> a) {
    final enabled = _selected != null && !_printing;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (title, icon, build) in a)
          FilledButton.tonalIcon(
            onPressed: enabled ? () => _send(title, build) : null,
            icon: Icon(icon, size: 18),
            label: Text(title),
          ),
      ],
    );
  }

  Widget _hintIfNoPrinter() => _selected == null
      ? const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Select a printer to print.'),
        )
      : const SizedBox.shrink();

  Widget _receiptTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hintIfNoPrinter(),
        _actions([
          ('Test page', Icons.fact_check_outlined, _receiptTest),
          ('Sample receipt', Icons.receipt_long, _sampleReceipt),
          ('PDF receipt', Icons.picture_as_pdf_outlined, _pdfReceipt),
          ('HTML receipt', Icons.language, _htmlReceipt),
          ('Barcode / QR', Icons.qr_code_2, _receiptCodeJob),
        ]),
        const SizedBox(height: 16),
        PaperSettingsCard(
          paperWidth: _paperWidth,
          charPerLine: _charPerLine,
          profileName: _profileName,
          onPaperWidthChanged: (v) => setState(() => _paperWidth = v),
          onCharPerLineChanged: (v) => setState(() => _charPerLine = v),
          onProfileChanged: (v) => setState(() => _profileName = v),
        ),
        const SizedBox(height: 12),
        CodeSettingsCard(settings: _receiptCode),
      ],
    );
  }

  Widget _labelTab() {
    final tspl = _label.language == LabelLanguage.tspl;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hintIfNoPrinter(),
        _actions([
          ('Sample label', Icons.style_outlined, _sampleLabel),
          ('Barcode / QR label', Icons.qr_code_2, _codeLabel),
          if (tspl) ...[
            (
              'Calibrate',
              Icons.straighten,
              () async => LabelCommands.tsplCalibrate(media: _label.media)
            ),
            (
              'Self test',
              Icons.build_outlined,
              () async => LabelCommands.tsplSelfTest()
            ),
            (
              'Text test',
              Icons.text_fields,
              () async => LabelCommands.tsplTextTest(
                    widthMm: _label.widthMm,
                    heightMm: _label.heightMm,
                    gapMm: _label.gapMm,
                    media: _label.media,
                    dpi: _label.dpi,
                  )
            ),
          ],
        ]),
        const SizedBox(height: 16),
        LabelSettingsCard(
          settings: _label,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        CodeSettingsCard(
          settings: _labelCode,
          showCaption: true,
          showAsImage: false, // labels are always one image
        ),
      ],
    );
  }

  Widget _resultBar() {
    final theme = Theme.of(context);
    if (_printing) return const LinearProgressIndicator(minHeight: 3);
    if (_lastResult == null) return const SizedBox.shrink();
    final color = _lastOk ? theme.colorScheme.primary : theme.colorScheme.error;
    return Material(
      color: color.withValues(alpha: 0.08),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(_lastOk ? Icons.check_circle_outline : Icons.error_outline,
                  color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_lastResult!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
