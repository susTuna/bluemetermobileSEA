import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/player_info.dart';
import '../models/monster_info.dart';
import '../models/dps_data.dart';
import '../services/database_service.dart';
import '../services/logger_service.dart';

class DataStorage extends ChangeNotifier {
  static final DataStorage _instance = DataStorage._internal();
  factory DataStorage() => _instance;
  DataStorage._internal();

  final LoggerService _logger = LoggerService();

  Int64 _currentPlayerUuid = Int64.ZERO;
  Int64 get currentPlayerUuid => _currentPlayerUuid;
  
  set currentPlayerUuid(Int64 value) {
    if (_currentPlayerUuid != value) {
      _currentPlayerUuid = value;
      _persistCurrentPlayerUuid(value);
      notifyListeners();
    }
  }

  Future<void> _persistCurrentPlayerUuid(Int64 uuid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_player_uuid', uuid.toString());
    } catch (e) {
      _logger.error("Error persisting CurrentPlayerUUID", error: e);
    }
  }
  
  final Map<Int64, PlayerInfo> _playerInfoDatas = {};
  final Map<Int64, MonsterInfo> _monsterInfoDatas = {};
  final Map<Int64, DpsData> _fullDpsDatas = {};

  void clearMonsters() {
    _monsterInfoDatas.clear();
    notifyListeners();
  }

  // Combat Timer Logic
  DateTime? _lastActionTime;
  DateTime? _combatStartTime;
  bool _isCombatActive = false;
  Duration combatTimeout = const Duration(seconds: 15);

  Duration get currentCombatDuration {
    if (_combatStartTime == null) return Duration.zero;
    if (_isCombatActive) {
      return DateTime.now().difference(_combatStartTime!);
    }
    if (_lastActionTime != null) {
      return _lastActionTime!.difference(_combatStartTime!);
    }
    return Duration.zero;
  }

  void checkTimeout() {
    if (_isCombatActive && _lastActionTime != null) {
      if (DateTime.now().difference(_lastActionTime!) > combatTimeout) {
        _isCombatActive = false;
        notifyListeners();
      }
    }
  }

  void _onAction() {
    final now = DateTime.now();
    
    // Check for timeout first to handle the case where we are "active" but timed out
    if (_isCombatActive && _lastActionTime != null && now.difference(_lastActionTime!) > combatTimeout) {
      _isCombatActive = false;
    }

    if (!_isCombatActive) {
      // Start new combat
      reset(resetTimer: false); // Don't reset timer fields here, we set them below
      _isCombatActive = true;
      _combatStartTime = now;
    }
    _lastActionTime = now;
  }

  Map<Int64, PlayerInfo> get playerInfoDatas => Map.unmodifiable(_playerInfoDatas);
  Map<Int64, MonsterInfo> get monsterInfoDatas => Map.unmodifiable(_monsterInfoDatas);
  
  // Filter DPS datas to only include entities that are identified as players (exist in playerInfoDatas)
  // This hides monsters/NPCs from the DPS list.
  Map<Int64, DpsData> get fullDpsDatas {
    final filtered = <Int64, DpsData>{};
    _fullDpsDatas.forEach((key, value) {
      // Always include current player, even if info not loaded yet
      if (key == _currentPlayerUuid) {
        filtered[key] = value;
      } else if (_playerInfoDatas.containsKey(key)) {
        final info = _playerInfoDatas[key];
        // Only include if has a valid profession ID (monsters usually don't)
        if (info != null && info.professionId != null && info.professionId != 0) {
          filtered[key] = value;
        }
      }
    });
    return Map.unmodifiable(filtered);
  }

  void updatePlayerInfo(PlayerInfo info) {
    _playerInfoDatas[info.uid] = info;
    _notFoundUids.remove(info.uid);
    DatabaseService().savePlayer(info);
    notifyListeners();
  }
  
  final Set<Int64> _notFoundUids = {};
  final Set<Int64> _pendingFetches = {};

  PlayerInfo? getPlayerInfoSync(Int64 uid) {
    return _playerInfoDatas[uid];
  }

  Future<PlayerInfo?> getPlayerInfo(Int64 uid) async {
    if (_playerInfoDatas.containsKey(uid)) {
      return _playerInfoDatas[uid];
    }
    if (_notFoundUids.contains(uid)) {
      return null;
    }
    if (_pendingFetches.contains(uid)) {
      return null;
    }

    _pendingFetches.add(uid);
    try {
      return await _fetchPlayerFromDb(uid);
    } finally {
      _pendingFetches.remove(uid);
    }
  }

  Future<PlayerInfo?> _fetchPlayerFromDb(Int64 uid) async {
    try {
      final player = await DatabaseService().getPlayer(uid);
      if (player != null) {
        // Only update if not already present (network update takes precedence)
        if (!_playerInfoDatas.containsKey(uid)) {
          _playerInfoDatas[uid] = player;
          notifyListeners();
        }
        return player;
      } else {
        // Only mark as not found if not present
        if (!_playerInfoDatas.containsKey(uid)) {
          _notFoundUids.add(uid);
        }
      }
    } catch (e) {
      _logger.error("Error fetching player from DB", error: e);
    }
    return null;
  }

  DpsData getOrCreateDpsData(Int64 uid) {
    if (!_fullDpsDatas.containsKey(uid)) {
      _fullDpsDatas[uid] = DpsData(uid: uid);
    }

    if (!_playerInfoDatas.containsKey(uid) && 
        !_notFoundUids.contains(uid) && 
        !_pendingFetches.contains(uid)) {
      getPlayerInfo(uid);
    }

    return _fullDpsDatas[uid]!;
  }

  DpsData? getDpsData(Int64 uid) {
    return _fullDpsDatas[uid];
  }

  void addDamage(Int64 attackerUid, Int64 targetUid, Int64 damage, int tick, {String? skillId}) {
    _onAction();
    _logger.log("addDamage - Attacker: $attackerUid, Target: $targetUid, Damage: $damage, CurrentPlayer: $_currentPlayerUuid");
    // 1. Add Damage Dealt to Attacker
    var attackerData = getOrCreateDpsData(attackerUid);
    attackerData.startLoggedTick ??= tick;
    attackerData.lastLoggedTick = tick;
    attackerData.totalAttackDamage += damage;
    if (attackerData.startLoggedTick != null) {
       attackerData.activeCombatTicks = tick - attackerData.startLoggedTick!;
    }

    // Track skill data
    if (skillId != null && skillId.isNotEmpty) {
      var skill = attackerData.skills.putIfAbsent(skillId, () => SkillData(skillId: skillId));
      skill.totalDamage += damage;
      skill.hitCount++;
    }

    // Track timeline data for Attacker (Damage Dealt)
    if (attackerData.startLoggedTick != null) {
      final relativeTime = (tick - attackerData.startLoggedTick!) ~/ 1000;
      final slice = attackerData.timeline.putIfAbsent(relativeTime, () => TimeSlice());
      slice.damage += damage.toInt();
      if (skillId != null && skillId.isNotEmpty) {
        slice.skillDamage.update(skillId, (val) => val + damage.toInt(), ifAbsent: () => damage.toInt());
      }
    }

    // 2. Add Damage Taken to Target
    var targetData = getOrCreateDpsData(targetUid);
    targetData.startLoggedTick ??= tick;
    targetData.lastLoggedTick = tick;
    targetData.totalTakenDamage += damage;
    if (targetData.startLoggedTick != null) {
       targetData.activeCombatTicks = tick - targetData.startLoggedTick!;
    }

    // Track timeline data for Target (Damage Taken)
    if (targetData.startLoggedTick != null) {
      final relativeTime = (tick - targetData.startLoggedTick!) ~/ 1000;
      final slice = targetData.timeline.putIfAbsent(relativeTime, () => TimeSlice());
      slice.taken += damage.toInt();
    }

    notifyListeners();
  }

  void addHealing(Int64 healerUid, Int64 targetUid, Int64 healAmount, int tick, {String? skillId}) {
    _onAction();
    _logger.log("addHealing - Healer: $healerUid, Target: $targetUid, Heal: $healAmount, CurrentPlayer: $_currentPlayerUuid");
    // 1. Add Heal Output to Healer
    var healerData = getOrCreateDpsData(healerUid);
    healerData.startLoggedTick ??= tick;
    healerData.lastLoggedTick = tick;
    healerData.totalHeal += healAmount;
    if (healerData.startLoggedTick != null) {
       healerData.activeCombatTicks = tick - healerData.startLoggedTick!;
    }

    // Track skill data
    if (skillId != null && skillId.isNotEmpty) {
      var skill = healerData.skills.putIfAbsent(skillId, () => SkillData(skillId: skillId));
      skill.totalHeal += healAmount;
      skill.hitCount++;
    }
    
    // Track timeline data for Healer (Healing Done)
    if (healerData.startLoggedTick != null) {
      final relativeTime = (tick - healerData.startLoggedTick!) ~/ 1000;
      final slice = healerData.timeline.putIfAbsent(relativeTime, () => TimeSlice());
      slice.heal += healAmount.toInt();
      if (skillId != null && skillId.isNotEmpty) {
        slice.skillHeal.update(skillId, (val) => val + healAmount.toInt(), ifAbsent: () => healAmount.toInt());
      }
    }

    notifyListeners();
  }

  void reset({bool resetTimer = true}) {
    _fullDpsDatas.clear();
    if (resetTimer) {
      _combatStartTime = null;
      _lastActionTime = null;
      _isCombatActive = false;
    }
    notifyListeners();
  }

  // --- Player Info Setters ---

  void ensurePlayer(Int64 uid) {
    if (!_playerInfoDatas.containsKey(uid)) {
      _playerInfoDatas[uid] = PlayerInfo(uid: uid);
      notifyListeners();
    }
  }

  void setPlayerName(Int64 uid, String name) {
    ensurePlayer(uid);
    _playerInfoDatas[uid]!.name = name;
    _logger.log("setPlayerName called: UID=$uid, Name=$name");
    notifyListeners();
  }

  void setPlayerProfessionId(Int64 uid, int id) {
    ensurePlayer(uid);
    _playerInfoDatas[uid]!.professionId = id;
    notifyListeners();
  }

  void setPlayerCombatPower(Int64 uid, int value) {
    ensurePlayer(uid);
    _playerInfoDatas[uid]!.combatPower = value;
    notifyListeners();
  }

  void setPlayerLevel(Int64 uid, int value) {
    ensurePlayer(uid);
    _playerInfoDatas[uid]!.level = value;
    notifyListeners();
  }

  void setPlayerHp(Int64 uid, int value) {
    ensurePlayer(uid);
    _playerInfoDatas[uid]!.hp = Int64(value);
    notifyListeners();
  }

  void setPlayerMaxHp(Int64 uid, int value) {
    ensurePlayer(uid);
    _playerInfoDatas[uid]!.maxHp = Int64(value);
    notifyListeners();
  }

  void setPlayerPosition(Int64 uid, Map<String, double> position) {
    ensurePlayer(uid);
    _playerInfoDatas[uid]!.position = position;
    notifyListeners();
  }

  void setPlayerRotation(Int64 uid, Map<String, double> rotation) {
    ensurePlayer(uid);
    _playerInfoDatas[uid]!.rotation = rotation;
    notifyListeners();
  }
  
  void removePlayer(Int64 uid) {
    if (_playerInfoDatas.containsKey(uid)) {
      _playerInfoDatas.remove(uid);
      notifyListeners();
    }
  }

  // --- Monster Info Setters ---

  void ensureMonster(Int64 uid) {
    if (!_monsterInfoDatas.containsKey(uid)) {
      _monsterInfoDatas[uid] = MonsterInfo(uid: uid);
      notifyListeners();
    }
  }

  void setMonsterTemplateId(Int64 uid, int id) {
    ensureMonster(uid);
    _monsterInfoDatas[uid]!.templateId = id;
    notifyListeners();
  }

  void setMonsterName(Int64 uid, String name) {
    ensureMonster(uid);
    _monsterInfoDatas[uid]!.name = name;
    notifyListeners();
  }

  void setMonsterLevel(Int64 uid, int level) {
    ensureMonster(uid);
    _monsterInfoDatas[uid]!.level = level;
    notifyListeners();
  }

  void setMonsterHp(Int64 uid, Int64 hp) {
    ensureMonster(uid);
    _monsterInfoDatas[uid]!.hp = hp;
    if (hp <= Int64.ZERO) {
      // Logic handled in UI filtering usually, but we can also cleanup if needed.
    }
    notifyListeners();
  }
  
  void decreaseMonsterHp(Int64 uid, Int64 damage) {
    if (_monsterInfoDatas.containsKey(uid)) {
      final currentHp = _monsterInfoDatas[uid]!.hp ?? Int64.ZERO;
      if (currentHp > Int64.ZERO) {
        var newHp = currentHp - damage;
        if (newHp < Int64.ZERO) newHp = Int64.ZERO;
        _monsterInfoDatas[uid]!.hp = newHp;
        notifyListeners();
      }
    }
  }

  void setMonsterMaxHp(Int64 uid, Int64 maxHp) {
    ensureMonster(uid);
    _monsterInfoDatas[uid]!.maxHp = maxHp;
    notifyListeners();
  }

  void setMonsterPosition(Int64 uid, Map<String, double> position) {
    ensureMonster(uid);
    _monsterInfoDatas[uid]!.position = position;
    notifyListeners();
  }

  void setMonsterRotation(Int64 uid, Map<String, double> rotation) {
    ensureMonster(uid);
    _monsterInfoDatas[uid]!.rotation = rotation;
    notifyListeners();
  }

  void removeMonster(Int64 uid) {
    if (_monsterInfoDatas.containsKey(uid)) {
      _monsterInfoDatas.remove(uid);
      notifyListeners();
    }
  }
}
