import 'package:flutter/material.dart';
import 'package:drago_pos_printer/drago_pos_printer.dart';

import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// ensure printer profile is loaded
  await CapabilityProfile.ensureProfileLoaded();
  print("ensured");
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: HomeScreen());
  }
}
