/// Model representing a mob (boss or magical_creature) from bptimer.com API
class HuntMob {
  final String id; // Internal ID (pocketbase)
  final int monsterId; // In-game monster ID
  final String name;
  final String type; // "boss" or "magical_creature"
  final String map;
  final int respawnTime;
  final bool location;
  final int uid;

  HuntMob({
    required this.id,
    required this.monsterId,
    required this.name,
    required this.type,
    required this.map,
    required this.respawnTime,
    required this.location,
    required this.uid,
  });

  factory HuntMob.fromJson(Map<String, dynamic> json) {
    return HuntMob(
      id: json['id'] as String,
      monsterId: json['monster_id'] as int,
      name: json['name'] as String,
      type: json['type'] as String,
      map: json['map'] as String? ?? '',
      respawnTime: json['respawn_time'] as int? ?? 0,
      location: json['location'] as bool? ?? false,
      uid: json['uid'] as int? ?? 0,
    );
  }

  bool get isBoss => type == 'boss';
  bool get isMagicalCreature => type == 'magical_creature';
}

/// Model representing a channel status for a mob
class MobChannelStatus {
  final String id;
  final String mobId; // Reference to HuntMob.id
  final int channelNumber;
  int lastHp;
  DateTime lastUpdate;
  final String region;

  MobChannelStatus({
    required this.id,
    required this.mobId,
    required this.channelNumber,
    required this.lastHp,
    required this.lastUpdate,
    required this.region,
  });

  factory MobChannelStatus.fromJson(Map<String, dynamic> json) {
    return MobChannelStatus(
      id: json['id'] as String,
      mobId: json['mob'] as String,
      channelNumber: json['channel_number'] as int,
      lastHp: json['last_hp'] as int? ?? 0,
      lastUpdate: DateTime.tryParse(json['last_update'] as String? ?? '') ?? DateTime.now(),
      region: json['region'] as String? ?? 'NA',
    );
  }
}
