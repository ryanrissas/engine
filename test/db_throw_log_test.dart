// strength_set.rpe_source and the throw-log helpers: additive on an existing
// install, appended after a session's sets, and read back with the session.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _dbPath(String name) async =>
    p.join(await databaseFactory.getDatabasesPath(), name);

void main() {
  const name = 'throw_log.db';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(await _dbPath(name));
  });

  test('rpe_source exists, throws append after sets, inputs read back',
      () async {
    await databaseFactory.deleteDatabase(await _dbPath(name));
    await LocalDb.close();
    LocalDb.dbName = name;
    final db = await LocalDb.instance;

    final cols = [
      for (final r in await db.rawQuery('PRAGMA table_info(strength_set)'))
        r['name'],
    ];
    expect(cols, contains('rpe_source'));

    await db.insert('sessions', {
      'id': 'bb1',
      'start_ts': 1790000000,
      'end_ts': 1790003600,
      'type': 'baseball',
      'status': 'done',
      'duration_min': 60,
      'created_at': 1790003600,
    });
    await LocalDb.saveStrengthSets('bb1', [
      {
        'exercise_key': 'back_squat',
        'set_index': 1,
        'reps': 5,
        'load_kg': 100.0,
        'rpe': 8,
        'rpe_source': 'user',
        'at_ts': 1790000100,
      },
    ]);
    await LocalDb.addThrowEntries('bb1', [
      {'exercise_key': 'throw_bullpen', 'set_index': 1, 'reps': 35, 'rpe': 9,
          'rpe_source': 'user'},
    ]);
    await LocalDb.addThrowEntries('bb1', [
      {'exercise_key': 'throw_long_toss', 'set_index': 1, 'reps': 20, 'rpe': 7,
          'rpe_source': 'user'},
    ]);
    final rows = await LocalDb.strengthSets('bb1');
    expect([for (final r in rows) r['seq']], [0, 1, 2]);
    expect(rows[1]['exercise_key'], 'throw_bullpen');

    await LocalDb.deleteStrengthRow('bb1', 2);
    expect(await LocalDb.strengthSets('bb1'), hasLength(2));

    final inputs = await LocalDb.loadInputsSince(1789990000);
    expect(inputs.sessions.single['type'], 'baseball');
    expect(inputs.sets['bb1'], hasLength(2));
    expect((await LocalDb.loadInputsSince(1790000001)).sessions, isEmpty);
  });
}
