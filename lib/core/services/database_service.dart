import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:fixnum/fixnum.dart';
import '../models/player_info.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'bluemetersea.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE players(
        uid TEXT PRIMARY KEY,
        name TEXT,
        professionId INTEGER,
        combatPower INTEGER,
        level INTEGER,
        rankLevel INTEGER,
        critical INTEGER,
        lucky INTEGER,
        maxHp TEXT,
        hp TEXT,
        last_seen INTEGER
      )
    ''');
  }

  Future<void> savePlayer(PlayerInfo player) async {
    final db = await database;

    await db.transaction((txn) async {
      // Check if player exists
      final List<Map<String, dynamic>> maps = await txn.query(
        'players',
        where: 'uid = ?',
        whereArgs: [player.uid.toString()],
      );

      if (maps.isEmpty) {
        // Insert new
        await txn.insert('players', {
          'uid': player.uid.toString(),
          'name': player.name,
          'professionId': player.professionId,
          'combatPower': player.combatPower,
          'level': player.level,
          'rankLevel': player.rankLevel,
          'critical': player.critical,
          'lucky': player.lucky,
          'maxHp': player.maxHp?.toString(),
          'hp': player.hp?.toString(),
          'last_seen': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        // Update existing, only non-null fields
        final updateValues = <String, dynamic>{
          'last_seen': DateTime.now().millisecondsSinceEpoch,
        };

        if (player.name != null) updateValues['name'] = player.name;
        if (player.professionId != null && player.professionId != 0)
          updateValues['professionId'] = player.professionId;
        if (player.combatPower != null && player.combatPower != 0)
          updateValues['combatPower'] = player.combatPower;
        if (player.seasonStrength != null && player.seasonStrength != 0)
          updateValues['seasonStrength'] = player.seasonStrength;
        if (player.level != null && player.level != 0)
          updateValues['level'] = player.level;
        if (player.rankLevel != null && player.rankLevel != 0)
          updateValues['rankLevel'] = player.rankLevel;
        if (player.critical != null && player.critical != 0)
          updateValues['critical'] = player.critical;
        if (player.lucky != null && player.lucky != 0)
          updateValues['lucky'] = player.lucky;
        if (player.maxHp != null && player.maxHp != Int64.ZERO)
          updateValues['maxHp'] = player.maxHp.toString();
        // Hp changes too often, maybe we don't need to persist it strictly or maybe we do?
        // User asked to persist player info. HP is transient. But let's keep it if we have it?
        // Actually, if we restart app, HP is likely 0 or full.
        // But updating DB for every HP change (damage packet) is VERY expensive.

        await txn.update(
          'players',
          updateValues,
          where: 'uid = ?',
          whereArgs: [player.uid.toString()],
        );
      }

      // Cleanup
      await txn.rawDelete(
        'DELETE FROM players WHERE uid NOT IN (SELECT uid FROM players ORDER BY last_seen DESC LIMIT 100)',
      );
    });
  }

  Future<PlayerInfo?> getPlayer(Int64 uid) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'players',
      where: 'uid = ?',
      whereArgs: [uid.toString()],
    );

    if (maps.isEmpty) return null;

    final map = maps.first;
    return PlayerInfo(
      uid: Int64.parseInt(map['uid'] as String),
      name: map['name'] as String?,
      professionId: map['professionId'] as int?,
      combatPower: map['combatPower'] as int?,
      seasonStrength: map['seasonStrength'] as int?,
      level: map['level'] as int?,
      rankLevel: map['rankLevel'] as int?,
      critical: map['critical'] as int?,
      lucky: map['lucky'] as int?,
      maxHp: map['maxHp'] != null
          ? Int64.parseInt(map['maxHp'] as String)
          : null,
      hp: map['hp'] != null ? Int64.parseInt(map['hp'] as String) : null,
    );
  }
}
