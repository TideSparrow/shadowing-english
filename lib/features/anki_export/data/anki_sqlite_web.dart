import 'package:flutter/services.dart';
import 'package:sqlite3/wasm.dart';

Future<CommonSqlite3>? _loaded;

Future<CommonSqlite3> loadAnkiSqlite() => _loaded ??= _load();

Future<CommonSqlite3> _load() async {
  try {
    final ByteData bytes = await rootBundle.load('assets/anki/sqlite3.wasm');
    return await WasmSqlite3.load(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } catch (_) {
    _loaded = null;
    rethrow;
  }
}
