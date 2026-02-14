enum AttrType {
  unknown(0),
  attrName(1),
  attrId(10),
  attrProfessionId(0xDC),
  attrFightPoint(0x272E),
  attrLevel(0x2710),
  attrRankLevel(0x274C),
  attrCri(0x2B66),
  attrLucky(0x2B7A),
  attrAttack(0x2B02),
  attrDefense(0x2B16),
  attrStrength(0x2B52),
  attrDexterity(0x2B5C),
  attrIntelligence(0x2B66 + 0x14), // placeholder offset
  attrHaste(0x2B8E),
  attrHastePct(0x2B98),
  attrMastery(0x2BA2),
  attrMasteryPct(0x2BAC),
  attrVersatility(0x2BB6),
  attrVersatilityPct(0x2BC0),
  attrSeasonStrength(12690),
  // Total variants - game may send these instead of base
  attrCriTotal(11111),
  attrLuckyTotal(11131),
  attrAttackTotal(11331),
  attrDefenseTotal(11351),
  attrHasteTotal(11121),
  attrMasteryTotal(11141),
  attrVersatilityTotal(11151),
  attrHastePctTotal(11931),
  attrMasteryPctTotal(11941),
  attrVersatilityPctTotal(11951),
  attrSeasonStrengthTotal(12691),
  attrHp(0x2C2E),
  attrMaxHp(0x2C38),
  attrElementFlag(0x646D6C),
  attrReductionLevel(0x64696D),
  attrReduntionId(0x6F6C65),
  attrEnergyFlag(0x543CD3C6),
  
  // Unknown but seen in logs
  attrUnknown50(50);

  final int value;
  const AttrType(this.value);

  static AttrType fromId(int id) {
    try {
      return AttrType.values.firstWhere((e) => e.value == id, orElse: () => AttrType.unknown);
    } catch (e) {
      return AttrType.unknown;
    }
  }

  static AttrType? fromValue(int value) {
    try {
      return AttrType.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return null;
    }
  }
  
  // Helper to check if a value matches (since firstWhere throws or returns default)
  static bool isKnown(int value) {
    return AttrType.values.any((e) => e.value == value);
  }
}
