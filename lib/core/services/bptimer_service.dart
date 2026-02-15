import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/hunt_mob.dart';
import '../state/data_storage.dart';

/// Service to interact with bptimer.com API for mob tracking
class BPTimerService extends ChangeNotifier {
  static final BPTimerService _instance = BPTimerService._internal();
  factory BPTimerService() => _instance;
  BPTimerService._internal();

  static const String _baseUrl = 'https://db.bptimer.com/api';
  static const String _region = 'NA';

  // API key injected at build time via --dart-define-from-file
  static const String _apiKey = String.fromEnvironment('BPTIMER_API_KEY');

  List<HuntMob> _mobs = [];
  // mobId -> list of channel statuses
  Map<String, List<MobChannelStatus>> _channelStatuses = {};

  // Cache: monsterId (in-game ID) -> HuntMob for quick lookup
  Map<int, HuntMob> _mobsByMonsterId = {};
  bool _mobsCached = false;
  DateTime? _mobsCacheTime;
  static const Duration _mobsCacheDuration = Duration(hours: 1);

  // HP report throttle: monsterId -> last reported 5% bucket
  // e.g. 28% -> bucket 25, 20% -> bucket 20
  final Map<String, int> _lastReportedBucket = {};

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  bool _isConnected = false;
  bool _isLoading = false;
  String? _error;

  // SSE fields
  http.Client? _sseClient;
  StreamSubscription? _sseSubscription;

  List<HuntMob> get mobs => _mobs;
  Map<String, List<MobChannelStatus>> get channelStatuses => _channelStatuses;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Check if a monster (by in-game templateId) is a known boss/creature
  bool isKnownMob(int monsterId) => _mobsByMonsterId.containsKey(monsterId);

  /// Get HuntMob by in-game monster ID
  HuntMob? getMobByMonsterId(int monsterId) => _mobsByMonsterId[monsterId];

  /// Get bosses only
  List<HuntMob> get bosses => _mobs.where((m) => m.isBoss).toList();

  /// Get magical creatures only
  List<HuntMob> get magicalCreatures => _mobs.where((m) => m.isMagicalCreature).toList();

  /// Get top 3 channels with HP > 0 for a given mob, sorted by HP ascending
  List<MobChannelStatus> getTopChannels(String mobId) {
    final statuses = _channelStatuses[mobId] ?? [];
    final alive = statuses.where((s) => s.lastHp > 0 && s.lastUpdate.isAfter(DateTime.now().subtract(const Duration(minutes: 5)))).toList();
    alive.sort((a, b) => a.lastHp.compareTo(b.lastHp));
    return alive.take(3).toList();
  }

  /// Load mob list from API (cached for 1 hour)
  Future<void> loadMobs({bool force = false}) async {
    // Return cached data if still valid
    if (!force && _mobsCached && _mobsCacheTime != null) {
      if (DateTime.now().difference(_mobsCacheTime!) < _mobsCacheDuration) {
        return;
      }
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/collections/mobs/records?perPage=100'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;
        _mobs = items.map((item) => HuntMob.fromJson(item)).toList();
        
        // Build lookup map by in-game monster ID
        _mobsByMonsterId = {for (final m in _mobs) m.monsterId: m};
        _mobsCached = true;
        _mobsCacheTime = DateTime.now();

        // Sort: bosses first, then magical creatures, alphabetically within each group
        _mobs.sort((a, b) {
          if (a.type != b.type) {
            return a.isBoss ? -1 : 1;
          }
          return a.name.compareTo(b.name);
        });

        // Load channel statuses for all mobs
        await _loadChannelStatuses();
      } else {
        _error = 'Failed to load mobs: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'Error loading mobs: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Ensure mobs are loaded (uses cache if available)
  Future<void> ensureMobsLoaded() => loadMobs();

  /// Report HP for a known boss/creature to bptimer.com
  ///
  /// Only sends a report when HP crosses a 5% boundary downward.
  /// e.g. 28% -> waits until 25%, then next report at 20%, etc.
  ///
  /// [monsterId] - In-game template ID of the monster
  /// [hpPercent] - Current HP percentage (0-100)
  /// [line] - Current channel/line number
  /// [posX], [posY], [posZ] - Monster position
  /// [uid] - Player's in-game UID
  Future<void> reportHp({
    required int monsterId,
    required double hpPercent,
    required int line,
    required double posX,
    required double posY,
    required double posZ,
  }) async {
    // Only report for known mobs
    if (!isKnownMob(monsterId)) return;

    // Ensure we have the API key
    if (_apiKey.isEmpty) {
      debugPrint('BPTimer: API key not configured');
      return;
    }

    // Get account info from DataStorage
    final storage = DataStorage();
    final accountId = storage.accountId;
    final playerUid = storage.currentPlayerUuid;

    if (accountId == null || accountId.isEmpty) {
      debugPrint('BPTimer: accountId not available yet');
      return;
    }

    // Throttle: compute 5% bucket (floor to nearest 5)
    final int hpPctInt = hpPercent.floor();
    final int bucket = (hpPctInt ~/ 5) * 5;

    // Create a unique key per monster instance + line
    final throttleKey = '${monsterId}_$line';

    final lastBucket = _lastReportedBucket[throttleKey];
    if (lastBucket != null && bucket >= lastBucket) {
      // Haven't crossed to a lower 5% bucket yet, skip
      return;
    }

    // Update the last reported bucket
    _lastReportedBucket[throttleKey] = bucket;

    // Send the report (fire and forget, ignore 200/403)
    try {
      await http.post(
        Uri.parse('$_baseUrl/create-hp-report'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': _apiKey,
        },
        body: json.encode({
          'monster_id': monsterId,
          'hp_pct': bucket,
          'line': line,
          'pos_x': posX,
          'pos_y': posY,
          'pos_z': posZ,
          'account_id': accountId,
          'uid': playerUid.toString(),
        }),
      );
      // Intentionally ignore response (200 = ok, 403 = already reported by someone else)
    } catch (e) {
      debugPrint('BPTimer: Error reporting HP: $e');
    }
  }

  /// Clear throttle state (e.g. on line change or mob respawn)
  void clearReportThrottle([String? throttleKey]) {
    if (throttleKey != null) {
      _lastReportedBucket.remove(throttleKey);
    } else {
      _lastReportedBucket.clear();
    }
  }

  /// Load channel statuses for all mobs
  Future<void> _loadChannelStatuses() async {
    if (_mobs.isEmpty) return;

    // Build filter string with all mob IDs
    final filterParts = _mobs.map((m) => "mob = '${m.id}'").join(' || ');
    final filter = '($filterParts) && region = \'$_region\'';

    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/collections/mob_channel_status/records?page=1&perPage=1000&skipTotal=true&filter=${Uri.encodeComponent(filter)}',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;

        _channelStatuses = {};
        for (final item in items) {
          final status = MobChannelStatus.fromJson(item);
          _channelStatuses.putIfAbsent(status.mobId, () => []);
          _channelStatuses[status.mobId]!.add(status);
        }
      }
    } catch (e) {
      debugPrint('Error loading channel statuses: $e');
    }
  }

  /// Connect to SSE realtime endpoint for live updates
  void connectRealtime() {
    if (_isConnected) return;

    _connectSSE();
  }

  void _connectSSE() async {
    try {
      _sseClient = http.Client();
      final request = http.Request('GET', Uri.parse('$_baseUrl/realtime'));
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final streamedResponse = await _sseClient!.send(request);

      String buffer = '';

      _sseSubscription = streamedResponse.stream
          .transform(utf8.decoder)
          .listen(
        (chunk) {
          buffer += chunk;

          // Process complete SSE messages
          while (buffer.contains('\n\n')) {
            final endIndex = buffer.indexOf('\n\n');
            final message = buffer.substring(0, endIndex);
            buffer = buffer.substring(endIndex + 2);

            String? currentEvent;
            String? currentData;

            for (final line in message.split('\n')) {
              if (line.startsWith('event:')) {
                currentEvent = line.substring(6).trim();
              } else if (line.startsWith('data:')) {
                currentData = line.substring(5).trim();
              }
            }

            if (currentEvent == 'PB_CONNECT' && currentData != null) {
              _handlePBConnect(currentData!);
            } else if (currentEvent == 'mob_hp_updates' && currentData != null) {
              _handleHpUpdate(currentData!);
            }
          }
        },
        onError: (error) {
          debugPrint('SSE error: $error');
          _isConnected = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 5), () {
            if (!_isConnected) _connectSSE();
          });
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 5), () {
            if (!_isConnected) _connectSSE();
          });
        },
      );
    } catch (e) {
      debugPrint('SSE connection error: $e');
      _isConnected = false;
      notifyListeners();
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isConnected) _connectSSE();
      });
    }
  }

  /// Handle PB_CONNECT: extract clientId and subscribe to mob_hp_updates
  void _handlePBConnect(String dataStr) async {
    try {
      final data = json.decode(dataStr);
      final clientId = data['clientId'] as String?;
      if (clientId == null) return;

      debugPrint('SSE connected with clientId: $clientId');

      // Subscribe to mob_hp_updates via POST /api/realtime
      final response = await http.post(
        Uri.parse('$_baseUrl/realtime'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'clientId': clientId,
          'subscriptions': ['mob_hp_updates'],
        }),
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        debugPrint('Subscribed to mob_hp_updates');
        _isConnected = true;
      } else {
        debugPrint('Subscription failed: ${response.statusCode} ${response.body}');
        // Fallback: try subscribing to the collection directly
        final fallbackResponse = await http.post(
          Uri.parse('$_baseUrl/realtime'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'clientId': clientId,
            'subscriptions': ['mob_channel_status/*'],
          }),
        );
        if (fallbackResponse.statusCode == 204 || fallbackResponse.statusCode == 200) {
          debugPrint('Subscribed to mob_channel_status/*');
          _isConnected = true;
        } else {
          debugPrint('Fallback subscription also failed: ${fallbackResponse.statusCode}');
          _isConnected = true; // Still connected to SSE, just no subscription
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error handling PB_CONNECT: $e');
    }
  }

  /// Handle HP update from realtime data
  /// Format: [["mobId", channelNumber, hp, unknown], ...]
  void _handleHpUpdate(String dataStr) {
    try {
      final updates = json.decode(dataStr) as List;
      bool changed = false;

      for (final update in updates) {
        if (update is! List || update.length < 3) continue;

        final mobId = update[0] as String;
        final channelNumber = update[1] as int;
        final hp = update[2] as int;

        // Find existing channel status and update it
        final statuses = _channelStatuses.putIfAbsent(mobId, () => []);
        final existingIndex = statuses.indexWhere(
          (s) => s.channelNumber == channelNumber,
        );

        if (existingIndex >= 0) {
          statuses[existingIndex].lastHp = hp;
          statuses[existingIndex].lastUpdate = DateTime.now();
        } else {
          // Create new channel status entry
          statuses.add(MobChannelStatus(
            id: '${mobId}_ch$channelNumber',
            mobId: mobId,
            channelNumber: channelNumber,
            lastHp: hp,
            lastUpdate: DateTime.now(),
            region: _region,
          ));
        }
        changed = true;
      }

      if (changed) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error handling HP update: $e');
    }
  }

  /// Disconnect from realtime updates
  void disconnect() {
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _sseClient?.close();
    _sseClient = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
    _isConnected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
