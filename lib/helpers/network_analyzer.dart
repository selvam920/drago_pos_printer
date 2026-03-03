/*
 * ping_discover_network
 * Created by Andrey Ushakov
 * 
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:io';

/// [NetworkAnalyzer] class returns instances of [NetworkAddress].
///
/// Found ip addresses will have [exists] == true field.
class NetworkAddress {
  NetworkAddress(this.ip, this.exists);
  bool exists;
  String ip;
}

/// Pings a given subnet (xxx.xxx.xxx) on a given port using [discover2] method.
class NetworkAnalyzer {
  /// Pings a given [subnet] (xxx.xxx.xxx) on a given [port].
  ///
  /// Pings IP:PORT all at once
  static Stream<NetworkAddress> discover2(
    String subnet,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (port < 1 || port > 65535) {
      throw 'Incorrect port';
    }

    final out = StreamController<NetworkAddress>();
    final futures = <Future<Socket>>[];
    int pending = 255;

    void _checkDone() {
      pending--;
      if (pending <= 0) {
        out.close();
      }
    }

    for (int i = 1; i < 256; ++i) {
      final host = '$subnet.$i';
      final Future<Socket> f = _ping(host, port, timeout);
      futures.add(f);
      f.then((socket) {
        socket.destroy();
        if (!out.isClosed) {
          out.sink.add(NetworkAddress(host, true));
        }
        _checkDone();
      }).catchError((dynamic e) {
        if (e is! SocketException) {
          _checkDone();
          return;
        }

        // Check if connection timed out or we got one of predefined errors
        if (e.osError == null || _errorCodes.contains(e.osError?.errorCode)) {
          if (!out.isClosed) {
            out.sink.add(NetworkAddress(host, false));
          }
        }
        // Error 23,24: Too many open files in system — skip silently
        _checkDone();
      });
    }

    return out.stream;
  }

  static Future<Socket> _ping(String host, int port, Duration timeout) {
    return Socket.connect(host, port, timeout: timeout).then((socket) {
      return socket;
    });
  }

  // 13: Connection failed (OS Error: Permission denied)
  // 49: Bind failed (OS Error: Can't assign requested address)
  // 61: OS Error: Connection refused
  // 64: Connection failed (OS Error: Host is down)
  // 65: No route to host
  // 101: Network is unreachable
  // 111: Connection refused
  // 113: No route to host
  // <empty>: SocketException: Connection timed out
  static final _errorCodes = [13, 49, 61, 64, 65, 101, 111, 113];
}
