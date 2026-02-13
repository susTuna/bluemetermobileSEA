import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bluemeter_mobile/core/services/translation_service.dart';
import 'package:bluemeter_mobile/views/dps_view.dart';
import 'package:bluemeter_mobile/views/nearby_view.dart';
import 'package:bluemeter_mobile/views/tools_view.dart';
import 'package:bluemeter_mobile/widgets/player_detail_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:fixnum/fixnum.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/analyze/packet_analyzer_v2.dart';
import 'core/state/data_storage.dart';
import 'core/services/monster_name_service.dart';
import 'core/models/dps_data.dart';
import 'core/models/player_info.dart';

import 'core/services/logger_service.dart';

// ...

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MonsterNameService().load();
  
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
      child: const MaterialApp(debugShowCheckedModeBanner: false, home: OverlayWidget()),
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
  // late TabController _tabController; // Moved to DpsView
  List<Map<String, dynamic>> _players = [];
  int _combatTime = 0;
  int _lineId = 0;
  String? _selectedPlayerUid; 
  
  // Navigation State
  int _mainTabIndex = 0; // 0=DPS, 1=Nearby, 2=Tools
  int _dpsTabIndex = 0; // 0=DPS(sword), 1=Taken(shield), 2=Heal(cross)

  // Track window position
  double _windowX = 0;
  double _windowY = 0;
  
  // Store original window size before showing detail
  double _savedWidth = 600;
  double _savedHeight = 400;
  
  // Persistent positions
  double _fullX = 0;
  double _fullY = 100;
  double _miniX = 0;
  double _miniY = 100;

  // Drag helpers
  double _lastMoveX = 0;
  double _lastMoveY = 0;
  double _windowDeltaX = 0;
  double _windowDeltaY = 0;
  Size? _resizeStartWindowSize;
  Offset? _dragStartTouchPosition; // Keep for resize
  bool _isDragging = false;

  // Minimize state
  bool _isMinimized = false;
  double _restoredWidth = 600;
  double _restoredHeight = 400;

  @override
  void initState() {
    super.initState();
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
            // _logger.log("Overlay received selectedPlayerUid: $newUid");
            
            // If switching to detail view, save current window size
            if (newUid != null && _selectedPlayerUid == null) {
              _saveCurrentWindowSize();
            }
            
            _selectedPlayerUid = newUid;
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
                 final convertedPos = myPos.map((key, value) => 
                    MapEntry(key.toString(), (value as num).toDouble()));
                 
                 storage.setPlayerPosition(
                   storage.currentPlayerUuid, 
                   convertedPos,
                 );
               }
             }

             if (event.containsKey('monsters')) {
               final monsters = event['monsters'] as List?;
               if (monsters != null) {
                //  debugPrint("[Overlay Isolate] Received ${monsters.length} monsters.");
                 final incomingUids = <Int64>{};

                 for (var m in monsters) {
                   final map = m as Map;
                   final uid = Int64.parseInt(map['uid'] as String);
                   incomingUids.add(uid);

                   // Allow overlay to sync with main app truth, ignoring local graveyard
                   storage.ensureMonster(uid, forceRespawn: true);
                   
                   if (map['templateId'] != null) storage.setMonsterTemplateId(uid, map['templateId'] as int);
                   if (map['name'] != null) storage.setMonsterName(uid, map['name'] as String);
                   if (map['level'] != null) storage.setMonsterLevel(uid, map['level'] as int);
                   if (map['hp'] != null) storage.setMonsterHp(uid, Int64.parseInt(map['hp'] as String));
                   if (map['maxHp'] != null) storage.setMonsterMaxHp(uid, Int64.parseInt(map['maxHp'] as String));
                   if (map['isDead'] != null) storage.setMonsterIsDead(uid, map['isDead'] as bool);
                   
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
                       debugPrint("[Overlay] Removing stale monster $uid");
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

  Future<void> _savePosition() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isMinimized) {
      _miniX = _windowX;
      _miniY = _windowY;
      await prefs.setDouble('overlay_mini_x', _miniX);
      await prefs.setDouble('overlay_mini_y', _miniY);
    } else {
      _fullX = _windowX;
      _fullY = _windowY;
      await prefs.setDouble('overlay_full_x', _fullX);
      await prefs.setDouble('overlay_full_y', _fullY);
    }
  }

  Future<void> _saveSize() async {
    if (_isMinimized) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('overlay_width', _restoredWidth);
    await prefs.setDouble('overlay_height', _restoredHeight);
  }

  Future<void> _saveMinimizedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('overlay_minimized', _isMinimized);
  }

  void _saveCurrentWindowSize() {
    // Save current window size from _restoredWidth and _restoredHeight
    _savedWidth = _restoredWidth;
    _savedHeight = _restoredHeight;
    _logger.log("Saved window size: $_savedWidth" "x" "$_savedHeight");
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
      _logger.log("Restored window size: $_savedWidth" "x" "$_savedHeight");
    } catch (e) {
      _logger.error("Error restoring window size", error: e);
    }
  }

  @override
  void dispose() {
    // _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Si un joueur est sélectionné, afficher la carte de détails
    if (_selectedPlayerUid != null) {
      // Resize window for detail view
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resizeForDetail();
      });
      return _buildPlayerDetail();
    }
    
    // Sinon afficher la liste normale
    if (_isMinimized) {
      return _buildMinimized();
    }
    return _buildFull();
  }

  BoxDecoration get _windowDecoration => BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(0),
        // Border-left
        border: Border(
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.9),
            width: 0.5,
          ),
        ),
      );

  Widget _buildMinimized() {
    // Determine keys based on tab index
    // Default to DPS if controller not ready
    int tabIndex = _dpsTabIndex;

    String rateKey = 'dps';
    String totalKey = 'total';
    IconData headerIcon = Icons.flash_on;

    if (tabIndex == 1) { // Taken (matches TabBarView order)
      rateKey = 'takenDps';
      totalKey = 'totalTaken';
      headerIcon = Icons.shield;
    } else if (tabIndex == 2) { // Heal
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
        onPanStart: (details) async {
             _isDragging = false;
             try {
               final pos = await FlutterOverlayWindow.getOverlayPosition();
               _windowX = pos.x;
               _windowY = pos.y;
               _lastMoveX=details.globalPosition.dx;
               _lastMoveY=details.globalPosition.dy;
               _windowDeltaX=0;
               _windowDeltaY=0;
               _isDragging = true;
             } catch (e) {
               debugPrint("Error getting overlay position: $e");
             }
        },
        onPanUpdate: (details) {
             if (!_isDragging) return;
             final dpr = MediaQuery.of(context).devicePixelRatio;
             _windowDeltaX= details.globalPosition.dx-_lastMoveX;
             _windowDeltaY= details.globalPosition.dy - _lastMoveY;
             
             // Update local tracking
             _windowX += _windowDeltaX/dpr;
             _windowY += _windowDeltaY/dpr;
             _lastMoveX = details.globalPosition.dx;
             _lastMoveY = details.globalPosition.dy;

             FlutterOverlayWindow.moveOverlay(
               OverlayPosition(_windowX, _windowY),
             );
        },
        onPanEnd: (details) {
          _isDragging = false;
          _savePosition();
        },
        onTap: () async {
          setState(() {
            _isMinimized = false;
          });
          _saveMinimizedState();
          
          // Restore full position
          _windowX = _fullX;
          _windowY = _fullY;
          
          await FlutterOverlayWindow.resizeOverlay(
            _restoredWidth.toInt(),
            _restoredHeight.toInt(),
            false,
          );
          await FlutterOverlayWindow.moveOverlay(OverlayPosition(_windowX, _windowY));
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
                  Icon(headerIcon, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  if (myRank > 0)
                    Text(
                      "#$myRank",
                      style: const TextStyle(
                        color: Colors.white,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                   final sendPort = IsolateNameServer.lookupPortByName('overlay_communication_port');
                   if (sendPort != null) {
                     sendPort.send("RESET");
                   }
                },
                child: const Icon(Icons.refresh, size: 16, color: Colors.white70),
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
                  color: Colors.black.withValues(alpha: 0.6),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      // Tab 0: DPS Meter
                      _buildSideTab(0, Icons.bar_chart),
                      // Tab 1: Nearby (Radar)
                      _buildSideTab(1, Icons.radar),
                      // Tab 2: Tools (Module/Optimizer)
                      _buildSideTab(2, Icons.build),
                    ],
                  ),
                ),
                // Main Content Area
                Expanded(
                  child: Column(
                    children: [
                      // Draggable Title Bar / Header (Timer + Window Controls)
                      GestureDetector(
                        onPanStart: (details) async {
                          _isDragging = false;
                          try {
                            final pos = await FlutterOverlayWindow.getOverlayPosition();
                            // Convert physical position (from native) to logical pixels (for Flutter)
                            _windowX = pos.x;
                            _windowY = pos.y;
                            _lastMoveX=details.globalPosition.dx;
                            _lastMoveY=details.globalPosition.dy;
                            _windowDeltaX=0;
                            _windowDeltaY=0;
                            _isDragging = true;
                          } catch (e) {
                            debugPrint("Error getting overlay position: $e");
                          }
                        },
                        onPanUpdate: (details) {
                          if (!_isDragging) return;
                            final dpr = MediaQuery.of(context).devicePixelRatio;
                            
                          _windowDeltaX= details.globalPosition.dx-_lastMoveX;
                          _windowDeltaY= details.globalPosition.dy - _lastMoveY;
                          
                          _windowX += _windowDeltaX/dpr;
                          _windowY += _windowDeltaY/dpr;
                          _lastMoveX = details.globalPosition.dx;
                          _lastMoveY = details.globalPosition.dy;
                          
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween, // Push items to edges
                            children: [
                              // Line number (Left aligned in this area)
                              Text(
                                _lineId > 0 ? 'L${_lineId}' : '—',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                                ),
                              ),
                              // Window Actions (Right aligned)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () async {
                                      setState(() {
                                        _isMinimized = true;
                                      });
                                      _saveMinimizedState();
                                      
                                      // Restore mini position
                                      _windowX = _miniX;
                                      _windowY = _miniY;
                                      
                                      await FlutterOverlayWindow.resizeOverlay(135, 30, false);
                                      await FlutterOverlayWindow.moveOverlay(OverlayPosition(_windowX, _windowY));
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 2),
                                      child: Icon(Icons.remove, size: 14, color: Colors.white70),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () async {
                                       final sendPort = IsolateNameServer.lookupPortByName('overlay_communication_port');
                                       if (sendPort != null) {
                                         sendPort.send("RESET");
                                       }
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 2),
                                      child: Icon(Icons.refresh, size: 14, color: Colors.white70),
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
                                final sendPort = IsolateNameServer.lookupPortByName('overlay_communication_port');
                                if (sendPort != null) {
                                  sendPort.send({'selectPlayer': uid});
                                }
                              },
                              onTabChanged: (index) {
                                _dpsTabIndex = index;
                              },
                            ),
                            const NearbyView(),
                            const ToolsView(),
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
                  if (_resizeStartWindowSize == null || _dragStartTouchPosition == null) return;

                  final currentTouch = details.globalPosition;
                  final diff = currentTouch - _dragStartTouchPosition!;
                  
                  // Calculate new size in logical pixels
                  double newWidth = _resizeStartWindowSize!.width + diff.dx;
                  double newHeight = _resizeStartWindowSize!.height + diff.dy;

                  // Min size constraints (logical)
                  if (newWidth < 150) newWidth = 150;
                  if (newHeight < 100) newHeight = 100;

                  // Save for restore
                  _restoredWidth = newWidth;
                  _restoredHeight = newHeight;

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
                  child: const Icon(Icons.south_east, size: 14, color: Colors.white24),
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
    return GestureDetector(
      onTap: () {
        setState(() {
          _mainTabIndex = index;
        });
      },
      child: Container(
        height: 26,
        width: 26,
        color: isSelected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
        child: Icon(
          icon,
          color: isSelected ? Colors.blue : Colors.white54,
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
      ..activeCombatTicks = playerData['activeCombatTicks'] ?? 0;

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
        ..hitCount = skillMap['hitCount'] ?? 0;
      dpsData.skills[skillData.skillId] = skillData;
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
      maxHp: Int64(playerData['maxHp'] ?? 0),
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
          onDragStart: (details) async {
            _isDragging = false;
            try {
              final pos = await FlutterOverlayWindow.getOverlayPosition();
              _windowX = pos.x;
              _windowY = pos.y;
              _lastMoveX = details.globalPosition.dx;
              _lastMoveY = details.globalPosition.dy;
              _windowDeltaX = 0;
              _windowDeltaY = 0;
              _isDragging = true;
            } catch (e) {
              _logger.error("Error getting overlay position", error: e);
            }
          },
          onDragUpdate: (details) {
            if (!_isDragging) return;
            final dpr = MediaQuery.of(context).devicePixelRatio;
            
            _windowDeltaX = details.globalPosition.dx - _lastMoveX;
            _windowDeltaY = details.globalPosition.dy - _lastMoveY;
            
            _windowX += _windowDeltaX / dpr;
            _windowY += _windowDeltaY / dpr;
            _lastMoveX = details.globalPosition.dx;
            _lastMoveY = details.globalPosition.dy;
            
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
      title: 'BlueMeter Mobile',
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
  static const platform = MethodChannel('com.bluemeter.mobile/vpn');
  static const eventChannel = EventChannel(
    'com.bluemeter.mobile/packet_stream',
  );
  static const upstreamEventChannel = EventChannel(
    'com.bluemeter.mobile/upstream_stream',
  );

  final LoggerService _logger = LoggerService();

  bool _isVpnRunning = false;
  StreamSubscription? _packetSubscription;
  StreamSubscription? _upstreamSubscription;
  late PacketAnalyzerV2 _packetAnalyzer;
  late PacketAnalyzerV2 _otherSessionAnalyzer;
  Timer? _overlayUpdateTimer;
  ReceivePort? _receivePort;
  String? _selectedPlayerUid; // UID du joueur sélectionné pour affichage de la carte

  @override
  void initState() {
    super.initState();
    _packetAnalyzer = PacketAnalyzerV2(DataStorage());
    _otherSessionAnalyzer = PacketAnalyzerV2(DataStorage());
    
    // Setup communication port
    _receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping('overlay_communication_port'); // Clean up old mapping if any
    IsolateNameServer.registerPortWithName(_receivePort!.sendPort, 'overlay_communication_port');
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
    _overlayUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
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

  Future<void> _updateOverlay() async {
    final storage = DataStorage();
    storage.checkTimeout();

    // _logger.log("UpdateOverlay - CurrentPlayerUUID: ${storage.currentPlayerUuid}");
    // _logger.log("UpdateOverlay - fullDpsDatas count: ${storage.fullDpsDatas.length}");

    final players = storage.fullDpsDatas.entries
    .where((e) => e.value.totalAttackDamage.toInt() > 0 || e.value.totalHeal.toInt() > 0 || e.value.totalTakenDamage.toInt() > 0)
    .map((e) {
      final uid = e.key;
      final dpsData = e.value;
      // Use synchronous getter to avoid await overhead
      final info = storage.getPlayerInfoSync(uid);
      // _logger.log("UpdateOverlay - Processing UID: $uid, isMe: ${uid == storage.currentPlayerUuid}, Name: ${info?.name}");
      
      // Convert skills to serializable format
      final skillsList = dpsData.skills.entries.map((skillEntry) => {
        'skillId': skillEntry.key,
        'totalDamage': skillEntry.value.totalDamage.toInt(),
        'totalHeal': skillEntry.value.totalHeal.toInt(),
        'hitCount': skillEntry.value.hitCount,
      }).toList();
      
      // Convert timeline to serializable format
      // Only send timeline if this is the selected player to save bandwidth
      Map<String, dynamic>? timelineMap;
      if (_selectedPlayerUid != null && uid.toString() == _selectedPlayerUid) {
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
        'level': info?.level ?? 0,
        'combatPower': info?.combatPower ?? 0,
        'rankLevel': info?.rankLevel ?? 0,
        'critical': info?.critical ?? 0,
        'lucky': info?.lucky ?? 0,
        'maxHp': info?.maxHp?.toInt() ?? 0,
        'skills': skillsList,
        'timeline': timelineMap,
      };
    }).toList();

    final combatDuration = storage.currentCombatDuration;

    // Serialize monsters
    final monsters = storage.monsterInfoDatas.values.map((m) => {
        'uid': m.uid.toString(),
        'templateId': m.templateId,
        'name': m.name,
        'level': m.level,
        'hp': m.hp?.toString(),
        'maxHp': m.maxHp?.toString(),
        'pos_x': m.position?['x']?.toDouble(),
        'pos_y': m.position?['y']?.toDouble(),
        'pos_z': m.position?['z']?.toDouble(),
    }).toList();

    // Debug: Log monster count being sent
    // _logger.log("[Main Isolate] _updateOverlay sending ${monsters.length} monsters.");
    // debugPrint("[Main Isolate] _updateOverlay sending ${monsters.length} monsters.");

    // Current Player Position
    final myUid = storage.currentPlayerUuid;
    final myPos = storage.playerInfoDatas[myUid]?.position;

    // Debug: Log first player to check UID transmission
    if (players.isNotEmpty) {
      // _logger.log("First player data: ${players.first}");
      // _logger.log("Current player UUID: ${storage.currentPlayerUuid}");
    }
    
    // Don't send selectedPlayerUid in regular updates to avoid overwriting close action
    FlutterOverlayWindow.shareData({
      'players': players,
      'combatTime': combatDuration.inSeconds,
      'lineId': storage.lineId,
      'monsters': monsters,
      'myPos': myPos, 
      'myUid': myUid.toString(),
    });
  }

  Future<void> _updateOverlayWithSelection() async {
    final storage = DataStorage();
    storage.checkTimeout();

    final players = storage.fullDpsDatas.entries
    .where((e) => e.value.totalAttackDamage.toInt() > 0 || e.value.totalHeal.toInt() > 0 || e.value.totalTakenDamage.toInt() > 0)
    .map((e) {
      final uid = e.key;
      final dpsData = e.value;
      final info = storage.getPlayerInfoSync(uid);
      
      // Convert skills to serializable format
      final skillsList = dpsData.skills.entries.map((skillEntry) => {
        'skillId': skillEntry.key,
        'totalDamage': skillEntry.value.totalDamage.toInt(),
        'totalHeal': skillEntry.value.totalHeal.toInt(),
        'hitCount': skillEntry.value.hitCount,
      }).toList();
      
      // Convert timeline to serializable format
      // Only send timeline if this is the selected player to save bandwidth
      Map<String, dynamic>? timelineMap;
      if (_selectedPlayerUid != null && uid.toString() == _selectedPlayerUid) {
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
        'level': info?.level ?? 0,
        'combatPower': info?.combatPower ?? 0,
        'rankLevel': info?.rankLevel ?? 0,
        'critical': info?.critical ?? 0,
        'lucky': info?.lucky ?? 0,
        'maxHp': info?.maxHp?.toInt() ?? 0,
        'skills': skillsList,
        'timeline': timelineMap,
      };
    }).toList();

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

    debugPrint("[BM] Port5003 received: ${data.length} bytes");
    // Feed into a second PacketAnalyzerV2 that shares the same DataStorage
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
      overlayTitle: "BlueMeter DPS",
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
    await FlutterOverlayWindow.moveOverlay(
      const OverlayPosition(0, 100),
    );
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
      _upstreamSubscription = upstreamEventChannel.receiveBroadcastStream().listen(
        _onUpstreamData,
      );
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
      appBar: AppBar(
        title: const Text('BlueMeter Mobile'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                backgroundColor: _isVpnRunning ? Colors.red : Colors.green,
              ),
              onPressed: _toggleService,
              child: Text(
                _isVpnRunning ? TranslationService().translate('Stop') : TranslationService().translate('Start'),
                style: const TextStyle(fontSize: 24, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

