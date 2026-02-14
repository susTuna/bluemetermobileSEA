import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';

import '../core/models/monster_info.dart';
import '../core/state/data_storage.dart';
import '../core/services/translation_service.dart';

class NearbyView extends StatefulWidget {
  final bool isActive;

  const NearbyView({super.key, this.isActive = true});

  @override
  State<NearbyView> createState() => _NearbyViewState();
}

class _NearbyViewState extends State<NearbyView> {
  // Cache to avoid recomputing when tab is not active
  List<_MonsterEntry>? _cachedMonsters;
  int _lastDataHash = 0;

  String _formatDistance(double dist) {
    if (dist > 1000) {
      return "${(dist / 1000).toStringAsFixed(1)}km";
    }
    return "${dist.toStringAsFixed(1)}m";
  }

  String _formatHp(Int64? hp, Int64? maxHp) {
    if (hp == null) return "?";
    if (maxHp == null || maxHp == Int64.ZERO) return "?";
    final percent = (hp.toDouble() / maxHp.toDouble() * 100).toStringAsFixed(1);
    return "$percent%";
  }

  static double _calculateDistance(Map<String, double>? pos1, Map<String, double>? pos2) {
    if (pos1 == null || pos2 == null) return 99999.0;
    final dx = (pos1['x'] ?? 0) - (pos2['x'] ?? 0);
    final dy = (pos1['y'] ?? 0) - (pos2['y'] ?? 0);
    final dz = (pos1['z'] ?? 0) - (pos2['z'] ?? 0);
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Bearing angle (radians) from pos1 looking toward pos2 on the XZ plane.
  static double _calculateBearing(Map<String, double>? pos1, Map<String, double>? pos2) {
    if (pos1 == null || pos2 == null) return 0.0;
    final dx = (pos2['x'] ?? 0) - (pos1['x'] ?? 0);
    final dz = (pos2['z'] ?? 0) - (pos1['z'] ?? 0);
    return atan2(dx, dz); // 0 = north (+Z), positive = clockwise
  }

  bool _isValidMonster(MonsterInfo m) {
    if (m.isDead || (m.hp != null && m.hp! <= Int64.ZERO)) return false;
    if (m.isSummon) return false;
    final hasHp = m.maxHp != null && m.maxHp! > Int64.ZERO;
    final hasLevel = m.level != null && m.level! > 0;
    if (!hasHp && !hasLevel) return false;
    if (m.name == null || m.name!.isEmpty) return false;
    if (m.name!.contains('Resonance')) return false;
    return true;
  }

  int _computeHash(DataStorage storage) {
    // Simple hash based on monster count + first few positions to detect changes
    var h = storage.monsterInfoDatas.length;
    for (final m in storage.monsterInfoDatas.values.take(10)) {
      h ^= m.uid.hashCode;
      if (m.hp != null) h ^= m.hp.hashCode;
      if (m.position != null) {
        h ^= ((m.position!['x'] ?? 0) * 100).toInt();
        h ^= ((m.position!['z'] ?? 0) * 100).toInt();
      }
    }
    return h;
  }

  List<_MonsterEntry> _buildMonsterList(DataStorage storage) {
    final myUid = storage.currentPlayerUuid;
    final myPos = storage.playerInfoDatas[myUid]?.position;

    final entries = <_MonsterEntry>[];
    for (final m in storage.monsterInfoDatas.values) {
      if (!_isValidMonster(m)) continue;
      final dist = _calculateDistance(myPos, m.position);
      if (dist > 200) continue;
      final bearing = _calculateBearing(myPos, m.position);
      entries.add(_MonsterEntry(monster: m, distance: dist, bearing: bearing));
    }
    entries.sort((a, b) => a.distance.compareTo(b.distance));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataStorage>(
      builder: (context, storage, child) {
        // Optimisation: when tab is not active, return cached data or nothing
        if (!widget.isActive) {
          if (_cachedMonsters == null || _cachedMonsters!.isEmpty) {
            return Center(
              child: Text(
                TranslationService().translate('No nearby monsters'),
                style: const TextStyle(color: Colors.white54),
              ),
            );
          }
          return _buildList(_cachedMonsters!);
        }

        // Check if data actually changed
        final hash = _computeHash(storage);
        if (hash != _lastDataHash || _cachedMonsters == null) {
          _cachedMonsters = _buildMonsterList(storage);
          _lastDataHash = hash;
        }

        if (_cachedMonsters!.isEmpty) {
          return Center(
            child: Text(
              TranslationService().translate('No nearby monsters'),
              style: const TextStyle(color: Colors.white54),
            ),
          );
        }

        return _buildList(_cachedMonsters!);
      },
    );
  }

  Widget _buildList(List<_MonsterEntry> entries) {
    return ListView.builder(
      itemCount: entries.length,
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemBuilder: (context, index) {
        final e = entries[index];
        final m = e.monster;
        return _MonsterTile(
          monster: m,
          distance: e.distance,
          bearing: e.bearing,
          formatDistance: _formatDistance,
          formatHp: _formatHp,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Data holder
// ---------------------------------------------------------------------------
class _MonsterEntry {
  final MonsterInfo monster;
  final double distance;
  final double bearing; // relative to player facing (radians)

  const _MonsterEntry({
    required this.monster,
    required this.distance,
    required this.bearing,
  });
}

// ---------------------------------------------------------------------------
// Individual monster tile
// ---------------------------------------------------------------------------
class _MonsterTile extends StatelessWidget {
  final MonsterInfo monster;
  final double distance;
  final double bearing;
  final String Function(double) formatDistance;
  final String Function(Int64?, Int64?) formatHp;

  const _MonsterTile({
    required this.monster,
    required this.distance,
    required this.bearing,
    required this.formatDistance,
    required this.formatHp,
  });

  @override
  Widget build(BuildContext context) {
    final m = monster;
    final hpPct = m.hpPercent;
    final hpColor = hpPct < 0.3
        ? Colors.redAccent
        : (hpPct < 0.6 ? Colors.orangeAccent : Colors.greenAccent);

    // Distance-based opacity: closer = more opaque
    final opacity = (1.0 - (distance / 200).clamp(0.0, 1.0)) * 0.5 + 0.5;

    final distColor = distance < 30
        ? Colors.greenAccent
        : (distance < 80 ? Colors.amber : Colors.white54);

    return Opacity(
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF12141A).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white10, width: 0.5),
        ),
        child: Row(
          children: [
            // Monster info
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (m.level != null && m.level! > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            "${m.level}",
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          (m.name != null && m.name!.isNotEmpty) ? m.name! : "Monster (${m.templateId ?? '?'})",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (m.maxHp != null && m.maxHp != Int64.ZERO) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(1.5),
                              child: LinearProgressIndicator(
                                value: hpPct,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation<Color>(hpColor),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatHp(m.hp, m.maxHp),
                          style: const TextStyle(color: Colors.white54, fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Distance + direction arrow
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatDistance(distance),
                  style: TextStyle(
                    color: distColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Transform.rotate(
                  angle: bearing,
                  child: Icon(
                    Icons.navigation,
                    size: 12,
                    color: distColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


