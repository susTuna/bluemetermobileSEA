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
      final hpStr = hp.toString();
      if (maxHp == null || maxHp == Int64.ZERO) return hpStr;
      
      final percent = (hp.toDouble() / maxHp.toDouble() * 100).toStringAsFixed(1);
      return "$hpStr ($percent%)";
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
        
        // Calculate distances and sort
        final List<Map<String, dynamic>> sortedMonsters = [];
        for (var m in monsters) {
            // Filter dead monsters
            if (m.hp != null && m.hp! <= Int64.ZERO) continue;

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
            // 3000m = 3km.
            if (dist > 3000) return const SizedBox.shrink(); // Hide item effectively

            return Card(
              color: Colors.black45,
              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                title: Row(
                  children: [
                    if (m.level != null && m.level! > 0)
                      Text(
                        "Lv.${m.level} ",
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                      ),
                    Expanded(
                      child: Text(
                        (m.name != null && m.name!.isNotEmpty) ? m.name! : "Monster (${m.templateId ?? '?'})",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatDistance(dist),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    // HP Bar
                    if (m.maxHp != null && m.maxHp != Int64.ZERO) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: m.hpPercent,
                          backgroundColor: Colors.grey[800],
                          valueColor: AlwaysStoppedAnimation<Color>(
                             m.hpPercent < 0.3 ? Colors.red : (m.hpPercent < 0.6 ? Colors.orange : Colors.green)
                          ),
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                     Text(
                      "HP: ${_formatHp(m.hp, m.maxHp)}",
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
