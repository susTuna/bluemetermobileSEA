import 'package:flutter/material.dart';
import 'package:fixnum/fixnum.dart';
import '../core/models/classes.dart';
import '../core/models/player_info.dart';
import '../core/models/dps_data.dart';
import '../core/data/skill_names.dart';
import '../core/services/translation_service.dart';
import 'player_dps_chart.dart';

class PlayerDetailCard extends StatefulWidget {
  final PlayerInfo? playerInfo;
  final DpsData dpsData;
  final double dpsValue;
  final double hpsValue;
  final double takenDpsValue;
  final bool isMe;
  final VoidCallback onClose;
  final Function(DragStartDetails)? onDragStart;
  final Function(DragUpdateDetails)? onDragUpdate;
  final Function(DragEndDetails)? onDragEnd;

  const PlayerDetailCard({
    super.key,
    required this.playerInfo,
    required this.dpsData,
    required this.dpsValue,
    required this.hpsValue,
    required this.takenDpsValue,
    this.isMe = false,
    required this.onClose,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  State<PlayerDetailCard> createState() => _PlayerDetailCardState();
}

class _PlayerDetailCardState extends State<PlayerDetailCard> {
  bool _showDps = true;
  bool _showHps = true;
  bool _showTaken = true;

  @override
  Widget build(BuildContext context) {
    final cls = Classes.fromId(widget.playerInfo?.professionId ?? 0);
    var name = widget.playerInfo?.name ?? "Unknown";
    if (widget.isMe && (name == "Unknown" || name.isEmpty)) {
      name = TranslationService().translate('Me');
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(0),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(name, cls),
            
            const Divider(height: 1, color: Colors.white10),

            // Player Stats (Level, CP, etc.)
            if (widget.playerInfo != null) _buildPlayerStats(widget.playerInfo!),

            // Main Content Split
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Side: Stats & Chart
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        _buildCombatStats(),
                        if (widget.dpsData.timeline.isNotEmpty)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
                              child: PlayerDpsChart(
                                dpsData: widget.dpsData, 
                                height: double.infinity,
                                showDps: _showDps,
                                showHps: _showHps,
                                showTaken: _showTaken,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const VerticalDivider(width: 1, color: Colors.white10),

                  // Right Side: Skills
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                TranslationService().translate('Skills'),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                TranslationService().translate('Details'),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _buildSkillsList(),
                        ),
                      ],
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

  Widget _buildHeader(String name, Classes cls) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: widget.onDragStart,
      onPanUpdate: widget.onDragUpdate,
      onPanEnd: widget.onDragEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (cls != Classes.unknown) ...[
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Image.asset(
                  cls.iconPath,
                  width: 24,
                  height: 24,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.help, color: Colors.white24, size: 24),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: _getClassColor(cls),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (cls != Classes.unknown)
                    Text(
                      cls.name,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 10, color: Colors.white54),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(widget.dpsData.activeCombatTicks),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 20),
              onPressed: widget.onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerStats(PlayerInfo info) {
    final stats = <Widget>[];
    
    if (info.level != null && info.level! > 0) {
      stats.add(_buildStatBadge("${TranslationService().translate('Lv')}.${info.level}", Colors.blueGrey));
    }
    if (info.combatPower != null && info.combatPower! > 0) {
      stats.add(_buildStatBadge("${TranslationService().translate('CS')}: ${_formatNumber(info.combatPower!)}", Colors.amber));
    }
    if (info.critical != null && info.critical! > 0) {
      stats.add(_buildStatBadge("${TranslationService().translate('Crit')}: ${info.critical}", Colors.redAccent));
    }
    if (info.lucky != null && info.lucky! > 0) {
      stats.add(_buildStatBadge("${TranslationService().translate('Luck')}: ${info.lucky}", Colors.greenAccent));
    }

    if (stats.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black12,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: stats,
      ),
    );
  }

  Widget _buildStatBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCombatStats() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(child: _buildStatBox(
            label: "DPS",
            value: widget.dpsValue,
            total: widget.dpsData.totalAttackDamage.toInt(),
            color: Colors.redAccent,
            icon: Icons.bolt,
            isActive: _showDps,
            onTap: () => setState(() => _showDps = !_showDps),
          )),
          const SizedBox(width: 8),
          Expanded(child: _buildStatBox(
            label: "HPS",
            value: widget.hpsValue,
            total: widget.dpsData.totalHeal.toInt(),
            color: Colors.greenAccent,
            icon: Icons.favorite,
            isActive: _showHps,
            onTap: () => setState(() => _showHps = !_showHps),
          )),
          const SizedBox(width: 8),
          Expanded(child: _buildStatBox(
            label: TranslationService().translate('Received'),
            value: widget.takenDpsValue,
            total: widget.dpsData.totalTakenDamage.toInt(),
            color: Colors.orangeAccent,
            icon: Icons.shield,
            isActive: _showTaken,
            onTap: () => setState(() => _showTaken = !_showTaken),
          )),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required String label,
    required double value,
    required int total,
    required Color color,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isActive ? 1.0 : 0.3,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 9, color: color),
                    const SizedBox(width: 2),
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatNumber(value),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  "${TranslationService().translate('Total')}: ${_formatNumber(total)}",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 7,
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }

  Widget _buildSkillsList() {
    if (widget.dpsData.skills.isEmpty) {
      return Center(
        child: Text(
          TranslationService().translate('NoSkillData'),
          style: const TextStyle(color: Colors.white24, fontSize: 12),
        ),
      );
    }

    // Aggregate skills by name
    final Map<String, SkillData> aggregatedSkills = {};
    
    for (var skill in widget.dpsData.skills.values) {
      final name = getSkillName(int.tryParse(skill.skillId) ?? 0);
      
      // Filter values based on visibility
      final damage = _showDps ? skill.totalDamage : Int64.ZERO;
      final heal = _showHps ? skill.totalHeal : Int64.ZERO;
      
      if (damage == 0 && heal == 0) continue;

      if (aggregatedSkills.containsKey(name)) {
        final existing = aggregatedSkills[name]!;
        existing.totalDamage += damage;
        existing.totalHeal += heal;
        existing.hitCount += skill.hitCount;
      } else {
        // Create a copy to avoid modifying original data
        aggregatedSkills[name] = SkillData(skillId: skill.skillId)
          ..totalDamage = damage
          ..totalHeal = heal
          ..hitCount = skill.hitCount;
      }
    }

    final sortedSkills = aggregatedSkills.entries.toList()
      ..sort((a, b) {
        final totalA = a.value.totalDamage.toInt() + a.value.totalHeal.toInt();
        final totalB = b.value.totalDamage.toInt() + b.value.totalHeal.toInt();
        return totalB.compareTo(totalA);
      });

    final totalDamageAndHeal = sortedSkills.fold<int>(
      0,
      (sum, entry) => sum + entry.value.totalDamage.toInt() + entry.value.totalHeal.toInt(),
    );

    // Find max value for bar scaling
    final maxSkillTotal = sortedSkills.isNotEmpty 
        ? (sortedSkills.first.value.totalDamage.toInt() + sortedSkills.first.value.totalHeal.toInt()) 
        : 1;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      itemCount: sortedSkills.length,
      itemBuilder: (context, index) {
        final entry = sortedSkills[index];
        final name = entry.key;
        final skill = entry.value;
        final skillTotal = skill.totalDamage.toInt() + skill.totalHeal.toInt();
        final percentage = totalDamageAndHeal > 0 
            ? (skillTotal / totalDamageAndHeal * 100) 
            : 0.0;
        
        // Bar width relative to the highest skill
        final barWidthFactor = maxSkillTotal > 0 ? (skillTotal / maxSkillTotal) : 0.0;

        final isHeal = skill.totalHeal > skill.totalDamage;
        final color = isHeal ? Colors.greenAccent : Colors.redAccent;
        final avg = skill.hitCount > 0 ? skillTotal / skill.hitCount : 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          height: 30,
          child: Stack(
            children: [
              // Background Bar
              FractionallySizedBox(
                widthFactor: barWidthFactor,
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    // Skill Name
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Stats
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Text(
                              _formatNumber(skillTotal),
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "(${percentage.toStringAsFixed(1)}%)",
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          "${skill.hitCount} ${TranslationService().translate('Hits')} • ${TranslationService().translate('Avg')}: ${_formatNumber(avg)}",
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
        return Colors.blueAccent;
      case Role.heal:
        return Colors.greenAccent;
      case Role.dps:
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
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
