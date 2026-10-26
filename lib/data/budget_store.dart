import 'package:sqflite/sqflite.dart';

import '../engine/budget.dart';
import 'app_database.dart';

/// The user's [Budget], one JSON row in `app_meta`. Read by the app and by
/// the 10 pm background run, so both see the same plan.
class BudgetStore {
  BudgetStore({AppDatabase? database}) : _db = database ?? AppDatabase();

  final AppDatabase _db;
  static const _key = 'budget';

  Future<Budget> load() async {
    final db = await _db.database;
    final rows = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: [_key],
      limit: 1,
    );
    if (rows.isEmpty) return const Budget();
    return Budget.fromJson(rows.first['value'] as String);
  }

  Future<void> save(Budget budget) async {
    final db = await _db.database;
    await db.insert('app_meta', {
      'key': _key,
      'value': budget.toJson(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
