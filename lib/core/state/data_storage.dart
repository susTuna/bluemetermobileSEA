import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/player_info.dart';
import '../models/monster_info.dart';
import '../models/dps_data.dart';
import '../services/database_service.dart';
import '../services/logger_service.dart';
import '../services/monster_name_service.dart';

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

  final Set<Int64> _deadMonsters = {};

  // Scene / Line tracking
  int _lineId = 0;
  int _mapId = 0;
  int _channelId = 0;

  int get lineId => _lineId;
  int get mapId => _mapId;
  int get channelId => _channelId;

  /// Called when SyncContainerData provides scene info.
  /// Detects line changes and resets transient state accordingly.
  void onSceneUpdate({int? lineId, int? mapId, int? channelId}) {
    // Only treat as a real change if we already had a valid value (> 0).
    // Initial setting (from 0 → value) is NOT a change — don't clear entities.
    final bool lineChanged = lineId != null && lineId > 0 && _lineId > 0 && _lineId != lineId;
    final bool mapChanged = mapId != null && mapId > 0 && _mapId > 0 && _mapId != mapId;
    // Detect dungeon entry: player had a valid lineId but now it's gone (lineId=0/null)
    final bool dungeonEntry = (lineId == null || lineId == 0) && _lineId > 0;
    final oldLine = _lineId;
    final oldMap = _mapId;
    
    if (mapId != null && mapId > 0) _mapId = mapId;
    if (channelId != null && channelId > 0) _channelId = channelId;
    if (lineId != null && lineId > 0) _lineId = lineId;
    if (dungeonEntry) _lineId = 0; // Mark as "in dungeon"

    if (lineChanged || mapChanged || dungeonEntry) {
      debugPrint("[BM] Scene change! Line: $oldLine→${lineId ?? 0}${dungeonEntry ? ' (dungeon)' : ''}, Map: $oldMap→$mapId. Clearing ${_monsterInfoDatas.length} monsters.");
      _logger.log("Scene change detected! Line: $_lineId, Map: $_mapId, Channel: $_channelId");
      // Clear all transient entity data
      _monsterInfoDatas.clear();
      _deadMonsters.clear();
      // Remove all players except self
      _playerInfoDatas.removeWhere((uid, _) => uid != _currentPlayerUuid);
      // Reset combat
      _fullDpsDatas.clear();
      _combatStartTime = null;
      _lastActionTime = null;
      _isCombatActive = false;
      notifyListeners();
    }
  }

  void clearMonsters() {
    _monsterInfoDatas.clear();
    _deadMonsters.clear();
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
      // Always include current player
      if (key == _currentPlayerUuid) {
        filtered[key] = value;
      } else if (_playerInfoDatas.containsKey(key)) {
        final info = _playerInfoDatas[key];
        if (info != null && info.professionId != null && info.professionId != 0) {
          filtered[key] = value;
        }
      } else {
        // Also include entities that are not in playerInfoDatas BUT we have established DPS data for them
        // and they likely were players (or we just keep them until combat reset).
        // Check if we can determine from DpsData if it was a player?
        // Actually, if they are removed from playerInfoDatas, we lose their Name/Class info.
        // So we MUST NOT remove them from playerInfoDatas if we want to show them.
        
        // This 'else' block is just a fallback, but the real fix is in removePlayer.
      }
    });
    return Map.unmodifiable(filtered);
  }

  void updatePlayerInfo(PlayerInfo info) {
    _playerInfoDatas[info.uid] = info;
    // _notFoundUids.remove(info.uid);
    DatabaseService().savePlayer(info);
    notifyListeners();
  }
  
  // final Set<Int64> _notFoundUids = {};
  final Set<Int64> _pendingFetches = {};

  PlayerInfo? getPlayerInfoSync(Int64 uid) {
    return _playerInfoDatas[uid];
  }

  Future<PlayerInfo?> getPlayerInfo(Int64 uid) async {
    if (_playerInfoDatas.containsKey(uid)) {
      return _playerInfoDatas[uid];
    }
    // if (_notFoundUids.contains(uid)) {
    //   return null;
    // }
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
        // OR if present but missing fields that DB has
        if (!_playerInfoDatas.containsKey(uid)) {
          _playerInfoDatas[uid] = player;
          notifyListeners();
        } else {
           // Merge: Fill gaps in current memory instance with DB data
           final current = _playerInfoDatas[uid]!;
           bool changed = false;
           if (current.name == null && player.name != null) { current.name = player.name; changed = true; }
           if ((current.professionId == null || current.professionId == 0) && (player.professionId != null && player.professionId != 0)) { current.professionId = player.professionId; changed = true; }
           if ((current.combatPower == null || current.combatPower == 0) && (player.combatPower != null && player.combatPower != 0)) { current.combatPower = player.combatPower; changed = true; }
           if ((current.level == null || current.level == 0) && (player.level != null && player.level != 0)) { current.level = player.level; changed = true; }
           
           if (changed) notifyListeners();
        }
        return player;
      } else {
        // Only mark as not found if not present
        // if (!_playerInfoDatas.containsKey(uid)) {
        //   _notFoundUids.add(uid);
        // }
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
      _fetchPlayerFromDb(uid);
      notifyListeners();
    }
  }

  void setPlayerName(Int64 uid, String name) {
    ensurePlayer(uid);
    final info = _playerInfoDatas[uid]!;
    info.name = name;
    _logger.log("setPlayerName called: UID=$uid, Name=$name");
    DatabaseService().savePlayer(info);
    notifyListeners();
  }

  void setPlayerProfessionId(Int64 uid, int id) {
    ensurePlayer(uid);
    final info = _playerInfoDatas[uid]!;
    info.professionId = id;
    DatabaseService().savePlayer(info);
    notifyListeners();
  }

  void setPlayerCombatPower(Int64 uid, int value) {
    ensurePlayer(uid);
    final info = _playerInfoDatas[uid]!;
    info.combatPower = value;
    DatabaseService().savePlayer(info);
    notifyListeners();
  }

  void setPlayerLevel(Int64 uid, int value) {
    ensurePlayer(uid);
    final info = _playerInfoDatas[uid]!;
    info.level = value;
    DatabaseService().savePlayer(info);
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
    // Don't save maxHP updates constantly unless critical, but often getting maxHP means we got good info?
    // Let's safe it sparingly or assume other updates will catch it.
    // Actually MaxHP doesn't change that often.
    DatabaseService().savePlayer(_playerInfoDatas[uid]!);
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
      // Don't remove player if they have DPS/Healing stats
      if (_fullDpsDatas.containsKey(uid)) {
          // Maybe just mark as offline/away? 
          // For now, doing nothing keeps them in the list.
          _logger.log("removePlayer($uid) ignored because player has DPS stats.");
          return;
      }
      _playerInfoDatas.remove(uid);
      notifyListeners();
    }
  }

  // --- Monster Info Setters ---

  bool ensureMonster(Int64 uid, {bool forceRespawn = false}) {
    if (forceRespawn) {
      _deadMonsters.remove(uid);
    }
    
    if (_deadMonsters.contains(uid)) return false;

    if (!_monsterInfoDatas.containsKey(uid)) {
      _monsterInfoDatas[uid] = MonsterInfo(uid: uid);
      notifyListeners();
    }
    return true;
  }

  void setMonsterTemplateId(Int64 uid, int id) {
    if (!ensureMonster(uid)) return;
    _monsterInfoDatas[uid]!.templateId = id;
    
    // Auto-resolve name if not present
    if (_monsterInfoDatas[uid]!.name == null || _monsterInfoDatas[uid]!.name!.isEmpty) {
       final name = MonsterNameService().getName(id);
       if (name != null) {
          _monsterInfoDatas[uid]!.name = name;
       }
    }
    
    notifyListeners();
  }

  void setMonsterName(Int64 uid, String name) {
    if (!ensureMonster(uid)) return;
    _monsterInfoDatas[uid]!.name = name;
    notifyListeners();
  }

  void setMonsterLevel(Int64 uid, int level) {
    if (!ensureMonster(uid)) return;
    _monsterInfoDatas[uid]!.level = level;
    notifyListeners();
  }

  void setMonsterIsDead(Int64 uid, bool isDead) {
    if (_monsterInfoDatas.containsKey(uid)) {
       _monsterInfoDatas[uid]!.isDead = isDead;
       notifyListeners();
    }
  }

  void setMonsterHp(Int64 uid, Int64 hp) {
    if (!ensureMonster(uid)) return;
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
    if (!ensureMonster(uid)) return;
    _monsterInfoDatas[uid]!.maxHp = maxHp;
    notifyListeners();
  }

  void setMonsterPosition(Int64 uid, Map<String, double> position) {
    if (!ensureMonster(uid)) return;
    _monsterInfoDatas[uid]!.position = position;
    notifyListeners();
  }

  void setMonsterRotation(Int64 uid, Map<String, double> rotation) {
    if (!ensureMonster(uid)) return;
    _monsterInfoDatas[uid]!.rotation = rotation;
    notifyListeners();
  }

  void removeMonster(Int64 uid) {
    _deadMonsters.add(uid);
    if (_monsterInfoDatas.containsKey(uid)) {
      _monsterInfoDatas.remove(uid);
      debugPrint("[DataStorage] Removed monster $uid. Map size: ${_monsterInfoDatas.length}");
      notifyListeners();
    }
  }
}
