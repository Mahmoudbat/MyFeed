
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String deleteAfterImportKey = 'delete_after_import';
  static const String deleteAfterExportKey = 'delete_after_export';

  Future<bool> getDeleteAfterImport() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(deleteAfterImportKey) ?? false;
  }

  Future<void> setDeleteAfterImport(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(deleteAfterImportKey, value);
  }

  Future<bool> getDeleteAfterExport() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(deleteAfterExportKey) ?? false;
  }

  Future<void> setDeleteAfterExport(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(deleteAfterExportKey, value);
  }
}
