import 'package:flutter/material.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';

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
                Icon(Icons.settings, size: 18, color: theme.colorScheme.primary),
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
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
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
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
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
