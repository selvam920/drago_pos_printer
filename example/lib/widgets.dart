import 'package:material_ui/material_ui.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'service.dart';

/// Reusable paper size settings card used across all printer screens.
class PaperSettingsCard extends StatefulWidget {
  final int paperWidth;
  final int charPerLine;
  final String profileName;
  final ValueChanged<int> onPaperWidthChanged;
  final ValueChanged<int> onCharPerLineChanged;
  final ValueChanged<String> onProfileChanged;

  const PaperSettingsCard({
    super.key,
    required this.paperWidth,
    required this.charPerLine,
    required this.profileName,
    required this.onPaperWidthChanged,
    required this.onCharPerLineChanged,
    required this.onProfileChanged,
  });

  @override
  State<PaperSettingsCard> createState() => _PaperSettingsCardState();
}

class _PaperSettingsCardState extends State<PaperSettingsCard> {
  late String _selectedSize;
  bool _showCustom = false;
  final _widthCtrl = TextEditingController();
  final _charsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedSize = _sizeFromWidth(widget.paperWidth);
    if (_selectedSize == 'Custom') {
      _showCustom = true;
      _widthCtrl.text = widget.paperWidth.toString();
      _charsCtrl.text = widget.charPerLine.toString();
    }
  }

  String _sizeFromWidth(int w) {
    if (w == PaperSizeWidth.mm58) return '58mm';
    if (w == PaperSizeWidth.mm80_Old) return '80mm Old';
    if (w == PaperSizeWidth.mm80) return '80mm';
    return 'Custom';
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _charsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Settings',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedSize,
              decoration: InputDecoration(
                labelText: 'Paper Size',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              items: ['58mm', '80mm Old', '80mm', 'Custom']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _selectedSize = val;
                  _showCustom = val == 'Custom';
                  switch (val) {
                    case '58mm':
                      widget.onPaperWidthChanged(PaperSizeWidth.mm58);
                      widget.onCharPerLineChanged(PaperSizeMaxPerLine.mm58);
                      break;
                    case '80mm Old':
                      widget.onPaperWidthChanged(PaperSizeWidth.mm80_Old);
                      widget.onCharPerLineChanged(PaperSizeMaxPerLine.mm80_Old);
                      break;
                    case '80mm':
                      widget.onPaperWidthChanged(PaperSizeWidth.mm80);
                      widget.onCharPerLineChanged(PaperSizeMaxPerLine.mm80);
                      break;
                    case 'Custom':
                      _widthCtrl.text = widget.paperWidth.toString();
                      _charsCtrl.text = widget.charPerLine.toString();
                      break;
                  }
                });
              },
            ),
            if (_showCustom) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _widthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Width (dots)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (v) =>
                          widget.onPaperWidthChanged(int.tryParse(v) ?? 0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _charsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Chars / Line',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (v) =>
                          widget.onCharPerLineChanged(int.tryParse(v) ?? 0),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: widget.profileName,
              decoration: InputDecoration(
                labelText: 'Printer Profile',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              items: printProfiles
                  .map<DropdownMenuItem<String>>((p) => DropdownMenuItem(
                        value: p['key'] as String,
                        child: Text(p['key'] as String),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) widget.onProfileChanged(val);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state placeholder.
class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.search_off,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Small chip-style action button used in printer cards.
class PrintActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  const PrintActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: c),
      label: Text(label, style: TextStyle(fontSize: 11, color: c)),
      backgroundColor: c.withValues(alpha: 0.08),
      side: BorderSide(color: c.withValues(alpha: 0.2)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onPressed: onPressed,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Section header for printer lists.
class SectionTitle extends StatelessWidget {
  final String title;
  final bool isLoading;

  const SectionTitle({super.key, required this.title, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title,
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5)),
          if (isLoading) ...[
            const SizedBox(width: 10),
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ],
      ),
    );
  }
}

/// Shows a themed floating snackbar with status.
/// Label job options shared by the printer screens.
class LabelSettings {
  LabelLanguage language = LabelLanguage.tspl;
  PrinterDpi dpi = PrinterDpi.dpi203;
  LabelCompression compression = LabelCompression.compressed;
  LabelMedia media = LabelMedia.gap;
  double widthMm = 50;
  double heightMm = 25;
  double gapMm = 2;
}

/// Language / DPI / compression / size pickers for [LabelSettings].
class LabelSettingsCard extends StatefulWidget {
  const LabelSettingsCard({super.key, required this.settings, this.onChanged});
  final LabelSettings settings;

  /// Called after any option changes (e.g. to show language-specific tools).
  final VoidCallback? onChanged;

  @override
  State<LabelSettingsCard> createState() => _LabelSettingsCardState();
}

class _LabelSettingsCardState extends State<LabelSettingsCard> {
  LabelSettings get s => widget.settings;

  /// Common roll sizes (width x height mm).
  static const _presets = <(double, double)>[
    (25, 15),
    (38, 25),
    (40, 30),
    (50, 25),
    (50, 30),
    (58, 40),
    (75, 50),
    (100, 50),
    (100, 150),
  ];

  late final _w = TextEditingController(text: _num(s.widthMm));
  late final _h = TextEditingController(text: _num(s.heightMm));
  late final _g = TextEditingController(text: _num(s.gapMm));

  static String _num(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _g.dispose();
    super.dispose();
  }

  void _pick((double, double) size) {
    setState(() {
      s.widthMm = size.$1;
      s.heightMm = size.$2;
      _w.text = _num(size.$1);
      _h.text = _num(size.$2);
    });
  }

  Widget _segmented<T>(String label, List<(T, String)> options, T value,
      ValueChanged<T> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final (v, text) in options)
                ButtonSegment(value: v, label: Text(text)),
            ],
            selected: {value},
            onSelectionChanged: (sel) {
              setState(() => onChanged(sel.first));
              widget.onChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _mmField(String label, TextEditingController ctrl,
      ValueChanged<double> onChanged) {
    return Expanded(
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'mm',
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: (v) {
          final d = double.tryParse(v);
          if (d != null && d > 0) onChanged(d);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dots = '${s.dpi.mmToDots(s.widthMm)} x '
        '${s.dpi.mmToDots(s.heightMm)} dots';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.label_outline,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Label',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(dots, style: theme.textTheme.labelSmall),
            ]),
            const SizedBox(height: 16),
            _segmented<LabelLanguage>(
              'Language',
              const [
                (LabelLanguage.tspl, 'TSPL'),
                (LabelLanguage.escPos, 'ESC/POS'),
                (LabelLanguage.cpcl, 'CPCL'),
              ],
              s.language,
              (v) => s.language = v,
            ),
            _segmented<PrinterDpi>(
              'Printer DPI',
              const [
                (PrinterDpi.dpi203, '203 dpi'),
                (PrinterDpi.dpi300, '300 dpi'),
              ],
              s.dpi,
              (v) => s.dpi = v,
            ),
            _segmented<LabelMedia>(
              'Media',
              const [
                (LabelMedia.gap, 'Gap'),
                (LabelMedia.blackMark, 'Black mark'),
                (LabelMedia.continuous, 'Continuous'),
              ],
              s.media,
              (v) => s.media = v,
            ),
            Text(
              'Blank label + roll keeps feeding = wrong language or media. '
              'Raster-only label printers (e.g. LD0801 / DP27) need ESC/POS.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _segmented<LabelCompression>(
              'Compression',
              const [
                (LabelCompression.none, 'None'),
                (LabelCompression.compressed, 'Compressed'),
              ],
              s.compression,
              (v) => s.compression = v,
            ),
            Text('Label size', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in _presets)
                  ChoiceChip(
                    label: Text('${_num(p.$1)}x${_num(p.$2)}'),
                    selected: s.widthMm == p.$1 && s.heightMm == p.$2,
                    onSelected: (_) => _pick(p),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              _mmField('Width', _w, (v) => setState(() => s.widthMm = v)),
              const SizedBox(width: 8),
              _mmField('Height', _h, (v) => setState(() => s.heightMm = v)),
              const SizedBox(width: 8),
              _mmField('Gap', _g, (v) => s.gapMm = v),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Barcode / QR options shared by the Receipt and Label tabs.
class CodeSettings {
  CodeType type = CodeType.qr;
  String data = 'https://github.com/selvam920/drago_pos_printer';
  String caption = 'Scan me';

  /// Send the code as a picture instead of the printer's barcode command.
  /// Needed for raster-only printers (e.g. LD0801) that ignore native codes.
  bool asImage = false;

  /// Sample data that is valid for [type].
  static String sample(CodeType type) => switch (type) {
        CodeType.qr => 'https://github.com/selvam920/drago_pos_printer',
        CodeType.code128 => 'SKU-12345',
        CodeType.ean13 => '890123456789',
        CodeType.code39 => 'ITEM42',
      };
}

/// Type chips, data / caption fields and the "as image" switch.
class CodeSettingsCard extends StatefulWidget {
  const CodeSettingsCard({
    super.key,
    required this.settings,
    this.showCaption = false,
    this.showAsImage = true,
  });

  final CodeSettings settings;
  final bool showCaption;
  final bool showAsImage;

  @override
  State<CodeSettingsCard> createState() => _CodeSettingsCardState();
}

class _CodeSettingsCardState extends State<CodeSettingsCard> {
  CodeSettings get s => widget.settings;
  late final _data = TextEditingController(text: s.data);
  late final _caption = TextEditingController(text: s.caption);
  String? _error;

  @override
  void initState() {
    super.initState();
    _validate();
  }

  @override
  void dispose() {
    _data.dispose();
    _caption.dispose();
    super.dispose();
  }

  void _validate() {
    try {
      ESCPrinterService.validateCode(s.type, s.data);
      _error = null;
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.qr_code_2, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Barcode / QR',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in CodeType.values)
                  ChoiceChip(
                    label: Text(t.title),
                    selected: s.type == t,
                    onSelected: (_) => setState(() {
                      s.type = t;
                      s.data = CodeSettings.sample(t);
                      _data.text = s.data;
                      _validate();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _data,
              decoration: InputDecoration(
                labelText: 'Data',
                errorText: _error,
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() {
                s.data = v.trim();
                _validate();
              }),
            ),
            if (widget.showCaption) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _caption,
                decoration: InputDecoration(
                  labelText: 'Caption (above the code)',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (v) => s.caption = v,
              ),
            ],
            if (widget.showAsImage)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: s.asImage,
                onChanged: (v) => setState(() => s.asImage = v),
                title: const Text('Print code as image'),
                subtitle: const Text(
                    'Turn on for raster-only printers that print nothing '
                    'for native barcode / QR commands.'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows why a job was held back and returns true when [status] blocks it
/// (head open, out of paper...). Unknown -- the printer didn't answer, as
/// most receipt printers don't -- lets the job go.
bool warnIfNotReady(BuildContext context, PrinterReadiness status) {
  if (!status.blocksPrint) return false;
  showStatusSnackbar(context, '${status.message} -- not printed',
      isError: true);
  return true;
}

void showStatusSnackbar(BuildContext context, String message,
    {bool isError = false}) {
  final theme = Theme.of(context);
  final bg = isError
      ? theme.colorScheme.errorContainer
      : theme.colorScheme.inverseSurface;
  final fg = isError
      ? theme.colorScheme.onErrorContainer
      : theme.colorScheme.onInverseSurface;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: fg,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: fg)),
          ),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: bg,
      duration: Duration(seconds: isError ? 4 : 2),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
}
