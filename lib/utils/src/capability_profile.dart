import 'dart:convert' show json;
import 'package:flutter/services.dart' show rootBundle;

List<Map> printProfiles = [];
Map printCapabilities = {};

class CodePage {
  CodePage(this.id, this.name);
  int id;
  String name;
}

class CapabilityProfile {
  CapabilityProfile._internal(this.name, this.codePages);

  /// [ensureProfileLoaded]
  /// this method will cache the profile json into data which will
  /// speed up the next loop and searching profile
  static Future ensureProfileLoaded({String? path}) async {
    /// check where this global capabilities is empty then load capabilities.json
    /// else do nothing
    if (printCapabilities.isEmpty == true) {
      final content = await rootBundle.loadString(
          path ?? 'packages/drago_pos_printer/assets/capabilities.json');
      var _capabilities = json.decode(content);
      printCapabilities = Map.from(_capabilities);

      _capabilities['profiles'].forEach((k, v) {
        printProfiles.add({
          'key': k,
          'vendor': v['vendor'] is String ? v['vendor'] : '',
          'model': v['model'] is String ? v['model'] : '',
          'description': v['description'] is String ? v['description'] : '',
        });
      });

      /// assert that the capabilities will be not empty
      assert(printCapabilities.isNotEmpty);
    } else {
      print("capabilities.length is already loaded");
    }
  }

  /// Public factory
  static Future<CapabilityProfile> load({String name = 'default'}) async {
    await ensureProfileLoaded();

    var profile = printCapabilities['profiles'][name];

    if (profile == null) {
      throw Exception("The CapabilityProfile '$name' does not exist");
    }

    List<CodePage> list = [];
    profile['codePages'].forEach((k, v) {
      list.add(CodePage(int.parse(k), v));
    });

    // Call the private constructor
    return CapabilityProfile._internal(name, list);
  }

  String name;
  List<CodePage> codePages;

  int getCodePageId(String? codePage) {
    if (codePages.length == 0) {
      throw Exception("The CapabilityProfile isn't initialized");
    }

    return codePages
        .firstWhere((cp) => cp.name == codePage,
            orElse: () => throw Exception(
                "Code Page '$codePage' isn't defined for this profile"))
        .id;
  }

  static Future<List<dynamic>> getAvailableProfiles() async {
    /// ensure the capabilities is not empty
    await ensureProfileLoaded();

    var _profiles = printCapabilities['profiles'];

    List<dynamic> res = [];

    _profiles.forEach((k, v) {
      res.add({
        'key': k,
        'vendor': v['vendor'] is String ? v['vendor'] : '',
        'model': v['model'] is String ? v['model'] : '',
        'description': v['description'] is String ? v['description'] : '',
      });
    });

    return res;
  }
}
