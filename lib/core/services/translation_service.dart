import 'dart:ui';

class TranslationService {
  static final TranslationService _instance = TranslationService._internal();

  factory TranslationService() {
    return _instance;
  }

  TranslationService._internal();

  // Obtient la langue actuelle du système
  String get currentLanguage => PlatformDispatcher.instance.locale.languageCode;

  // Dictionnaire de traduction
  final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'Unknown': 'Unknown',
      'Stormblade': 'Stormblade',
      'FrostMage': 'Frost Mage',
      'WindKnight': 'Wind Knight',
      'VerdantOracle': 'Verdant Oracle',
      'HeavyGuardian': 'Heavy Guardian',
      'Marksman': 'Marksman',
      'ShieldKnight': 'Shield Knight',
      'SoulMusician': 'Beat Performer',
      'Tank': 'Tank',
      'Heal': 'Healer',
      'DPS': 'DPS',
      'NoData': 'No data',
      'Start': 'Start',
      'Stop': 'Stop',
      'Me': 'Me',
      'Lv': 'Lv',
      'CS': 'AS',
      'Crit': 'Crit',
      'Luck': 'Luck',
      'Skills': 'SKILLS',
      'Details': 'DETAILS',
      'NoSkillData': 'No skill data',
      'Received': 'Taken',
      'Total': 'Tot',
      'Hits': 'hits',
      'Avg': 'Avg',
      'SubClass_Unknown': 'Unknown',
      'SubClass_Iaido': 'Iaido',
      'SubClass_Moonstrike': 'Moonstrike',
      'SubClass_Icicle': 'Icicle',
      'SubClass_Frostbeam': 'Frostbeam',
      'SubClass_Vanguard': 'Vanguard',
      'SubClass_Skyward': 'Skyward',
      'SubClass_Smite': 'Smite',
      'SubClass_Lifebind': 'Lifebind',
      'SubClass_Earthfort': 'Earthfort',
      'SubClass_Block': 'Block',
      'SubClass_Wildpack': 'Wildpack',
      'SubClass_Falconry': 'Falconry',
      'SubClass_Recovery': 'Recovery',
      'SubClass_Shield': 'Shield',
      'SubClass_Dissonance': 'Dissonance',
      'SubClass_Concerto': 'Concerto',
    },
  };

  String translate(String key) {
    // Essaie de trouver la traduction dans la langue actuelle
    if (_localizedValues.containsKey(currentLanguage) &&
        _localizedValues[currentLanguage]!.containsKey(key)) {
      return _localizedValues[currentLanguage]![key]!;
    }

    // Fallback sur l'anglais
    if (_localizedValues['en']!.containsKey(key)) {
      return _localizedValues['en']![key]!;
    }

    // Retourne la clé si aucune traduction n'est trouvée
    return key;
  }
}
