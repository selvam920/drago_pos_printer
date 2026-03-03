import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:drago_pos_printer/helpers/network_analyzer.dart';
import 'package:drago_pos_printer/models/pos_printer.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';
import 'network_service.dart';
import 'printer_manager.dart';

/// Network Printer
class NetworkPrinterManager extends PrinterManager {
  Socket? socket;

  /// Whether the socket is currently connected.
  bool get isConnected => socket != null;

  /// Maximum bytes to write per chunk over the network.
  ///
  /// Sending the entire byte array at once can overflow the printer's
  /// internal network buffer, causing data loss or incomplete prints.
  /// 4096 bytes is a safe default for most receipt printers.
  static const int defaultChunkSize = 4096;

  /// Delay between sending chunks (in milliseconds).
  ///
  /// Gives the printer time to process each chunk before receiving more.
  /// Increase this if your printer drops data on large print jobs.
  static const int defaultChunkDelayMs = 5;

  NetworkPrinterManager(POSPrinter printer) {
    super.printer = printer;
  }

  /// [connect] let you connect to a network printer.
  ///
  /// Sets TCP_NODELAY to disable Nagle's algorithm so small ESC/POS
  /// commands are sent immediately without waiting for more data.
  @override
  Future connect({Duration? timeout = const Duration(seconds: 5)}) async {
    // Avoid opening multiple connections.
    if (isConnected) return;

    try {
      socket = await Socket.connect(
        printer.address,
        printer.port ?? 9100,
        timeout: timeout,
      );
      // Disable Nagle's algorithm — send ESC/POS commands immediately
      // instead of buffering them. Critical for small writes like status
      // queries and cut commands.
      socket!.setOption(SocketOption.tcpNoDelay, true);
    } catch (e) {
      socket = null;
      return Future.error('Failed to connect to ${printer.address}:${printer.port ?? 9100} — $e');
    }
  }

  /// [discover] let you explore all netWork printer in your network.
  ///
  /// [port] defaults to 9100 (standard RAW/JetDirect port).
  static Future<List<NetWorkPrinter>> discover({int port = 9100}) async {
    var results = await findNetworkPrinter(port: port);
    return [
      ...results
          .map((e) => NetWorkPrinter(id: e, name: e, address: e, type: 0))
          .toList(),
    ];
  }

  /// [discoverStream] returns a Stream that yields printers as they are
  /// found on the network, instead of waiting for the full scan to finish.
  ///
  /// [port] defaults to 9100 (standard RAW/JetDirect port).
  static Stream<NetWorkPrinter> discoverStream({
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 5000),
  }) async* {
    String? currentIpAddress = await getDeviceIpAddress();
    if (currentIpAddress == null) return;

    final subnet =
        currentIpAddress.substring(0, currentIpAddress.lastIndexOf('.'));
    final stream = NetworkAnalyzer.discover2(
      subnet,
      port,
      timeout: timeout,
    );

    await for (final entry in stream) {
      if (entry.exists) {
        yield NetWorkPrinter(
          id: entry.ip,
          name: entry.ip,
          address: entry.ip,
          type: 0,
        );
      }
    }
  }

  /// [writeBytes] writes raw data to the network socket in chunks.
  ///
  /// Data is sent in [chunkSize]-byte pieces with a small delay and flush
  /// between each chunk. This prevents the printer's internal buffer from
  /// overflowing, which can cause:
  /// - Incomplete prints / missing lines
  /// - Printer treating data as multiple "pages" (A4-height output)
  /// - Garbled output from buffer wrap-around
  ///
  /// [chunkSize] — max bytes per write (default: 4096).
  /// [chunkDelayMs] — delay in ms between chunks (default: 5).
  @override
  Future writeBytes(
    List<int> data, {
    int chunkSize = defaultChunkSize,
    int chunkDelayMs = defaultChunkDelayMs,
  }) async {
    if (socket == null) {
      return Future.error(
          'Socket is not connected. Call connect() before writeBytes().');
    }

    try {
      final bytes = Uint8List.fromList(data);
      final totalLength = bytes.length;

      if (totalLength <= chunkSize) {
        // Small payload — send in one go.
        socket!.add(bytes);
        await socket!.flush();
      } else {
        // Large payload — send in chunks with flush + delay.
        int offset = 0;
        while (offset < totalLength) {
          final end =
              (offset + chunkSize > totalLength) ? totalLength : offset + chunkSize;
          socket!.add(bytes.sublist(offset, end));
          await socket!.flush();
          offset = end;

          // Small delay to let the printer process the chunk.
          if (offset < totalLength && chunkDelayMs > 0) {
            await Future.delayed(Duration(milliseconds: chunkDelayMs));
          }
        }
      }
    } catch (e) {
      return Future.error('Failed to write bytes: $e');
    }
  }

  /// [disconnect] flushes pending data and closes the socket.
  ///
  /// [timeout] — optional delay after closing (useful for printers that
  /// need time to finish processing before a reconnect).
  @override
  Future disconnect({Duration? timeout}) async {
    try {
      await socket?.flush();
      await socket?.close();
    } catch (_) {
      // Ignore errors during cleanup.
    } finally {
      socket = null;
    }

    if (timeout != null) {
      await Future.delayed(timeout);
    }
  }

  /// [scan] yields printers as they are discovered on the network.
  ///
  /// Uses streaming discovery so results appear immediately instead of
  /// waiting for all 255 IPs to be checked.
  @override
  Stream<POSPrinter> scan() {
    return discoverStream(port: printer.port ?? 9100);
  }

  @override
  Future<void> pair(POSPrinter device) async {
    // Network printers do not require pairing.
  }
}
