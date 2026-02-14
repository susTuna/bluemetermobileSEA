import 'package:flutter/material.dart';
import 'package:fixnum/fixnum.dart';
import '../core/models/classes.dart';
import '../core/models/player_info.dart';
import '../core/models/dps_data.dart';
import '../core/data/skill_names.dart';
import '../core/services/translation_service.dart';
import '../core/services/monster_name_service.dart';
import '../core/state/data_storage.dart';
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
  Int64? _selectedTargetUid;

  @override
  Widget build(BuildContext context) {
    final cls = Classes.fromId(widget.playerInfo?.professionId ?? 0);
    var name = widget.playerInfo?.name ?? "Unknown";
    if (widget.isMe && (name == "Unknown" || name.isEmpty)) {
      name = TranslationService().translate('Me');
    }

    // Compute filtered data based on selected target
    final filteredSkills = _getFilteredSkills();
    final filteredDamage = _getFilteredDamage();
    final filteredHeal = _getFilteredHeal();
    final filteredHitCount = _getFilteredHitCount();
    final filteredLuckyHits = _getFilteredLuckyHits();

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
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
            _buildHeader(name, cls),
            const Divider(height: 1, color: Colors.white10),
            if (widget.playerInfo != null) _buildPlayerStats(widget.playerInfo!, filteredHitCount, filteredLuckyHits),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left: Stats + Chart
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _buildCombatStats(filteredDamage, filteredHeal),
                        if (widget.dpsData.targets.isNotEmpty)
                          _buildTargetFilter(),
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
                  // Right: Skills
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                TranslationService().translate('Skills'),
                                style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                              Text(
                                TranslationService().translate('Details'),
                                style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _buildSkillsList(filteredSkills)),
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

  // --- Data helpers ---

  Map<String, SkillData> _getFilteredSkills() {
    if (_selectedTargetUid == null) return widget.dpsData.skills;
    return widget.dpsData.targets[_selectedTargetUid]?.skills ?? {};
  }

  Int64 _getFilteredDamage() {
    if (_selectedTargetUid == null) return widget.dpsData.totalAttackDamage;
    return widget.dpsData.targets[_selectedTargetUid]?.totalDamage ?? Int64.ZERO;
  }

  Int64 _getFilteredHeal() {
    if (_selectedTargetUid == null) return widget.dpsData.totalHeal;
    return widget.dpsData.targets[_selectedTargetUid]?.totalHeal ?? Int64.ZERO;
  }

  int _getFilteredHitCount() {
    if (_selectedTargetUid == null) return widget.dpsData.totalHitCount;
    return widget.dpsData.targets[_selectedTargetUid]?.hitCount ?? 0;
  }

  int _getFilteredLuckyHits() {
    if (_selectedTargetUid == null) return widget.dpsData.luckyHitCount;
    return widget.dpsData.targets[_selectedTargetUid]?.luckyHitCount ?? 0;
  }

  String _getTargetName(Int64 uid) {
    final monster = DataStorage().monsterInfoDatas[uid];
    if (monster != null && monster.name != null && monster.name!.isNotEmpty) {
      return monster.name!;
    }
    if (monster != null && monster.templateId != null) {
      final n = MonsterNameService().getName(monster.templateId!);
      if (n != null) return n;
    }
    final player = DataStorage().playerInfoDatas[uid];
    if (player != null && player.name != null && player.name!.isNotEmpty) {
      return player.name!;
    }
    return "#${uid.toInt()}";
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

  Widget _buildPlayerStats(PlayerInfo info, int hitCount, int luckyHits) {
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
    if (hitCount > 0) {
      final luckyRate = luckyHits / hitCount * 100;
      stats.add(_buildStatBadge("Lucky: ${luckyRate.toStringAsFixed(1)}%", Colors.amber.shade300));
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

  Widget _buildCombatStats(Int64 filteredDamage, Int64 filteredHeal) {
    double seconds = widget.dpsData.activeCombatTicks / 1000.0;
    if (seconds < 1.0) seconds = 1.0;
    final filteredDps = filteredDamage.toDouble() / seconds;
    final filteredHps = filteredHeal.toDouble() / seconds;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(child: _buildStatBox(
            label: "DPS",
            value: _selectedTargetUid != null ? filteredDps : widget.dpsValue,
            total: filteredDamage.toInt(),
            color: Colors.redAccent,
            icon: Icons.bolt,
            isActive: _showDps,
            onTap: () => setState(() => _showDps = !_showDps),
          )),
          const SizedBox(width: 6),
          Expanded(child: _buildStatBox(
            label: "HPS",
            value: _selectedTargetUid != null ? filteredHps : widget.hpsValue,
            total: filteredHeal.toInt(),
            color: Colors.greenAccent,
            icon: Icons.favorite,
            isActive: _showHps,
            onTap: () => setState(() => _showHps = !_showHps),
          )),
          const SizedBox(width: 6),
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

  Widget _buildTargetFilter() {
    final targetEntries = widget.dpsData.targets.entries.toList()
      ..sort((a, b) => b.value.totalDamage.compareTo(a.value.totalDamage));
    if (targetEntries.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildTargetChip(
            label: TranslationService().translate('All'),
            isSelected: _selectedTargetUid == null,
            onTap: () => setState(() => _selectedTargetUid = null),
          ),
          const SizedBox(width: 4),
          ...targetEntries.take(8).map((e) {
            final name = _getTargetName(e.key);
            final short = name.length > 10 ? '${name.substring(0, 10)}…' : name;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildTargetChip(
                label: short,
                isSelected: _selectedTargetUid == e.key,
                onTap: () => setState(() => _selectedTargetUid = e.key),
                damage: e.value.totalDamage,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTargetChip({
    required String label, required bool isSelected,
    required VoidCallback onTap, Int64? damage,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.blueAccent.withValues(alpha: 0.6) : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
              style: TextStyle(
                color: isSelected ? Colors.blueAccent : Colors.white54,
                fontSize: 9, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              )),
            if (damage != null && damage > Int64.ZERO) ...[
              const SizedBox(width: 3),
              Text(_formatNumber(damage.toInt()),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8)),
            ],
          ],
        ),
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

  Widget _buildSkillsList(Map<String, SkillData> skills) {
    if (skills.isEmpty) {
      return Center(
        child: Text(
          TranslationService().translate('NoSkillData'),
          style: const TextStyle(color: Colors.white24, fontSize: 12),
        ),
      );
    }

    // Aggregate skills by name
    final Map<String, _AggregatedSkill> aggregatedSkills = {};
    
    for (var skill in skills.values) {
      final name = getSkillName(int.tryParse(skill.skillId) ?? 0);
      
      final damage = _showDps ? skill.totalDamage : Int64.ZERO;
      final heal = _showHps ? skill.totalHeal : Int64.ZERO;
      
      if (damage == Int64.ZERO && heal == Int64.ZERO) continue;

      if (aggregatedSkills.containsKey(name)) {
        final existing = aggregatedSkills[name]!;
        existing.totalDamage += damage;
        existing.totalHeal += heal;
        existing.hitCount += skill.hitCount;
        existing.luckyHitCount += skill.luckyHitCount;
      } else {
        aggregatedSkills[name] = _AggregatedSkill(
          totalDamage: damage,
          totalHeal: heal,
          hitCount: skill.hitCount,
          luckyHitCount: skill.luckyHitCount,
        );
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
        final luckyPct = skill.hitCount > 0 ? (skill.luckyHitCount / skill.hitCount * 100) : 0.0;

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
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(children: [
                          Text(_formatNumber(skillTotal),
                            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 3),
                          Text("(${percentage.toStringAsFixed(1)}%)",
                            style: const TextStyle(color: Colors.white54, fontSize: 9)),
                        ]),
                        Text(
                          "${skill.hitCount} ${TranslationService().translate('Hits')} • ${TranslationService().translate('Avg')}: ${_formatNumber(avg)}"
                          "${luckyPct > 0 ? ' • L:${luckyPct.toStringAsFixed(0)}%' : ''}",
                          style: const TextStyle(color: Colors.white38, fontSize: 8),
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
      case Role.tank: return Colors.blueAccent;
      case Role.heal: return Colors.greenAccent;
      case Role.dps: return Colors.redAccent;
      default: return Colors.grey;
    }
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  String _formatNumber(num number) {
    if (number >= 1000000) {
      double val = number / 1000000;
      return "${val < 100 ? val.toStringAsFixed(2) : val.toStringAsFixed(1)}m";
    }
    if (number >= 1000) {
      double val = number / 1000;
      return "${val < 100 ? val.toStringAsFixed(2) : val.toStringAsFixed(1)}k";
    }
    return number.toStringAsFixed(0);
  }
}

class _AggregatedSkill {
  Int64 totalDamage;
  Int64 totalHeal;
  int hitCount;
  int luckyHitCount;

  _AggregatedSkill({
    required this.totalDamage,
    required this.totalHeal,
    required this.hitCount,
    required this.luckyHitCount,
  });
}
