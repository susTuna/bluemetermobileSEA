import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';

import '../core/models/monster_info.dart';
import '../core/state/data_storage.dart';
import '../core/services/translation_service.dart';

class NearbyView extends StatelessWidget {
  const NearbyView({super.key});

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

  double _calculateDistance(Map<String, double>? pos1, Map<String, double>? pos2) {
    if (pos1 == null || pos2 == null) return 99999.0;
    
    final dx = (pos1['x'] ?? 0) - (pos2['x'] ?? 0);
    final dy = (pos1['y'] ?? 0) - (pos2['y'] ?? 0);
    final dz = (pos1['z'] ?? 0) - (pos2['z'] ?? 0);
    
    return sqrt(dx * dx + dy * dy + dz * dz); 
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataStorage>(
      builder: (context, storage, child) {
        final myUid = storage.currentPlayerUuid;
        final myPos = storage.playerInfoDatas[myUid]?.position;

        final monsters = storage.monsterInfoDatas.values.toList();

        // Debug logging for NearbyView
        if (monsters.isNotEmpty) {
           debugPrint("[NearbyView] Rebuild with ${monsters.length} monsters.");
           for (var m in monsters) {
               if (m.isDead || (m.hp != null && m.hp! <= Int64.ZERO)) {
                  debugPrint(" -> [DEAD-KEPT-ALIVE?] Monster ${m.uid}: HP=${m.hp}, isDead=${m.isDead}, Name=${m.name}");
               }
           }
        }
        
        // Calculate distances and sort
        final List<Map<String, dynamic>> sortedMonsters = [];
        for (var m in monsters) {
            // Filter dead monsters
            if (m.isDead || (m.hp != null && m.hp! <= Int64.ZERO)) continue;

            // Units are typically centimeters in UE games.
            final rawDist = _calculateDistance(myPos, m.position);
            sortedMonsters.add({'monster': m, 'dist': rawDist});
        }
        
        sortedMonsters.sort((a, b) => (a['dist'] as double).compareTo(b['dist'] as double));

        if (sortedMonsters.isEmpty) {
           return Center(
             child: Text(
               TranslationService().translate('No nearby monsters'),
               style: const TextStyle(color: Colors.white54),
             ),
           );
        }

        return ListView.builder(
          itemCount: sortedMonsters.length,
          itemBuilder: (context, index) {
            final m = sortedMonsters[index]['monster'] as MonsterInfo;
            // Assuming raw units are Meters (removing / 100 conversion)
            // Or if they are CM, then / 100 is correct.
            // User feedback suggests "m" is too small/wrong.
            // Let's try displaying Raw units as meters first (common in MMOs to use float meters).
            final dist = (sortedMonsters[index]['dist'] as double);
            
            // Filter out very far monsters (likely stale from other zones/teleports)
            // Limit to 200m
            if (dist > 200) return const SizedBox.shrink(); // Hide item effectively

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white12, width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (m.level != null && m.level! > 0)
                        Text(
                          "Lv.${m.level}",
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          ((m.name != null && m.name!.isNotEmpty) ? m.name! : "Monster (${m.templateId ?? '?'})") + (m.isDead || (m.hp != null && m.hp! <= Int64.ZERO) ? " (Dead)" : ""),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDistance(dist),
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                  if (m.maxHp != null && m.maxHp != Int64.ZERO) ...[
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(1.5),
                              child: LinearProgressIndicator(
                                value: m.hpPercent,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                   m.hpPercent < 0.3 ? Colors.redAccent : (m.hpPercent < 0.6 ? Colors.orangeAccent : Colors.greenAccent)
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 35,
                          child: Text(
                            _formatHp(m.hp, m.maxHp),
                            style: const TextStyle(color: Colors.white54, fontSize: 10),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
