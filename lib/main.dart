import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:fixnum/fixnum.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/analyze/packet_analyzer_v2.dart';
import 'core/state/data_storage.dart';
import 'core/models/classes.dart';
import 'core/models/dps_data.dart';
import 'core/models/player_info.dart';
import 'core/services/logger_service.dart';
import 'core/services/translation_service.dart';
import 'widgets/player_detail_card.dart';

void main() {
  runApp(const MyApp());
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: OverlayWidget()),
  );
}

class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget>
    with SingleTickerProviderStateMixin {
  final LoggerService _logger = LoggerService();
  late TabController _tabController;
  List<Map<String, dynamic>> _players = [];
  int _combatTime = 0;
  String? _selectedPlayerUid; // UID du joueur sélectionné pour la carte de détails

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
    _tabController = TabController(length: 3, vsync: this);
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
          // Update selectedPlayerUid when it's explicitly sent
          if (event.containsKey('selectedPlayerUid')) {
            final newUid = event['selectedPlayerUid'] as String?;
            _logger.log("Overlay received selectedPlayerUid: $newUid");
            
            // If switching to detail view, save current window size
            if (newUid != null && _selectedPlayerUid == null) {
              _saveCurrentWindowSize();
            }
            
            _selectedPlayerUid = newUid;
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
    _tabController.dispose();
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
    int tabIndex = 0;
    try {
      if (_tabController.length > 0) {
        tabIndex = _tabController.index;
      }
    } catch (e) {
      // ignore
    }

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
            Column(
              children: [
                // Title Bar
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
                    height: 32, // Reduced height
                    color: Colors.transparent, // Hit test
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TabBar(
                            controller: _tabController,
                            labelPadding: EdgeInsets.zero,
                            indicatorSize: TabBarIndicatorSize.label,
                            indicatorColor: Colors.transparent,
                            dividerColor: Colors.transparent,
                            labelColor: Colors.blue,
                            unselectedLabelColor: Colors.white,
                            tabs: const [
                              Tab(child: Icon(Icons.flash_on, size: 16)), // DPS (Sword replacement)
                              Tab(child: Icon(Icons.shield, size: 16)),
                              Tab(child: Icon(Icons.local_hospital, size: 16)),
                            ],
                          ),
                        ),
                        // Timer
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _formatTime(_combatTime),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                            ),
                          ),
                        ),
                        // Actions
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
                                child: Icon(Icons.remove, size: 16, color: Colors.white70),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                 final sendPort = IsolateNameServer.lookupPortByName('overlay_communication_port');
                                 if (sendPort != null) {
                                   sendPort.send("RESET");
                                 } else {
                                   debugPrint("Could not find communication port");
                                 }
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2),
                                child: Icon(Icons.refresh, size: 16, color: Colors.white70),
                              ),
                            ),
                            // GestureDetector(
                            //   onTap: () async {
                            //     await FlutterOverlayWindow.closeOverlay();
                            //   },
                            //   child: const Padding(
                            //     padding: EdgeInsets.symmetric(horizontal: 2),
                            //     child: Icon(Icons.settings, size: 16, color: Colors.white70),
                            //   ),
                            // ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      PlayerList(players: _players, metricType: "dps"),
                      PlayerList(players: _players, metricType: "taken"),
                      PlayerList(players: _players, metricType: "heal"),
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

  String _formatTime(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
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

  final LoggerService _logger = LoggerService();

  bool _isVpnRunning = false;
  StreamSubscription? _packetSubscription;
  late PacketAnalyzerV2 _packetAnalyzer;
  Timer? _overlayUpdateTimer;
  ReceivePort? _receivePort;
  String? _selectedPlayerUid; // UID du joueur sélectionné pour affichage de la carte

  @override
  void initState() {
    super.initState();
    _packetAnalyzer = PacketAnalyzerV2(DataStorage());
    
    // Setup communication port
    _receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping('overlay_communication_port'); // Clean up old mapping if any
    IsolateNameServer.registerPortWithName(_receivePort!.sendPort, 'overlay_communication_port');
    _receivePort!.listen((message) {
      _logger.log("HomePage received message: $message");
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
    .where((e) => e.value.totalAttackDamage > Int64.ZERO || e.value.totalHeal > Int64.ZERO || e.value.totalTakenDamage > Int64.ZERO)
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

    // Debug: Log first player to check UID transmission
    if (players.isNotEmpty) {
      // _logger.log("First player data: ${players.first}");
      // _logger.log("Current player UUID: ${storage.currentPlayerUuid}");
    }
    
    // Don't send selectedPlayerUid in regular updates to avoid overwriting close action
    FlutterOverlayWindow.shareData({
      'players': players,
      'combatTime': combatDuration.inSeconds,
    });
  }

  Future<void> _updateOverlayWithSelection() async {
    final storage = DataStorage();
    storage.checkTimeout();

    final players = storage.fullDpsDatas.entries
    .where((e) => e.value.totalAttackDamage > Int64.ZERO || e.value.totalHeal > Int64.ZERO || e.value.totalTakenDamage > Int64.ZERO)
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
      'selectedPlayerUid': _selectedPlayerUid,
    });
  }

  Future<void> _onPacketData(dynamic event) async {
    // debugPrint("Received packet data: ${event.runtimeType}");
    if (event is Uint8List) {
      // debugPrint("Processing ${event.length} bytes");
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

class PlayerList extends StatefulWidget {
  final List<Map<String, dynamic>> players;
  final String metricType;

  const PlayerList({
    super.key,
    required this.players,
    required this.metricType,
  });

  @override
  State<PlayerList> createState() => _PlayerListState();
}

class _PlayerListState extends State<PlayerList> {
  final LoggerService _logger = LoggerService();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine keys based on metricType
    String rateKey = 'dps';
    String totalKey = 'total';
    if (widget.metricType == 'heal') {
      rateKey = 'hps';
      totalKey = 'totalHeal';
    } else if (widget.metricType == 'taken') {
      rateKey = 'takenDps';
      totalKey = 'totalTaken';
    }

    // Filter
    var filtered = widget.players.where((p) {
      final total = (p[totalKey] as num?)?.toDouble() ?? 0.0;
      return total > 0;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(TranslationService().translate('NoData'), style: const TextStyle(color: Colors.white54, fontSize: 10)),
      );
    }

    // Sort
    filtered.sort((a, b) {
      final valA = (a[totalKey] as num?)?.toDouble() ?? 0.0;
      final valB = (b[totalKey] as num?)?.toDouble() ?? 0.0;
      return valB.compareTo(valA);
    });

    // Calculate Max for Progress Bar
    double maxVal = 0.0;
    if (filtered.isNotEmpty) {
      maxVal = (filtered.first[totalKey] as num?)?.toDouble() ?? 0.0;
    }
    if (maxVal == 0) maxVal = 1.0;

    // Find "Me"
    int myIndex = filtered.indexWhere((p) => p['isMe'] == true);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              itemCount: filtered.length,
              itemExtent: 18.0,
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                return _buildRow(filtered[index], index, maxVal, rateKey, totalKey);
              },
            ),
            if (myIndex != -1)
              AnimatedBuilder(
                animation: _scrollController,
                builder: (context, child) {
                  final double itemTop = myIndex * 18.0;
                  final double scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                  final double viewportHeight = constraints.maxHeight;
                  
                  // Show sticky if item is below the viewport
                  if (itemTop > scrollOffset + viewportHeight - 18.0) {
                     return Positioned(
                       bottom: 0,
                       left: 0,
                       right: 0,
                       child: Container(
                         color: Colors.black.withValues(alpha: 0.8),
                         child: _buildRow(filtered[myIndex], myIndex, maxVal, rateKey, totalKey),
                       ),
                     );
                  }
                  return const SizedBox.shrink();
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildRow(Map<String, dynamic> p, int index, double maxVal, String rateKey, String totalKey) {
    final cls = Classes.fromId(p['classId']);
    final val = (p[rateKey] as num?)?.toDouble() ?? 0.0;
    final total = (p[totalKey] as num?)?.toInt() ?? 0;
    final percent = (total / maxVal).clamp(0.0, 1.0);

    String name = p['name']?.toString() ?? "Unknown";
    if (p['isMe'] == true && (name == "Unknown" || name.isEmpty)) {
      name = "Moi";
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _logger.log("Row tapped - Full player data: $p");
        final uidStr = p['uid'] as String?;
        _logger.log("Row tapped - uid: $uidStr, name: $name");
        if (uidStr != null && uidStr.isNotEmpty) {
          // Envoyer un message au processus principal pour sélectionner ce joueur
          final sendPort = IsolateNameServer.lookupPortByName('overlay_communication_port');
          if (sendPort != null) {
            sendPort.send({'selectPlayer': uidStr});
            _logger.log("Sent selectPlayer message: $uidStr");
          } else {
            _logger.log("Could not find communication port");
          }
        }
      },
      child: Container(
        height: 18,
        padding: const EdgeInsets.only(bottom: 1),
        child: Stack(
          children: [
            FractionallySizedBox(
              widthFactor: percent,
              child: Container(
                color: _getClassColor(cls).withValues(alpha: 0.3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Container(width: 2, color: _getClassColor(cls)),
                  const SizedBox(width: 4),
                  Text(
                    "${index + 1}.",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                      shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (cls != Classes.unknown) ...[
                    Image.asset(
                      cls.iconPath,
                      width: 12,
                      height: 12,
                      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    "${_formatNumber(val)} / ${_formatNumber(total)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getClassColor(Classes cls) {
    switch (cls.role) {
      case Role.tank:
        return Colors.blue;
      case Role.heal:
        return Colors.green;
      case Role.dps:
        return Colors.red;
      default:
        return Colors.grey;
    }
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
}
