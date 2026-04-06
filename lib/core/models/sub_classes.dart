enum SubClass {
  unknown,
  // Stormblade
  iaido,
  moonstrike,
  // FrostMage
  icicle,
  frostbeam,
  // WindKnight
  vanguard,
  skyward,
  // VerdantOracle
  smite,
  lifebind,
  // HeavyGuardian
  earthfort,
  block,
  // Marksman
  wildpack,
  falconry,
  // ShieldKnight
  recovery,
  shield,
  // SoulMusician / BeatPerformer
  dissonance,
  concerto,
}

class SubClasses {
  static SubClass fromSkillId(int skillId) {
    switch (skillId) {
      case 1714: case 1734: return SubClass.iaido;
      case 1715: case 1740: case 1741: case 179906: return SubClass.moonstrike;
      case 120901: case 120902: return SubClass.icicle;
      case 1241: return SubClass.frostbeam;
      case 1405: case 1418: return SubClass.vanguard;
      case 1419: return SubClass.skyward;
      case 1518: case 1541: case 21402: return SubClass.smite;
      case 20301: return SubClass.lifebind;
      case 199902: return SubClass.earthfort;
      case 1930: case 1931: case 1934: case 1935: return SubClass.block;
      case 2292: case 1700820: case 1700825: case 1700827: return SubClass.wildpack;
      case 220112: case 2203622: case 220106: return SubClass.falconry;
      case 2405: return SubClass.recovery;
      case 2406: return SubClass.shield;
      case 2321: case 2335: return SubClass.dissonance;
      case 2301: case 2336: case 2361: case 55302: return SubClass.concerto;
      default: return SubClass.unknown;
    }
  }

  static String getName(SubClass sub) {
    switch (sub) {
      case SubClass.iaido: return 'Iaido';
      case SubClass.moonstrike: return 'Moonstrike';
      case SubClass.icicle: return 'Icicle';
      case SubClass.frostbeam: return 'Frostbeam';
      case SubClass.vanguard: return 'Vanguard';
      case SubClass.skyward: return 'Skyward';
      case SubClass.smite: return 'Smite';
      case SubClass.lifebind: return 'Lifebind';
      case SubClass.earthfort: return 'Earthfort';
      case SubClass.block: return 'Block';
      case SubClass.wildpack: return 'Wildpack';
      case SubClass.falconry: return 'Falconry';
      case SubClass.recovery: return 'Recovery';
      case SubClass.shield: return 'Shield';
      case SubClass.dissonance: return 'Dissonance';
      case SubClass.concerto: return 'Concerto';
      default: return '';
    }
  }

  /// Detect SubClass from a player's skill map (DpsData.skills keys)
  static SubClass detectFromSkills(Map<String, dynamic> skills) {
    for (final skillIdStr in skills.keys) {
      final skillId = int.tryParse(skillIdStr) ?? 0;
      final sub = fromSkillId(skillId);
      if (sub != SubClass.unknown) return sub;
    }
    return SubClass.unknown;
  }
}