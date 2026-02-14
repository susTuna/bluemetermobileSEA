import 'package:fixnum/fixnum.dart';

class SkillData {
  final String skillId;
  Int64 totalDamage = Int64.ZERO;
  Int64 totalHeal = Int64.ZERO;
  int hitCount = 0;
  int luckyHitCount = 0;

  SkillData({required this.skillId});
}

class TargetBreakdown {
  final Int64 targetUid;
  Int64 totalDamage = Int64.ZERO;
  Int64 totalHeal = Int64.ZERO;
  int hitCount = 0;
  int luckyHitCount = 0;
  final Map<String, SkillData> skills = {};

  TargetBreakdown({required this.targetUid});
}

class TimeSlice {
  int damage = 0;
  int heal = 0;
  int taken = 0;
  final Map<String, int> skillDamage = {};
  final Map<String, int> skillHeal = {};
}

class DpsData {
  Int64 uid;
  int? startLoggedTick;
  int lastLoggedTick = 0;
  int activeCombatTicks = 0;
  
  Int64 totalAttackDamage = Int64.ZERO;
  Int64 totalTakenDamage = Int64.ZERO;
  Int64 totalDamageMitigated = Int64.ZERO;
  Int64 totalHeal = Int64.ZERO;
  
  bool isNpcData = false;

  // Hit tracking for crit/luck rates
  int totalHitCount = 0;
  int luckyHitCount = 0;

  // Skill tracking
  final Map<String, SkillData> skills = {};
  
  // Per-target breakdown
  final Map<Int64, TargetBreakdown> targets = {};
  
  // Timeline tracking (Key: seconds from start)
  final Map<int, TimeSlice> timeline = {};

  DpsData({required this.uid});

  double get luckyRate => totalHitCount > 0 ? luckyHitCount / totalHitCount : 0.0;

  double get dps {
    if (activeCombatTicks <= 0) return totalAttackDamage.toDouble();
    double seconds = activeCombatTicks / 1000.0;
    if (seconds < 1.0) seconds = 1.0;
    return totalAttackDamage.toDouble() / seconds;
  }
  
  double get simpleDps {
    if (startLoggedTick == null) return 0.0;
    double seconds = (lastLoggedTick - startLoggedTick!) / 1000.0;
    if (seconds < 1.0) seconds = 1.0;
    return totalAttackDamage.toDouble() / seconds;
  }

  double get simpleHps {
    if (startLoggedTick == null) return 0.0;
    double seconds = (lastLoggedTick - startLoggedTick!) / 1000.0;
    if (seconds < 1.0) seconds = 1.0;
    return totalHeal.toDouble() / seconds;
  }

  double get simpleTakenDps {
    if (startLoggedTick == null) return 0.0;
    double seconds = (lastLoggedTick - startLoggedTick!) / 1000.0;
    if (seconds < 1.0) seconds = 1.0;
    return totalTakenDamage.toDouble() / seconds;
  }
}
