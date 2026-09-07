import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/services/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Points [AppDatabase] at a fresh in-memory SQLite for the current test, and
/// tears it down afterwards.
///
/// [AppDatabase] is a singleton holding one open connection for the life of
/// the app, so without the close each test would inherit the previous one's
/// rows — and a migration test would find its work already done.
void useInMemoryDatabase() {
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    await AppDatabase.instance.close();
    AppDatabase.factoryOverride = databaseFactoryFfi;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.factoryOverride = null;
    AppDatabase.pathOverride = null;
  });
}
