import 'package:flutter/material.dart';
import 'package:fixnum/fixnum.dart';
import '../core/models/classes.dart';
import '../core/models/player_info.dart';
import '../core/models/dps_data.dart';
import '../core/data/skill_names.dart';

class PlayerDetailCard extends StatelessWidget {
  final PlayerInfo? playerInfo;
  final DpsData dpsData;
  final double dpsValue;
  final double hpsValue;
  final double takenDpsValue;
  final VoidCallback onClose;

  const PlayerDetailCard({
    super.key,
    required this.playerInfo,
    required this.dpsData,
    required this.dpsValue,
    required this.hpsValue,
    required this.takenDpsValue,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cls = Classes.fromId(playerInfo?.professionId ?? 0);
    final name = playerInfo?.name ?? "Unknown";

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header compact
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  if (cls != Classes.unknown) ...[
                    Image.asset(
                      cls.iconPath,
                      width: 20,
                      height: 20,
                      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: _getClassColor(cls),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (cls != Classes.unknown)
                          Text(
                            cls.name,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: const Icon(Icons.close, color: Colors.white70, size: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Stats compacts en colonnes
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn("DPS", dpsValue, dpsData.totalAttackDamage.toInt(), Colors.red),
                  Container(width: 1, height: 30, color: Colors.white10),
                  _buildStatColumn("HPS", hpsValue, dpsData.totalHeal.toInt(), Colors.green),
                  Container(width: 1, height: 30, color: Colors.white10),
                  _buildStatColumn("Reçu", takenDpsValue, dpsData.totalTakenDamage.toInt(), Colors.orange),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Skills Section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                "Compétences",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),

            Expanded(
              child: _buildSkillsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, double rate, int total, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "${_formatNumber(rate)}/s",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _formatNumber(total),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillsList() {
    if (dpsData.skills.isEmpty) {
      return const Center(
        child: Text(
          "Aucune compétence enregistrée",
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
      );
    }

    // Sort skills by total damage + heal
    final sortedSkills = dpsData.skills.values.toList()
      ..sort((a, b) {
        final totalA = a.totalDamage.toInt() + a.totalHeal.toInt();
        final totalB = b.totalDamage.toInt() + b.totalHeal.toInt();
        return totalB.compareTo(totalA);
      });

    final totalDamageAndHeal = sortedSkills.fold<int>(
      0,
      (sum, skill) => sum + skill.totalDamage.toInt() + skill.totalHeal.toInt(),
    );

    return ListView.builder(
      itemCount: sortedSkills.length,
      itemBuilder: (context, index) {
        final skill = sortedSkills[index];
        final skillTotal = skill.totalDamage.toInt() + skill.totalHeal.toInt();
        final percentage = totalDamageAndHeal > 0 
            ? (skillTotal / totalDamageAndHeal * 100) 
            : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(3),
            border: Border(
              left: BorderSide(
                color: skill.totalDamage > Int64.ZERO ? Colors.red : Colors.green,
                width: 2,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      getSkillName(int.tryParse(skill.skillId) ?? 0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    "${percentage.toStringAsFixed(1)}%",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (skill.totalDamage > Int64.ZERO)
                    Text(
                      "Dmg: ${_formatNumber(skill.totalDamage.toInt())}",
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 8,
                      ),
                    ),
                  if (skill.totalHeal > Int64.ZERO)
                    Text(
                      "Heal: ${_formatNumber(skill.totalHeal.toInt())}",
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 8,
                      ),
                    ),
                  Text(
                    "${skill.hitCount}x",
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              LinearProgressIndicator(
                value: percentage / 100,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(
                  skill.totalDamage > Int64.ZERO ? Colors.red : Colors.green,
                ),
                minHeight: 1.5,
              ),
            ],
          ),
        );
      },
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
