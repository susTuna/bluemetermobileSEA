import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Predefined overlay anchor positions (percentage-based)
class OverlayAnchor {
  final String name;
  final IconData icon;
  final double xPercent; // % of screen width for X position
  final double yPercent; // % of screen height for Y position
  final double wPercent; // % of screen width for width
  final double hPercent; // % of screen height for height

  const OverlayAnchor({
    required this.name,
    required this.icon,
    required this.xPercent,
    required this.yPercent,
    required this.wPercent,
    required this.hPercent,
  });
}

// Easily editable predefined anchors
const List<OverlayAnchor> kOverlayAnchors = [
  OverlayAnchor(
    name: 'Left',
    icon: Icons.align_horizontal_left,
    xPercent: 0.0,
    yPercent: 28.0,
    wPercent: 22.0,
    hPercent: 26.0,
  ),
  OverlayAnchor(
    name: 'Right',
    icon: Icons.align_horizontal_right,
    xPercent: 73.0, // 100% - 20% width - 5% margin
    yPercent: 10.0,
    wPercent: 22.0,
    hPercent: 26.0,
  ),
  OverlayAnchor(
    name: 'Top',
    icon: Icons.align_vertical_top,
    xPercent: 20.0,
    yPercent: 0.0,
    wPercent: 22.0,
    hPercent: 26.0,
  ),
];

/// Color theme for the overlay
class OverlayColorTheme {
  final String id;
  final String name;
  final Color backgroundColor;
  final Color sidebarColor;
  final Color accentColor;
  final Color textColor;
  final Color secondaryTextColor;
  final Color borderColor;

  const OverlayColorTheme({
    required this.id,
    required this.name,
    required this.backgroundColor,
    required this.sidebarColor,
    required this.accentColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.borderColor,
  });
}

const Map<String, OverlayColorTheme> kOverlayThemes = {
  'dark': OverlayColorTheme(
    id: 'dark',
    name: 'Dark',
    backgroundColor: Color(0xFF000000),
    sidebarColor: Color(0xFF000000),
    accentColor: Color(0xFF2196F3),
    textColor: Color(0xFFFFFFFF),
    secondaryTextColor: Color(0xB3FFFFFF),
    borderColor: Color(0xE6FFFFFF),
  ),
  'ocean': OverlayColorTheme(
    id: 'ocean',
    name: 'Ocean',
    backgroundColor: Color(0xFF0D1B2A),
    sidebarColor: Color(0xFF0A1628),
    accentColor: Color(0xFF00BCD4),
    textColor: Color(0xFFE0F7FA),
    secondaryTextColor: Color(0xB3B2EBF2),
    borderColor: Color(0xCC00BCD4),
  ),
  'forest': OverlayColorTheme(
    id: 'forest',
    name: 'Forest',
    backgroundColor: Color(0xFF0D1F0D),
    sidebarColor: Color(0xFF0A1A0A),
    accentColor: Color(0xFF4CAF50),
    textColor: Color(0xFFE8F5E9),
    secondaryTextColor: Color(0xB3C8E6C9),
    borderColor: Color(0xCC4CAF50),
  ),
  'amethyst': OverlayColorTheme(
    id: 'amethyst',
    name: 'Amethyst',
    backgroundColor: Color(0xFF1A0D2E),
    sidebarColor: Color(0xFF150A28),
    accentColor: Color(0xFFAB47BC),
    textColor: Color(0xFFF3E5F5),
    secondaryTextColor: Color(0xB3E1BEE7),
    borderColor: Color(0xCCAB47BC),
  ),
  'crimson': OverlayColorTheme(
    id: 'crimson',
    name: 'Crimson',
    backgroundColor: Color(0xFF1A0A0A),
    sidebarColor: Color(0xFF150808),
    accentColor: Color(0xFFE53935),
    textColor: Color(0xFFFFEBEE),
    secondaryTextColor: Color(0xB3FFCDD2),
    borderColor: Color(0xCCE53935),
  ),
  'midnight': OverlayColorTheme(
    id: 'midnight',
    name: 'Midnight',
    backgroundColor: Color(0xFF0F0F23),
    sidebarColor: Color(0xFF0A0A1A),
    accentColor: Color(0xFF5C6BC0),
    textColor: Color(0xFFE8EAF6),
    secondaryTextColor: Color(0xB3C5CAE9),
    borderColor: Color(0xCC5C6BC0),
  ),
};

/// Persistent overlay settings
class OverlaySettings {
  // Theme
  String themeId;
  double backgroundOpacity;

  // Full mode position/size
  double fullX;
  double fullY;
  double fullWidth;
  double fullHeight;

  // Minimized mode position
  double miniX;
  double miniY;

  // State
  bool isMinimized;
  bool showProfession;

  OverlaySettings({
    this.themeId = 'dark',
    this.backgroundOpacity = 0.8,
    this.fullX = 0,
    this.fullY = 100,
    this.fullWidth = 600,
    this.fullHeight = 400,
    this.miniX = 0,
    this.miniY = 100,
    this.isMinimized = false,
    this.showProfession = true,
  });

  OverlayColorTheme get theme =>
      kOverlayThemes[themeId] ?? kOverlayThemes['dark']!;

  /// Load settings from SharedPreferences
  static Future<OverlaySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return OverlaySettings(
      themeId: prefs.getString('overlay_theme') ?? 'dark',
      backgroundOpacity: prefs.getDouble('overlay_opacity') ?? 0.8,
      fullX: prefs.getDouble('overlay_full_x') ?? 0,
      fullY: prefs.getDouble('overlay_full_y') ?? 100,
      fullWidth: prefs.getDouble('overlay_width') ?? 600,
      fullHeight: prefs.getDouble('overlay_height') ?? 400,
      miniX: prefs.getDouble('overlay_mini_x') ?? 0,
      miniY: prefs.getDouble('overlay_mini_y') ?? 100,
      isMinimized: prefs.getBool('overlay_minimized') ?? false,
      showProfession: prefs.getBool('overlay_show_profession') ?? true,
    );
  }

  Future<void> saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('overlay_theme', themeId);
    await prefs.setDouble('overlay_opacity', backgroundOpacity);
    await prefs.setDouble('overlay_full_x', fullX);
    await prefs.setDouble('overlay_full_y', fullY);
    await prefs.setDouble('overlay_width', fullWidth);
    await prefs.setDouble('overlay_height', fullHeight);
    await prefs.setDouble('overlay_mini_x', miniX);
    await prefs.setDouble('overlay_mini_y', miniY);
    await prefs.setBool('overlay_minimized', isMinimized);
    await prefs.setBool('overlay_show_profession', showProfession);
  }

  Future<void> savePosition(bool minimized) async {
    final prefs = await SharedPreferences.getInstance();
    if (minimized) {
      await prefs.setDouble('overlay_mini_x', miniX);
      await prefs.setDouble('overlay_mini_y', miniY);
    } else {
      await prefs.setDouble('overlay_full_x', fullX);
      await prefs.setDouble('overlay_full_y', fullY);
    }
  }

  Future<void> saveSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('overlay_width', fullWidth);
    await prefs.setDouble('overlay_height', fullHeight);
  }

  Future<void> saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('overlay_theme', themeId);
  }

  Future<void> saveOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('overlay_opacity', backgroundOpacity);
  }

  Future<void> saveMinimizedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('overlay_minimized', isMinimized);
  }

  Future<void> saveProfessionVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('overlay_show_profession', showProfession);
  }
}
