import 'package:fixnum/fixnum.dart';

class PlayerInfo {
  Int64 uid;
  String? name;
  int? professionId;
  int? combatPower;
  int? level;
  int? rankLevel;
  int? critical;
  int? lucky;
  int? attack;
  int? defense;
  int? haste;
  int? hastePct;
  int? mastery;
  int? masteryPct;
  int? versatility;
  int? versatilityPct;
  int? seasonStrength;
  Int64? maxHp;
  Int64? hp;
  Map<String, double>? position;
  Map<String, double>? rotation;

  PlayerInfo({
    required this.uid,
    this.name,
    this.professionId,
    this.combatPower,
    this.level,
    this.rankLevel,
    this.critical,
    this.lucky,
    this.attack,
    this.defense,
    this.haste,
    this.hastePct,
    this.mastery,
    this.masteryPct,
    this.versatility,
    this.versatilityPct,
    this.seasonStrength,
    this.maxHp,
    this.hp,
    this.position,
    this.rotation,
  });

  @override
  String toString() {
    return 'PlayerInfo(uid: $uid, name: $name, professionId: $professionId)';
  }
}
