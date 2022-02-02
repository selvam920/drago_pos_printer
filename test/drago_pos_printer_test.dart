import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';

void main() {
  const MethodChannel channel = MethodChannel('drago_pos_printer');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect('20', '42');
  });
}
