import '../data/monster_names.dart';

class MonsterNameService {
  static final MonsterNameService _instance = MonsterNameService._internal();
  factory MonsterNameService() => _instance;
  MonsterNameService._internal();

  // No explicit load needed for static const data, but kept for API compatibility
  Future<void> load() async {
    // Optional: Log that we are ready
    print("[MonsterNameService] Using static data with ${monsterNames.length} names.");
  }

  String? getName(int templateId) {
    return monsterNames[templateId];
  }
}
