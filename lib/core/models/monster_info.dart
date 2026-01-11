import 'package:fixnum/fixnum.dart';

class MonsterInfo {
  Int64 uid;
  int? templateId;
  String? name; // Might be empty if we only get templateId
  int? level;
  Int64? hp;
  Int64? maxHp;
  Map<String, double>? position;
  Map<String, double>? rotation;

  MonsterInfo({
    required this.uid,
    this.templateId,
    this.name,
    this.level,
    this.hp,
    this.maxHp,
    this.position,
    this.rotation,
  });
  
  double get hpPercent {
    if (hp == null || maxHp == null || maxHp == Int64.ZERO) return 0.0;
    return hp!.toDouble() / maxHp!.toDouble();
  }
}
