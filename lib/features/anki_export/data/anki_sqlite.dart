import 'package:sqlite3/common.dart';

import 'anki_sqlite_native.dart'
    if (dart.library.js_interop) 'anki_sqlite_web.dart'
    as platform;

Future<CommonSqlite3> loadAnkiSqlite() => platform.loadAnkiSqlite();
