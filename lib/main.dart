import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bluemetersea_mobile/core/services/translation_service.dart';
import 'package:bluemetersea_mobile/views/dps_view.dart';
import 'package:bluemetersea_mobile/views/nearby_view.dart';
import 'package:bluemetersea_mobile/views/tools_view.dart';
import 'package:bluemetersea_mobile/views/hunt_view.dart';
import 'package:bluemetersea_mobile/views/settings_view.dart';
import 'package:bluemetersea_mobile/widgets/player_detail_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:fixnum/fixnum.dart';
import 'core/analyze/packet_analyzer_v2.dart';
import 'core/state/data_storage.dart';
import 'core/services/monster_name_service.dart';
import 'core/services/bptimer_service.dart';
import 'core/models/dps_data.dart';
import 'core/models/player_info.dart';

import 'core/models/overlay_settings.dart';
import 'core/services/logger_service.dart';

// ...

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await MonsterNameService().load();

  // Pre-load known mobs for HP reporting (non-blocking)
  BPTimerService().ensureMobsLoaded();

  runApp(
    ChangeNotifierProvider(
      create: (context) => DataStorage(),
      child: const MyApp(),
    ),
  );
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (context) => DataStorage(),
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OverlayWidget(),
      ),
    ),
  );
}

class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  final LoggerService _logger = LoggerService();
  List<Map<String, dynamic>> _players = [];
  int _combatTime = 0;
  int _lineId = 0;
  String? _selectedPlayerUid;

  // Navigation State
  int _mainTabIndex = 0; // 0=DPS, 1=Nearby, 2=Tools, 3=Hunt, 4=Settings
  int _dpsTabIndex = 0; // 0=DPS(sword), 1=Taken(shield), 2=Heal(cross)

  // Track window position
  double _windowX = 0;
  double _windowY = 0;

  // Store original window size before showing detail
  double _savedWidth = 600;
  double _savedHeight = 400;

  // Screen dimensions (received from main app via IPC)
  double _screenWidth = 0;
  double _screenHeight = 0;

  // Drag helpers – simple per-frame delta from globalPosition
  double _lastGlobalX = 0;
  double _lastGlobalY = 0;
  Size? _resizeStartWindowSize;
  Offset? _dragStartTouchPosition; // Keep for resize
  bool _isDragging = false;

  // Overlay settings (theme, opacity, positions, minimized state)
  late OverlaySettings _settings;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is List) {
        setState(() {
          _players = List<Map<String, dynamic>>.from(event);
        });
      } else if (event is Map) {
        setState(() {
          if (event.containsKey('players')) {
            _players = List<Map<String, dynamic>>.from(event['players']);
          }
          if (event.containsKey('combatTime')) {
            _combatTime = event['combatTime'] as int;
          }
          if (event.containsKey('lineId')) {
            _lineId = event['lineId'] as int;
          }
          // Update selectedPlayerUid when it's explicitly sent
          if (event.containsKey('selectedPlayerUid')) {
            final newUid = event['selectedPlayerUid'] as String?;

            // If switching to detail view, save current window size
            if (newUid != null && _selectedPlayerUid == null) {
              _saveCurrentWindowSize();
            }

            _selectedPlayerUid = newUid;
          }

          // Receive screen dimensions from main app
          if (event.containsKey('screenWidth')) {
            _screenWidth = (event['screenWidth'] as num).toDouble();
            _screenHeight = (event['screenHeight'] as num).toDouble();
          }

          // Sync DataStorage for NearbyView
          if (mounted) {
            final storage = Provider.of<DataStorage>(context, listen: false);

            if (event.containsKey('myUid')) {
              final myUidStr = event['myUid'] as String?;
              if (myUidStr != null) {
                storage.currentPlayerUuid = Int64.parseInt(myUidStr);
              }
            }

            if (event.containsKey('myPos')) {
              final myPos = event['myPos'] as Map?;
              if (myPos != null) {
                final convertedPos = myPos.map(
                  (key, value) =>
                      MapEntry(key.toString(), (value as num).toDouble()),
                );

                storage.setPlayerPosition(
                  storage.currentPlayerUuid,
                  convertedPos,
                );
              }
            }

            if (event.containsKey('monsters')) {
              final monsters = event['monsters'] as List?;
              if (monsters != null) {
                final incomingUids = <Int64>{};

                for (var m in monsters) {
                  final map = m as Map;
                  final uid = Int64.parseInt(map['uid'] as String);
                  incomingUids.add(uid);

                  // Allow overlay to sync with main app truth, ignoring local graveyard
                  storage.ensureMonster(uid, forceRespawn: true);

                  if (map['templateId'] != null)
                    storage.setMonsterTemplateId(uid, map['templateId'] as int);
                  if (map['name'] != null)
                    storage.setMonsterName(uid, map['name'] as String);
                  if (map['level'] != null)
                    storage.setMonsterLevel(uid, map['level'] as int);
                  if (map['hp'] != null)
                    storage.setMonsterHp(
                      uid,
                      Int64.parseInt(map['hp'] as String),
                    );
                  if (map['maxHp'] != null)
                    storage.setMonsterMaxHp(
                      uid,
                      Int64.parseInt(map['maxHp'] as String),
                    );
                  if (map['isDead'] != null)
                    storage.setMonsterIsDead(uid, map['isDead'] as bool);

                  if (map['pos_x'] != null) {
                    storage.setMonsterPosition(uid, {
                      'x': (map['pos_x'] as num).toDouble(),
                      'y': (map['pos_y'] as num).toDouble(),
                      'z': (map['pos_z'] as num).toDouble(),
                    });
                  }
                }

                // Remove stale monsters that are no longer in the list sent by Main Isolate
                final currentUids = storage.monsterInfoDatas.keys.toList();
                for (var uid in currentUids) {
                  if (!incomingUids.contains(uid)) {
                    storage.removeMonster(uid);
                  }
                }
              }
            }
          }
        });
      }
    });
  }

  Future<void> _loadSettings() async {
    final s = await OverlaySettings.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _settingsLoaded = true;
      _windowX = s.isMinimized ? s.miniX : s.fullX;
      _windowY = s.isMinimized ? s.miniY : s.fullY;
      _savedWidth = s.fullWidth;
    });
    // Apply saved state after the overlay is fully ready
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (s.isMinimized) {
          await FlutterOverlayWindow.resizeOverlay(135, 30, false);
        } else {
          await FlutterOverlayWindow.resizeOverlay(
            s.fullWidth.toInt(),
            s.fullHeight.toInt(),
            false,
          );
        }
        await FlutterOverlayWindow.moveOverlay(
          OverlayPosition(_windowX, _windowY),
        );
      } catch (e) {
        _logger.error('Error applying saved overlay state', error: e);
      }
    });
  }

  Future<void> _savePosition() async {
    if (_settings.isMinimized) {
      _settings.miniX = _windowX;
      _settings.miniY = _windowY;
    } else {
      _settings.fullX = _windowX;
      _settings.fullY = _windowY;
    }
    await _settings.savePosition(_settings.isMinimized);
  }

  Future<void> _saveSize() async {
    if (_settings.isMinimized) return;
    await _settings.saveSize();
  }

  void _saveCurrentWindowSize() {
    _savedWidth = _settings.fullWidth;
    _savedHeight = _settings.fullHeight;
    _logger.log(
      "Saved window size: $_savedWidth"
      "x"
      "$_savedHeight",
    );
  }

  Future<void> _resizeForDetail() async {
    try {
      await FlutterOverlayWindow.resizeOverlay(500, 300, false);
      // debugPrint("[BM] Resized to detail view: 300x300");
    } catch (e) {
      // debugPrint("[BM] Error resizing for detail: $e");
    }
  }

  Future<void> _restoreOriginalSize() async {
    try {
      await FlutterOverlayWindow.resizeOverlay(
        _savedWidth.toInt(),
        _savedHeight.toInt(),
        false,
      );
      _logger.log(
        "Restored window size: $_savedWidth"
        "x"
        "$_savedHeight",
      );
    } catch (e) {
      _logger.error("Error restoring window size", error: e);
    }
  }

  Future<void> _applyAnchor(OverlayAnchor anchor) async {
    // Use screen dimensions received from main app via IPC
    if (_screenWidth <= 0 || _screenHeight <= 0) {
      _logger.error('Screen dimensions not available yet');
      return;
    }

    final x = _screenWidth * anchor.xPercent / 100.0;
    final y = _screenHeight * anchor.yPercent / 100.0;
    final w = _screenWidth * anchor.wPercent / 100.0;
    final h = _screenHeight * anchor.hPercent / 100.0;

    setState(() {
      _windowX = x;
      _windowY = y;
      _settings.fullX = x;
      _settings.fullY = y;
      _settings.fullWidth = w;
      _settings.fullHeight = h;
      _settings.isMinimized = false;
    });

    await FlutterOverlayWindow.resizeOverlay(w.toInt(), h.toInt(), false);
    await FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y));
    await _settings.saveAll();
  }

  @override
  void dispose() {
    // _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const SizedBox.shrink();
    }

    // Si un joueur est sélectionné, afficher la carte de détails
    if (_selectedPlayerUid != null) {
      // Resize window for detail view
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resizeForDetail();
      });
      return _buildPlayerDetail();
    }

    // Sinon afficher la liste normale
    if (_settings.isMinimized) {
      return _buildMinimized();
    }
    return _buildFull();
  }

  BoxDecoration get _windowDecoration {
    final theme = _settings.theme;
    return BoxDecoration(
      color: theme.backgroundColor.withValues(
        alpha: _settings.backgroundOpacity,
      ),
      borderRadius: BorderRadius.circular(0),
      border: Border(
        left: BorderSide(
          color: theme.borderColor.withValues(alpha: 0.9),
          width: 0.5,
        ),
      ),
    );
  }

  Widget _buildMinimized() {
    // Determine keys based on tab index
    // Default to DPS if controller not ready
    int tabIndex = _dpsTabIndex;

    String rateKey = 'dps';
    String totalKey = 'total';
    IconData headerIcon = Icons.flash_on;

    if (tabIndex == 1) {
      // Taken (matches TabBarView order)
      rateKey = 'takenDps';
      totalKey = 'totalTaken';
      headerIcon = Icons.shield;
    } else if (tabIndex == 2) {
      // Heal
      rateKey = 'hps';
      totalKey = 'totalHeal';
      headerIcon = Icons.local_hospital;
    }

    // Calculate Rank
    var filtered = _players.where((p) {
      final total = (p[totalKey] as num?)?.toDouble() ?? 0.0;
      return total > 0;
    }).toList();

    filtered.sort((a, b) {
      final valA = (a[totalKey] as num?)?.toDouble() ?? 0.0;
      final valB = (b[totalKey] as num?)?.toDouble() ?? 0.0;
      return valB.compareTo(valA);
    });

    final myIndex = filtered.indexWhere((p) => p['isMe'] == true);
    final myRank = myIndex != -1 ? myIndex + 1 : 0;

    final myData = _players.firstWhere(
      (p) => p['isMe'] == true,
      orElse: () => {},
    );
    final myVal = (myData[rateKey] as num?)?.toDouble() ?? 0.0;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onPanStart: (details) {
          _lastGlobalX = details.globalPosition.dx;
          _lastGlobalY = details.globalPosition.dy;
          _isDragging = true;
        },
        onPanUpdate: (details) {
          if (!_isDragging) return;
          final dx = details.globalPosition.dx - _lastGlobalX;
          final dy = details.globalPosition.dy - _lastGlobalY;
          _windowX += dx;
          _windowY += dy;
          _lastGlobalX = details.globalPosition.dx;
          _lastGlobalY = details.globalPosition.dy;

          FlutterOverlayWindow.moveOverlay(OverlayPosition(_windowX, _windowY));
        },
        onPanEnd: (details) {
          _isDragging = false;
          _savePosition();
        },
        onTap: () async {
          setState(() {
            _settings.isMinimized = false;
          });
          _settings.saveMinimizedState();

          // Restore full position
          _windowX = _settings.fullX;
          _windowY = _settings.fullY;

          await FlutterOverlayWindow.resizeOverlay(
            _settings.fullWidth.toInt(),
            _settings.fullHeight.toInt(),
            false,
          );
          await FlutterOverlayWindow.moveOverlay(
            OverlayPosition(_windowX, _windowY),
          );
        },
        child: Container(
          decoration: _windowDecoration,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    headerIcon,
                    size: 16,
                    color: _settings.theme.accentColor,
                  ),
                  const SizedBox(width: 4),
                  if (myRank > 0)
                    Text(
                      "#$myRank",
                      style: TextStyle(
                        color: _settings.theme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
              Expanded(
                child: Text(
                  _formatNumber(myVal),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: _settings.theme.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final sendPort = IsolateNameServer.lookupPortByName(
                    'overlay_communication_port',
                  );
                  if (sendPort != null) {
                    sendPort.send("RESET");
                  }
                },
                child: Icon(
                  Icons.refresh,
                  size: 16,
                  color: _settings.theme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFull() {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: _windowDecoration,
        child: Stack(
          children: [
            Row(
              children: [
                // Vertical Side Menu
                Container(
                  width: 26,
                  color: _settings.theme.sidebarColor.withValues(
                    alpha: _settings.backgroundOpacity * 0.75,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      // Tab 0: DPS Meter
                      _buildSideTab(0, Icons.bar_chart),
                      // Tab 1: Nearby (Radar)
                      _buildSideTab(1, Icons.radar),
                      // Tab 2: Tools (Module/Optimizer)
                      // _buildSideTab(2, Icons.build),
                      // Tab 3: Hunt (Boss/Creature Tracker)
                      _buildSideTab(3, Icons.hub_outlined),
                      // Tab 4: Settings
                      _buildSideTab(4, Icons.settings),
                    ],
                  ),
                ),
                // Main Content Area
                Expanded(
                  child: Column(
                    children: [
                      // Draggable Title Bar / Header (Timer + Window Controls)
                      GestureDetector(
                        onPanStart: (details) {
                          _lastGlobalX = details.globalPosition.dx;
                          _lastGlobalY = details.globalPosition.dy;
                          _isDragging = true;
                        },
                        onPanUpdate: (details) {
                          if (!_isDragging) return;
                          final dx = details.globalPosition.dx - _lastGlobalX;
                          final dy = details.globalPosition.dy - _lastGlobalY;
                          _windowX += dx;
                          _windowY += dy;
                          _lastGlobalX = details.globalPosition.dx;
                          _lastGlobalY = details.globalPosition.dy;

                          FlutterOverlayWindow.moveOverlay(
                            OverlayPosition(_windowX, _windowY),
                          );
                        },
                        onPanEnd: (details) {
                          _isDragging = false;
                          _savePosition();
                        },
                        child: Container(
                          height: 22,
                          color: Colors.transparent, // Hit test
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment
                                .spaceBetween, // Push items to edges
                            children: [
                              // Line number (Left aligned in this area)
                              Text(
                                _lineId > 0 ? 'L${_lineId}' : '—',
                                style: TextStyle(
                                  color: _settings.theme.textColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  shadows: const [
                                    Shadow(blurRadius: 2, color: Colors.black),
                                  ],
                                ),
                              ),
                              // Window Actions (Right aligned)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () async {
                                      setState(() {
                                        _settings.isMinimized = true;
                                      });
                                      _settings.saveMinimizedState();

                                      // Restore mini position
                                      _windowX = _settings.miniX;
                                      _windowY = _settings.miniY;

                                      await FlutterOverlayWindow.resizeOverlay(
                                        135,
                                        30,
                                        false,
                                      );
                                      await FlutterOverlayWindow.moveOverlay(
                                        OverlayPosition(_windowX, _windowY),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: Icon(
                                        Icons.remove,
                                        size: 14,
                                        color:
                                            _settings.theme.secondaryTextColor,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () async {
                                      final sendPort =
                                          IsolateNameServer.lookupPortByName(
                                            'overlay_communication_port',
                                          );
                                      if (sendPort != null) {
                                        sendPort.send("RESET");
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: Icon(
                                        Icons.refresh,
                                        size: 14,
                                        color:
                                            _settings.theme.secondaryTextColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Content View
                      Expanded(
                        child: IndexedStack(
                          index: _mainTabIndex,
                          children: [
                            DpsView(
                              players: _players,
                              combatTime: _combatTime,
                              onSelectPlayer: (uid) {
                                final sendPort =
                                    IsolateNameServer.lookupPortByName(
                                      'overlay_communication_port',
                                    );
                                if (sendPort != null) {
                                  sendPort.send({'selectPlayer': uid});
                                }
                              },
                              onTabChanged: (index) {
                                _dpsTabIndex = index;
                              },
                            ),
                            NearbyView(isActive: _mainTabIndex == 1),
                            const ToolsView(),
                            HuntView(isActive: _mainTabIndex == 3),
                            SettingsView(
                              settings: _settings,
                              onThemeChanged: () => setState(() {}),
                              onOpacityChanged: () => setState(() {}),
                              onAnchorSelected: (anchor) =>
                                  _applyAnchor(anchor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Resize Handle
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onPanStart: (details) {
                  // Use logical size directly
                  final size = MediaQuery.of(context).size;
                  _resizeStartWindowSize = size;
                  _dragStartTouchPosition = details.globalPosition;
                },
                onPanUpdate: (details) {
                  if (_resizeStartWindowSize == null ||
                      _dragStartTouchPosition == null)
                    return;

                  final currentTouch = details.globalPosition;
                  final diff = currentTouch - _dragStartTouchPosition!;

                  // Calculate new size in logical pixels
                  double newWidth = _resizeStartWindowSize!.width + diff.dx;
                  double newHeight = _resizeStartWindowSize!.height + diff.dy;

                  // Min size constraints (logical)
                  if (newWidth < 150) newWidth = 150;
                  if (newHeight < 100) newHeight = 100;

                  // Save for restore
                  _settings.fullWidth = newWidth;
                  _settings.fullHeight = newHeight;

                  FlutterOverlayWindow.resizeOverlay(
                    newWidth.toInt(),
                    newHeight.toInt(),
                    false,
                  );
                },
                onPanEnd: (details) {
                  _saveSize();
                },
                child: Container(
                  width: 30,
                  height: 30,
                  color: Colors.transparent,
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.south_east,
                    size: 14,
                    color: Colors.white24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideTab(int index, IconData icon) {
    final isSelected = _mainTabIndex == index;
    final theme = _settings.theme;
    return GestureDetector(
      onTap: () {
        setState(() {
          _mainTabIndex = index;
        });
      },
      child: Container(
        height: 26,
        width: 26,
        color: isSelected
            ? theme.textColor.withValues(alpha: 0.1)
            : Colors.transparent,
        child: Icon(
          icon,
          color: isSelected ? theme.accentColor : theme.secondaryTextColor,
          size: 16,
        ),
      ),
    );
  }

  String _formatNumber(num number) {
    if (number >= 1000000) {
      double val = number / 1000000;
      String s = val < 100 ? val.toStringAsFixed(2) : val.toStringAsFixed(1);
      return "${s}m";
    }
    if (number >= 1000) {
      double val = number / 1000;
      String s = val < 100 ? val.toStringAsFixed(2) : val.toStringAsFixed(1);
      return "${s}k";
    }
    return number.toStringAsFixed(0);
  }

  Widget _buildPlayerDetail() {
    if (_selectedPlayerUid == null) return const SizedBox.shrink();

    final playerData = _players.firstWhere(
      (p) => p['uid'] == _selectedPlayerUid,
      orElse: () => {},
    );

    if (playerData.isEmpty) return const SizedBox.shrink();

    final uid = Int64.parseInt(_selectedPlayerUid!);

    // Use the already calculated DPS/HPS values from playerData
    final dpsValue = (playerData['dps'] as num?)?.toDouble() ?? 0.0;
    final hpsValue = (playerData['hps'] as num?)?.toDouble() ?? 0.0;
    final takenDpsValue = (playerData['takenDps'] as num?)?.toDouble() ?? 0.0;

    final dpsData = DpsData(uid: uid)
      ..totalAttackDamage = Int64(playerData['total'] ?? 0)
      ..totalHeal = Int64(playerData['totalHeal'] ?? 0)
      ..totalTakenDamage = Int64(playerData['totalTaken'] ?? 0)
      ..activeCombatTicks = playerData['activeCombatTicks'] ?? 0
      ..totalHitCount = playerData['totalHitCount'] ?? 0
      ..critHitCount = playerData['critHitCount'] ?? 0
      ..luckyHitCount = playerData['luckyHitCount'] ?? 0;

    if (playerData.containsKey('timeline') && playerData['timeline'] != null) {
      final timelineMap = playerData['timeline'] as Map<String, dynamic>;
      timelineMap.forEach((key, value) {
        final time = int.tryParse(key) ?? 0;
        final sliceData = value as Map<String, dynamic>;
        final slice = TimeSlice()
          ..damage = sliceData['d'] ?? 0
          ..heal = sliceData['h'] ?? 0
          ..taken = sliceData['t'] ?? 0;

        if (sliceData.containsKey('sd')) {
          (sliceData['sd'] as Map<String, dynamic>).forEach((k, v) {
            slice.skillDamage[k] = v as int;
          });
        }
        if (sliceData.containsKey('sh')) {
          (sliceData['sh'] as Map<String, dynamic>).forEach((k, v) {
            slice.skillHeal[k] = v as int;
          });
        }
        dpsData.timeline[time] = slice;
      });
    }

    final skillsList = playerData['skills'] as List<dynamic>? ?? [];
    for (var skillMap in skillsList) {
      final skillData = SkillData(skillId: skillMap['skillId'])
        ..totalDamage = Int64(skillMap['totalDamage'] ?? 0)
        ..totalHeal = Int64(skillMap['totalHeal'] ?? 0)
        ..hitCount = skillMap['hitCount'] ?? 0
        ..critHitCount = skillMap['critHitCount'] ?? 0
        ..luckyHitCount = skillMap['luckyHitCount'] ?? 0;
      dpsData.skills[skillData.skillId] = skillData;
    }

    // Deserialize per-target breakdown
    final targetsList = playerData['targets'] as List<dynamic>? ?? [];
    for (var targetMap in targetsList) {
      final targetUid = Int64.parseInt(targetMap['uid'] as String);
      final targetName = targetMap['name'] as String?;
      final breakdown =
          TargetBreakdown(
              targetUid: targetUid,
              name: targetName != null && targetName.isNotEmpty
                  ? targetName
                  : null,
            )
            ..totalDamage = Int64(targetMap['totalDamage'] ?? 0)
            ..totalHeal = Int64(targetMap['totalHeal'] ?? 0)
            ..hitCount = targetMap['hitCount'] ?? 0
            ..critHitCount = targetMap['critHitCount'] ?? 0
            ..luckyHitCount = targetMap['luckyHitCount'] ?? 0;

      final tSkills = targetMap['skills'] as List<dynamic>? ?? [];
      for (var ts in tSkills) {
        final sd = SkillData(skillId: ts['skillId'])
          ..totalDamage = Int64(ts['totalDamage'] ?? 0)
          ..totalHeal = Int64(ts['totalHeal'] ?? 0)
          ..hitCount = ts['hitCount'] ?? 0
          ..critHitCount = ts['critHitCount'] ?? 0
          ..luckyHitCount = ts['luckyHitCount'] ?? 0;
        breakdown.skills[sd.skillId] = sd;
      }
      dpsData.targets[targetUid] = breakdown;
    }

    final playerInfo = PlayerInfo(
      uid: uid,
      name: playerData['name'],
      professionId: playerData['classId'],
      level: playerData['level'],
      combatPower: playerData['combatPower'],
      rankLevel: playerData['rankLevel'],
      critical: playerData['critical'],
      lucky: playerData['lucky'],
      attack: playerData['attack'],
      defense: playerData['defense'],
      haste: playerData['haste'],
      hastePct: playerData['hastePct'],
      mastery: playerData['mastery'],
      masteryPct: playerData['masteryPct'],
      versatility: playerData['versatility'],
      versatilityPct: playerData['versatilityPct'],
      seasonStrength: playerData['seasonStrength'],
      maxHp: Int64(playerData['maxHp'] ?? 0),
      hp: Int64(playerData['hp'] ?? 0),
    );

    final isMe = playerData['isMe'] == true;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: _windowDecoration,
        child: PlayerDetailCard(
          playerInfo: playerInfo,
          dpsData: dpsData,
          dpsValue: dpsValue,
          hpsValue: hpsValue,
          takenDpsValue: takenDpsValue,
          isMe: isMe,
          onClose: () async {
            // Restore original window size before closing detail
            await _restoreOriginalSize();
            setState(() {
              _selectedPlayerUid = null;
            });
          },
          onDragStart: (details) {
            _lastGlobalX = details.globalPosition.dx;
            _lastGlobalY = details.globalPosition.dy;
            _isDragging = true;
          },
          onDragUpdate: (details) {
            if (!_isDragging) return;
            final dx = details.globalPosition.dx - _lastGlobalX;
            final dy = details.globalPosition.dy - _lastGlobalY;
            _windowX += dx;
            _windowY += dy;
            _lastGlobalX = details.globalPosition.dx;
            _lastGlobalY = details.globalPosition.dy;

            FlutterOverlayWindow.moveOverlay(
              OverlayPosition(_windowX, _windowY),
            );
          },
          onDragEnd: (details) {
            _isDragging = false;
            _savePosition();
          },
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bluemeterseaSEA Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const platform = MethodChannel('com.bluemetersea.mobile/vpn');
  static const eventChannel = EventChannel(
    'com.bluemetersea.mobile/packet_stream',
  );
  static const upstreamEventChannel = EventChannel(
    'com.bluemetersea.mobile/upstream_stream',
  );

  final LoggerService _logger = LoggerService();
  final BPTimerService _bpTimerService = BPTimerService();

  bool _isVpnRunning = false;
  StreamSubscription? _packetSubscription;
  StreamSubscription? _upstreamSubscription;
  late PacketAnalyzerV2 _packetAnalyzer;
  late PacketAnalyzerV2 _otherSessionAnalyzer;
  Timer? _overlayUpdateTimer;
  ReceivePort? _receivePort;
  String?
  _selectedPlayerUid; // UID du joueur sélectionné pour affichage de la carte
  int _lastReportedLineId = 0; // Track line changes for throttle reset

  @override
  void initState() {
    super.initState();
    _packetAnalyzer = PacketAnalyzerV2(DataStorage(), tag: 'combat');
    _otherSessionAnalyzer = PacketAnalyzerV2(DataStorage(), tag: 'port5003');

    // Setup communication port
    _receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(
      'overlay_communication_port',
    ); // Clean up old mapping if any
    IsolateNameServer.registerPortWithName(
      _receivePort!.sendPort,
      'overlay_communication_port',
    );
    _receivePort!.listen((message) {
      // _logger.log("HomePage received message: $message");
      if (message == "RESET") {
        DataStorage().reset();
        setState(() {
          _selectedPlayerUid = null;
        });
        _updateOverlay(); // Send update without selectedPlayerUid
      } else if (message is Map && message.containsKey('selectPlayer')) {
        final newUid = message['selectPlayer'] as String?;
        _logger.log("HomePage setting selectedPlayerUid to: $newUid");
        setState(() {
          _selectedPlayerUid = newUid;
        });
        // Send selected player to overlay immediately
        _updateOverlayWithSelection();
      }
    });

    // DataStorage().addListener(_updateOverlay);
    // Update overlay at 2 FPS (500ms) to prevent log spam and UI overload
    _overlayUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) {
      _updateOverlay();
    });
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('overlay_communication_port');
    _receivePort?.close();
    // DataStorage().removeListener(_updateOverlay);
    _overlayUpdateTimer?.cancel();
    super.dispose();
  }

  final Map<String, String> _targetNameCache = {};

  String _resolveTargetName(Int64 uid) {
    final key = uid.toString();
    // Check cache first (survives monster death)
    if (_targetNameCache.containsKey(key)) return _targetNameCache[key]!;
    final storage = DataStorage();
    final monster = storage.monsterInfoDatas[uid];
    if (monster != null && monster.name != null && monster.name!.isNotEmpty) {
      _targetNameCache[key] = monster.name!;
      return monster.name!;
    }
    if (monster != null && monster.templateId != null) {
      final n = MonsterNameService().getName(monster.templateId!);
      if (n != null) {
        _targetNameCache[key] = n;
        return n;
      }
    }
    final player = storage.playerInfoDatas[uid];
    if (player != null && player.name != null && player.name!.isNotEmpty) {
      _targetNameCache[key] = player.name!;
      return player.name!;
    }
    return '';
  }

  Future<void> _updateOverlay() async {
    final storage = DataStorage();
    storage.checkTimeout();

    final players = storage.fullDpsDatas.entries
        .where(
          (e) =>
              e.value.totalAttackDamage.toInt() > 0 ||
              e.value.totalHeal.toInt() > 0 ||
              e.value.totalTakenDamage.toInt() > 0,
        )
        .map((e) {
          final uid = e.key;
          final dpsData = e.value;
          // Use synchronous getter to avoid await overhead
          final info = storage.getPlayerInfoSync(uid);
          // _logger.log("UpdateOverlay - Processing UID: $uid, isMe: ${uid == storage.currentPlayerUuid}, Name: ${info?.name}");

          // Convert skills to serializable format
          final skillsList = dpsData.skills.entries
              .map(
                (skillEntry) => {
                  'skillId': skillEntry.key,
                  'totalDamage': skillEntry.value.totalDamage.toInt(),
                  'totalHeal': skillEntry.value.totalHeal.toInt(),
                  'hitCount': skillEntry.value.hitCount,
                  'critHitCount': skillEntry.value.critHitCount,
                  'luckyHitCount': skillEntry.value.luckyHitCount,
                },
              )
              .toList();

          // Convert timeline to serializable format
          // Only send timeline if this is the selected player to save bandwidth
          Map<String, dynamic>? timelineMap;
          if (_selectedPlayerUid != null &&
              uid.toString() == _selectedPlayerUid) {
            timelineMap = {};
            dpsData.timeline.forEach((key, value) {
              timelineMap![key.toString()] = {
                'd': value.damage,
                'h': value.heal,
                't': value.taken,
                'sd': value.skillDamage,
                'sh': value.skillHeal,
              };
            });
          }

          // Convert per-target breakdown for selected player
          List<Map<String, dynamic>>? targetsList;
          if (_selectedPlayerUid != null &&
              uid.toString() == _selectedPlayerUid) {
            targetsList = dpsData.targets.entries
                .where(
                  (te) => te.key != uid,
                ) // filter out self-targets (self-heal)
                .map(
                  (te) => {
                    'uid': te.key.toString(),
                    'name': _resolveTargetName(te.key),
                    'totalDamage': te.value.totalDamage.toInt(),
                    'totalHeal': te.value.totalHeal.toInt(),
                    'hitCount': te.value.hitCount,
                    'critHitCount': te.value.critHitCount,
                    'luckyHitCount': te.value.luckyHitCount,
                    'skills': te.value.skills.entries
                        .map(
                          (se) => {
                            'skillId': se.key,
                            'totalDamage': se.value.totalDamage.toInt(),
                            'totalHeal': se.value.totalHeal.toInt(),
                            'hitCount': se.value.hitCount,
                            'critHitCount': se.value.critHitCount,
                            'luckyHitCount': se.value.luckyHitCount,
                          },
                        )
                        .toList(),
                  },
                )
                .toList();
          }

          return {
            'uid': uid.toString(), // Add UID as string for serialization
            'name': info?.name ?? "Unknown",
            'isMe': uid == storage.currentPlayerUuid,
            'classId': info?.professionId ?? 0,
            'dps': dpsData.simpleDps,
            'total': dpsData.totalAttackDamage.toInt(),
            'hps': dpsData.simpleHps,
            'totalHeal': dpsData.totalHeal.toInt(),
            'takenDps': dpsData.simpleTakenDps,
            'totalTaken': dpsData.totalTakenDamage.toInt(),
            'activeCombatTicks': dpsData.activeCombatTicks,
            'totalHitCount': dpsData.totalHitCount,
            'critHitCount': dpsData.critHitCount,
            'luckyHitCount': dpsData.luckyHitCount,
            'level': info?.level ?? 0,
            'combatPower': info?.combatPower ?? 0,
            'rankLevel': info?.rankLevel ?? 0,
            'critical': info?.critical ?? 0,
            'lucky': info?.lucky ?? 0,
            'attack': info?.attack ?? 0,
            'defense': info?.defense ?? 0,
            'haste': info?.haste ?? 0,
            'hastePct': info?.hastePct ?? 0,
            'mastery': info?.mastery ?? 0,
            'masteryPct': info?.masteryPct ?? 0,
            'versatility': info?.versatility ?? 0,
            'versatilityPct': info?.versatilityPct ?? 0,
            'seasonStrength': info?.seasonStrength ?? 0,
            'maxHp': info?.maxHp?.toInt() ?? 0,
            'hp': info?.hp?.toInt() ?? 0,
            'skills': skillsList,
            'timeline': timelineMap,
            'targets': targetsList,
          };
        })
        .toList();

    final combatDuration = storage.currentCombatDuration;

    // Serialize monsters — only send monsters with useful display info
    final monsters = storage.monsterInfoDatas.values
        .where((m) {
          final hasHp = m.maxHp != null && m.maxHp! > Int64.ZERO;
          final hasLevel = m.level != null && m.level! > 0;
          if (!hasHp && !hasLevel) return false;
          if (m.isSummon) return false;
          if (m.name == null || m.name!.isEmpty) return false;
          if (m.name!.contains('Resonance')) return false;
          return true;
        })
        .map(
          (m) => {
            'uid': m.uid.toString(),
            'templateId': m.templateId,
            'name': m.name,
            'level': m.level,
            'hp': m.hp?.toString(),
            'maxHp': m.maxHp?.toString(),
            'pos_x': m.position?['x']?.toDouble(),
            'pos_y': m.position?['y']?.toDouble(),
            'pos_z': m.position?['z']?.toDouble(),
          },
        )
        .toList();

    // Report HP for known bosses/creatures to bptimer.com
    _reportKnownMobsHp(storage);

    // Current Player Position
    final myUid = storage.currentPlayerUuid;
    final myPos = storage.playerInfoDatas[myUid]?.position;

    // Debug: Log first player to check UID transmission
    if (players.isNotEmpty) {
      // _logger.log("First player data: ${players.first}");
      // _logger.log("Current player UUID: ${storage.currentPlayerUuid}");
    }

    // Don't send selectedPlayerUid in regular updates to avoid overwriting close action
    // Include screen dimensions for overlay anchor calculations
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screenSizeDp = view.physicalSize / view.devicePixelRatio;

    FlutterOverlayWindow.shareData({
      'players': players,
      'combatTime': combatDuration.inSeconds,
      'lineId': storage.lineId,
      'monsters': monsters,
      'myPos': myPos,
      'myUid': myUid.toString(),
      'screenWidth': screenSizeDp.width,
      'screenHeight': screenSizeDp.height,
    });
  }

  Future<void> _updateOverlayWithSelection() async {
    final storage = DataStorage();
    storage.checkTimeout();

    final players = storage.fullDpsDatas.entries
        .where(
          (e) =>
              e.value.totalAttackDamage.toInt() > 0 ||
              e.value.totalHeal.toInt() > 0 ||
              e.value.totalTakenDamage.toInt() > 0,
        )
        .map((e) {
          final uid = e.key;
          final dpsData = e.value;
          final info = storage.getPlayerInfoSync(uid);

          // Convert skills to serializable format
          final skillsList = dpsData.skills.entries
              .map(
                (skillEntry) => {
                  'skillId': skillEntry.key,
                  'totalDamage': skillEntry.value.totalDamage.toInt(),
                  'totalHeal': skillEntry.value.totalHeal.toInt(),
                  'hitCount': skillEntry.value.hitCount,
                  'critHitCount': skillEntry.value.critHitCount,
                  'luckyHitCount': skillEntry.value.luckyHitCount,
                },
              )
              .toList();

          // Convert timeline to serializable format
          // Only send timeline if this is the selected player to save bandwidth
          Map<String, dynamic>? timelineMap;
          if (_selectedPlayerUid != null &&
              uid.toString() == _selectedPlayerUid) {
            timelineMap = {};
            dpsData.timeline.forEach((key, value) {
              timelineMap![key.toString()] = {
                'd': value.damage,
                'h': value.heal,
                't': value.taken,
                'sd': value.skillDamage,
                'sh': value.skillHeal,
              };
            });
          }

          // Convert per-target breakdown for selected player
          List<Map<String, dynamic>>? targetsList;
          if (_selectedPlayerUid != null &&
              uid.toString() == _selectedPlayerUid) {
            targetsList = dpsData.targets.entries
                .where((te) => te.key != uid) // filter out self-targets
                .map(
                  (te) => {
                    'uid': te.key.toString(),
                    'name': _resolveTargetName(te.key),
                    'totalDamage': te.value.totalDamage.toInt(),
                    'totalHeal': te.value.totalHeal.toInt(),
                    'hitCount': te.value.hitCount,
                    'critHitCount': te.value.critHitCount,
                    'luckyHitCount': te.value.luckyHitCount,
                    'skills': te.value.skills.entries
                        .map(
                          (se) => {
                            'skillId': se.key,
                            'totalDamage': se.value.totalDamage.toInt(),
                            'totalHeal': se.value.totalHeal.toInt(),
                            'hitCount': se.value.hitCount,
                            'critHitCount': se.value.critHitCount,
                            'luckyHitCount': se.value.luckyHitCount,
                          },
                        )
                        .toList(),
                  },
                )
                .toList();
          }

          return {
            'uid': uid.toString(),
            'name': info?.name ?? "Unknown",
            'isMe': uid == storage.currentPlayerUuid,
            'classId': info?.professionId ?? 0,
            'dps': dpsData.simpleDps,
            'total': dpsData.totalAttackDamage.toInt(),
            'hps': dpsData.simpleHps,
            'totalHeal': dpsData.totalHeal.toInt(),
            'takenDps': dpsData.simpleTakenDps,
            'totalTaken': dpsData.totalTakenDamage.toInt(),
            'activeCombatTicks': dpsData.activeCombatTicks,
            'totalHitCount': dpsData.totalHitCount,
            'critHitCount': dpsData.critHitCount,
            'luckyHitCount': dpsData.luckyHitCount,
            'level': info?.level ?? 0,
            'combatPower': info?.combatPower ?? 0,
            'rankLevel': info?.rankLevel ?? 0,
            'critical': info?.critical ?? 0,
            'lucky': info?.lucky ?? 0,
            'attack': info?.attack ?? 0,
            'defense': info?.defense ?? 0,
            'haste': info?.haste ?? 0,
            'hastePct': info?.hastePct ?? 0,
            'mastery': info?.mastery ?? 0,
            'masteryPct': info?.masteryPct ?? 0,
            'versatility': info?.versatility ?? 0,
            'versatilityPct': info?.versatilityPct ?? 0,
            'seasonStrength': info?.seasonStrength ?? 0,
            'maxHp': info?.maxHp?.toInt() ?? 0,
            'hp': info?.hp?.toInt() ?? 0,
            'skills': skillsList,
            'timeline': timelineMap,
            'targets': targetsList,
          };
        })
        .toList();

    final combatDuration = storage.currentCombatDuration;

    // Send with selectedPlayerUid
    _logger.log("Sending selectedPlayerUid to overlay: $_selectedPlayerUid");
    FlutterOverlayWindow.shareData({
      'players': players,
      'combatTime': combatDuration.inSeconds,
      'lineId': storage.lineId,
      'selectedPlayerUid': _selectedPlayerUid,
    });
  }

  /// Report HP of known bosses/creatures to bptimer.com
  /// Called from _updateOverlay every 500ms — throttled inside BPTimerService
  void _reportKnownMobsHp(DataStorage storage) {
    // Detect line change and clear throttle
    if (storage.lineId != _lastReportedLineId) {
      if (_lastReportedLineId != 0) {
        _bpTimerService.clearReportThrottle();
      }
      _lastReportedLineId = storage.lineId;
    }

    final lineId = storage.lineId;
    if (lineId <= 0) return; // Not on a line yet

    for (final monster in storage.monsterInfoDatas.values) {
      if (monster.templateId == null) continue;
      if (!_bpTimerService.isKnownMob(monster.templateId!)) continue;
      if (monster.isDead) continue;

      // Need both HP and maxHP to compute percentage
      final hp = monster.hp;
      final maxHp = monster.maxHp;
      if (hp == null || maxHp == null || maxHp == Int64.ZERO) continue;

      final hpPercent = (hp.toDouble() / maxHp.toDouble()) * 100.0;

      _bpTimerService.reportHp(
        monsterId: monster.templateId!,
        hpPercent: hpPercent,
        line: lineId,
        posX: monster.position?['x'] ?? 0.0,
        posY: monster.position?['y'] ?? 0.0,
        posZ: monster.position?['z'] ?? 0.0,
      );
    }
  }

  Future<void> _onPacketData(dynamic event) async {
    if (event is Uint8List) {
      _packetAnalyzer.processPacket(event);
    } else if (event is List<int>) {
      _packetAnalyzer.processPacket(Uint8List.fromList(event));
    } else if (event is String) {
      try {
        final bytes = _hexToBytes(event);
        _packetAnalyzer.processPacket(bytes);
      } catch (e) {
        _logger.error("Error processing packet", error: e);
      }
    }
  }

  void _onUpstreamData(dynamic event) {
    Uint8List data;
    if (event is Uint8List) {
      data = event;
    } else if (event is List<int>) {
      data = Uint8List.fromList(event);
    } else {
      return;
    }

    // Only log non-heartbeat data (heartbeats are 6 bytes)
    // Feed into a second PacketAnalyzerV2 (port 5003 only now)
    _otherSessionAnalyzer.processPacket(data);
  }

  Uint8List _hexToBytes(String hex) {
    final buffer = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      buffer[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return buffer;
  }

  Future<void> _startOverlay() async {
    final bool status = await FlutterOverlayWindow.isPermissionGranted();
    if (!status) {
      await FlutterOverlayWindow.requestPermission();
      return;
    }

    if (await FlutterOverlayWindow.isActive()) return;

    await FlutterOverlayWindow.showOverlay(
      enableDrag: false, // Disable native drag to allow content interaction
      overlayTitle: "bluemetersea DPS",
      overlayContent: "DPS Meter Active",
      flag: OverlayFlag.defaultFlag,
      alignment: OverlayAlignment.topLeft,
      visibility: NotificationVisibility.visibilityPublic,
      positionGravity: PositionGravity.none,
      height: 400,
      width: 600,
    );

    // Move to a safe initial position (logical pixels)
    await Future.delayed(const Duration(milliseconds: 100));
    await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 100));
  }

  Future<void> _startVpn() async {
    try {
      await platform.invokeMethod('startVpn');
      setState(() {
        _isVpnRunning = true;
      });

      _packetSubscription = eventChannel.receiveBroadcastStream().listen(
        _onPacketData,
      );
      _upstreamSubscription = upstreamEventChannel
          .receiveBroadcastStream()
          .listen(_onUpstreamData);
    } on PlatformException catch (e) {
      _logger.error("Failed to start VPN", error: e.message);
    }
  }

  Future<void> _stopVpn() async {
    try {
      await platform.invokeMethod('stopVpn');
      setState(() {
        _isVpnRunning = false;
      });
      _packetSubscription?.cancel();
      _upstreamSubscription?.cancel();
    } on PlatformException catch (e) {
      _logger.error("Failed to stop VPN", error: e.message);
    }
  }

  Future<void> _toggleService() async {
    if (_isVpnRunning) {
      await _stopVpn();
      await FlutterOverlayWindow.closeOverlay();
    } else {
      final bool status = await FlutterOverlayWindow.isPermissionGranted();
      if (!status) {
        await FlutterOverlayWindow.requestPermission();
        return;
      }

      await _startOverlay();
      await _startVpn();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('bluemeterseaSEA Mobile')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
                backgroundColor: _isVpnRunning ? Colors.red : Colors.green,
              ),
              onPressed: _toggleService,
              child: Text(
                _isVpnRunning
                    ? TranslationService().translate('Stop')
                    : TranslationService().translate('Start'),
                style: const TextStyle(fontSize: 24, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
