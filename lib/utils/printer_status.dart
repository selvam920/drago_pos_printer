import 'dart:typed_data';

/// What a printer said when asked if it can print.
enum PrinterReadiness {
  ready,
  paperOut,
  coverOpen,
  paused,
  error,

  /// The printer did not answer the status query -- many cheap printers
  /// never do, so this is not a reason to block printing.
  unknown,
}

extension PrinterReadinessText on PrinterReadiness {
  bool get blocksPrint =>
      this != PrinterReadiness.ready && this != PrinterReadiness.unknown;

  String get message {
    switch (this) {
      case PrinterReadiness.ready:
        return 'Printer is ready';
      case PrinterReadiness.paperOut:
        return 'Printer is out of paper / labels';
      case PrinterReadiness.coverOpen:
        return 'Printer cover / head is open';
      case PrinterReadiness.paused:
        return 'Printer is paused';
      case PrinterReadiness.error:
        return 'Printer reports an error';
      case PrinterReadiness.unknown:
        return 'Printer status not available';
    }
  }
}

/// Status queries in the language the job is written in.
class PrinterStatusQuery {
  PrinterStatusQuery._(this.query, this._parse);

  final Uint8List query;
  final PrinterReadiness Function(int byte) _parse;

  PrinterReadiness parse(Uint8List? reply) =>
      reply == null || reply.isEmpty ? PrinterReadiness.unknown : _parse(reply.last);

  /// TSPL `<ESC>!?`: one status byte, 0 = ready.
  static final tspl = PrinterStatusQuery._(
    Uint8List.fromList([0x1B, 0x21, 0x3F]),
    (b) {
      if (b == 0 || b == 0x20) return PrinterReadiness.ready; // 0x20 = printing
      if (b & 0x01 != 0) return PrinterReadiness.coverOpen;
      if (b & 0x0C != 0) return PrinterReadiness.paperOut; // paper / ribbon
      if (b & 0x10 != 0) return PrinterReadiness.paused;
      return PrinterReadiness.error;
    },
  );

  /// ESC/POS `DLE EOT 4` (roll paper sensor), then `DLE EOT 2` would give
  /// the cover; the paper sensor alone covers the common case.
  static final escPos = PrinterStatusQuery._(
    Uint8List.fromList([0x10, 0x04, 0x04]),
    (b) {
      // Every DLE EOT reply has bit 1 set and bit 7 clear; anything else is
      // not a status byte (some printers echo) -- treat as unknown.
      if (b & 0x12 != 0x12 || b & 0x81 != 0) return PrinterReadiness.unknown;
      if (b & 0x60 != 0) return PrinterReadiness.paperOut;
      return PrinterReadiness.ready;
    },
  );

  /// TSPL jobs are plain ASCII commands (`SIZE`, `CLS`, ...); ESC/POS jobs
  /// start with a control byte.
  static PrinterStatusQuery forJob(List<int> bytes) {
    final first = bytes.firstWhere((b) => b != 0x0D && b != 0x0A, orElse: () => 0);
    final isAsciiCommand = first >= 0x41 && first <= 0x5A;
    return isAsciiCommand ? tspl : escPos;
  }
}
