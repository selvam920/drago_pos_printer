import 'dart:io';
import 'dart:math';
import 'package:drago_pos_printer/helpers/network_analyzer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {}

Future<String?> getIPAddress() async {
  int code = Random().nextInt(255);
  var dgSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  dgSocket.readEventsEnabled = true;
  dgSocket.broadcastEnabled = true;
  Future<InternetAddress> ret =
      dgSocket.timeout(const Duration(milliseconds: 100), onTimeout: (sink) {
    sink.close();
  }).expand<InternetAddress>((event) {
    if (event == RawSocketEvent.read) {
      Datagram? dg = dgSocket.receive();
      if (dg != null && dg.data.length == 1 && dg.data[0] == code) {
        dgSocket.close();
        return [dg.address];
      }
    }
    return [];
  }).first;

  dgSocket.send([code], InternetAddress("255.255.255.255"), dgSocket.port);
  return (await ret).address;
}

Future<String?> getDeviceIpAddress() async {
  try {
    final connectivityResult = await (Connectivity().checkConnectivity());
    String? currentIpAddress;

    if (connectivityResult.any((element) =>
        element == ConnectivityResult.wifi ||
        element == ConnectivityResult.ethernet)) {
      currentIpAddress = await getIPAddress();
    }

    if (connectivityResult.any((element) =>
        element == ConnectivityResult.mobile ||
        element == ConnectivityResult.vpn)) {
      for (var interface in await NetworkInterface.list()) {
        if (interface.name == 'wlan1') {
          currentIpAddress = interface.addresses.first.address;
        }
      }
    }
    return currentIpAddress;
  } catch (e) {
    return null;
  }
}

Future<List<String>> findNetworkPrinter({int port = 9100}) async {
  String? currentIpAddress = await getDeviceIpAddress();
  if (currentIpAddress != null) {
    final stream = NetworkAnalyzer.discover2(
      currentIpAddress.substring(0, currentIpAddress.lastIndexOf('.')),
      port,
      timeout: const Duration(milliseconds: 5000),
    );
    var results = await stream.toList();
    return [
      ...results
          .where((entry) => entry.exists)
          .toList()
          .map((e) => e.ip)
          .toList()
    ];
  } else {
    return [];
  }
}
