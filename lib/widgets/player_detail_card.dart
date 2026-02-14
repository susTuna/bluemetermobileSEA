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

class _PlayerDetailCardState extends State<PlayerDetailCard> with SingleTickerProviderStateMixin {
  bool _showDps = true;
  bool _showHps = true;
  bool _showTaken = true;
  Int64? _selectedTargetUid;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cls = Classes.fromId(widget.playerInfo?.professionId ?? 0);
    var name = widget.playerInfo?.name ?? "Unknown";
    if (widget.isMe && (name == "Unknown" || name.isEmpty)) {
      name = TranslationService().translate('Me');
    }

    final filteredSkills = _getFilteredSkills();
    final filteredDamage = _getFilteredDamage();
    final filteredHeal = _getFilteredHeal();

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF12141A),
          border: Border.all(color: const Color(0xFF2A2E38)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(name, cls),
            _buildCombatStats(filteredDamage, filteredHeal),
            if (widget.dpsData.targets.isNotEmpty) _buildTargetFilter(),
            Container(
              height: 24,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF2A2E38), width: 0.5)),
              ),
              child: TabBar(
                controller: _tabController,
                labelPadding: EdgeInsets.zero,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorColor: Colors.blueAccent,
                indicatorWeight: 2,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(text: TranslationService().translate('Skills')),
                  Tab(text: TranslationService().translate('Chart')),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSkillsList(filteredSkills),
                  widget.dpsData.timeline.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
                          child: PlayerDpsChart(
                            dpsData: widget.dpsData,
                            height: double.infinity,
                            showDps: _showDps,
                            showHps: _showHps,
                            showTaken: _showTaken,
                          ),
                        )
                      : Center(
                          child: Text(
                            TranslationService().translate('NoData'),
                            style: const TextStyle(color: Colors.white24, fontSize: 11),
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

  int _getFilteredCritHits() {
    if (_selectedTargetUid == null) return widget.dpsData.critHitCount;
    return widget.dpsData.targets[_selectedTargetUid]?.critHitCount ?? 0;
  }

  String _getTargetName(Int64 uid) {
    // Use pre-resolved name from serialization (overlay has no DataStorage data)
    final breakdown = widget.dpsData.targets[uid];
    if (breakdown?.name != null && breakdown!.name!.isNotEmpty) {
      return breakdown.name!;
    }
    // Fallback: try DataStorage (works in main app, not overlay)
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
    return "Entity";
  }

  // --- Header ---

  Widget _buildHeader(String name, Classes cls) {
    final info = widget.playerInfo;
    final hitCount = _getFilteredHitCount();
    final critHits = _getFilteredCritHits();
    final luckyHits = _getFilteredLuckyHits();
    final critRate = hitCount > 0 ? (critHits / hitCount * 100) : 0.0;
    final luckyRate = hitCount > 0 ? (luckyHits / hitCount * 100) : 0.0;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: widget.onDragStart,
      onPanUpdate: widget.onDragUpdate,
      onPanEnd: widget.onDragEnd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _getClassColor(cls).withValues(alpha: 0.12),
              Colors.transparent,
            ],
          ),
          border: const Border(bottom: BorderSide(color: Color(0xFF2A2E38), width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Icon + Name + stat chips + close
            Row(
              children: [
                if (cls != Classes.unknown) ...[
                  Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: _getClassColor(cls).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Image.asset(
                      cls.iconPath,
                      width: 16,
                      height: 16,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(Icons.person, color: _getClassColor(cls), size: 16),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                // Name + class badge
                Flexible(
                  flex: 0,
                  child: Text(
                    name,
                    style: TextStyle(
                      color: _getClassColor(cls),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (cls != Classes.unknown) ...[
                  const SizedBox(width: 3),
                  Text(
                    cls.name,
                    style: TextStyle(color: _getClassColor(cls).withValues(alpha: 0.5), fontSize: 7),
                  ),
                ],
                const SizedBox(width: 6),
                // Stat labels
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _buildStatLabels(info),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onClose,
                  child: const Icon(Icons.close, color: Colors.white38, size: 14),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // Row 2: Timer + Hits + HP bar + Crit/Lucky rates
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 8, color: Colors.white.withValues(alpha: 0.35)),
                const SizedBox(width: 2),
                Text(
                  _formatDuration(widget.dpsData.activeCombatTicks),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 8),
                ),
                if (widget.dpsData.totalHitCount > 0) ...[
                  const SizedBox(width: 5),
                  Text(
                    '${widget.dpsData.totalHitCount}h',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8),
                  ),
                ],
                if (info != null && info.maxHp != null && info.maxHp! > Int64.ZERO) ...[
                  const SizedBox(width: 6),
                  _buildHpMiniBar(info),
                ],
                const Spacer(),
                if (hitCount > 0) ...[
                  _buildRateBadge('C', '${critRate.toStringAsFixed(1)}%', const Color(0xFFFF5252)),
                  const SizedBox(width: 3),
                  _buildRateBadge('L', '${luckyRate.toStringAsFixed(1)}%', const Color(0xFF69F0AE)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStatLabels(PlayerInfo? info) {
    if (info == null) return [];
    final labels = <Widget>[];

    void addStat(String label, int? value, Color color, {int? pct}) {
      if (value == null || value <= 0) return;
      String text = _formatNumber(value);
      if (pct != null && pct > 0) text += '(${(pct / 100.0).toStringAsFixed(1)}%)';
      labels.add(Padding(
        padding: const EdgeInsets.only(right: 4),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$label ',
                style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 7, fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text: text,
                style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ));
    }

    if (info.level != null && info.level! > 0) {
      addStat('Lv', info.level, const Color(0xFF64B5F6));
    }
    if (info.combatPower != null && info.combatPower! > 0) {
      addStat('CP', info.combatPower, const Color(0xFFFFD54F));
    }
    addStat('ATK', info.attack, const Color(0xFFFF8A65));
    addStat('DEF', info.defense, const Color(0xFF90CAF9));
    addStat('Crit', info.critical, const Color(0xFFFF5252));
    addStat('Luck', info.lucky, const Color(0xFF69F0AE));
    addStat('Haste', info.haste, const Color(0xFF80DEEA), pct: info.hastePct);
    addStat('Mast', info.mastery, const Color(0xFFCE93D8), pct: info.masteryPct);
    addStat('Vers', info.versatility, const Color(0xFFA5D6A7), pct: info.versatilityPct);
    addStat('SSt', info.seasonStrength, const Color(0xFFFFCC80));

    return labels;
  }

  Widget _buildHpMiniBar(PlayerInfo info) {
    final hpPct = (info.hp != null && info.maxHp != null && info.maxHp! > Int64.ZERO)
        ? (info.hp!.toDouble() / info.maxHp!.toDouble())
        : 0.0;
    final hpColor = hpPct < 0.3 ? Colors.redAccent : (hpPct < 0.6 ? Colors.orangeAccent : const Color(0xFF69F0AE));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.favorite, size: 7, color: hpColor.withValues(alpha: 0.6)),
        const SizedBox(width: 2),
        SizedBox(
          width: 24,
          height: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(1.5),
            child: LinearProgressIndicator(
              value: hpPct,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(hpColor),
            ),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          '${(hpPct * 100).toStringAsFixed(0)}%',
          style: TextStyle(color: hpColor.withValues(alpha: 0.7), fontSize: 7),
        ),
      ],
    );
  }

  Widget _buildRateBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 7, fontWeight: FontWeight.bold)),
          const SizedBox(width: 1),
          Text(value, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // --- Combat Stats (DPS/HPS/Taken) ---

  Widget _buildCombatStats(Int64 filteredDamage, Int64 filteredHeal) {
    double seconds = widget.dpsData.activeCombatTicks / 1000.0;
    if (seconds < 1.0) seconds = 1.0;
    final filteredDps = filteredDamage.toDouble() / seconds;
    final filteredHps = filteredHeal.toDouble() / seconds;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: _buildStatBox(
              label: "DPS",
              value: _selectedTargetUid != null ? filteredDps : widget.dpsValue,
              total: filteredDamage.toInt(),
              color: const Color(0xFFFF5252),
              icon: Icons.bolt,
              isActive: _showDps,
              onTap: () => setState(() => _showDps = !_showDps),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildStatBox(
              label: "HPS",
              value: _selectedTargetUid != null ? filteredHps : widget.hpsValue,
              total: filteredHeal.toInt(),
              color: const Color(0xFF69F0AE),
              icon: Icons.favorite,
              isActive: _showHps,
              onTap: () => setState(() => _showHps = !_showHps),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildStatBox(
              label: "TAKEN",
              value: widget.takenDpsValue,
              total: widget.dpsData.totalTakenDamage.toInt(),
              color: const Color(0xFFFFB74D),
              icon: Icons.shield,
              isActive: _showTaken,
              onTap: () => setState(() => _showTaken = !_showTaken),
            ),
          ),
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
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 8, color: color.withValues(alpha: 0.7)),
                  const SizedBox(width: 2),
                  Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 7, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ],
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _formatNumber(value),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                _formatNumber(total),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Target Filter ---

  Widget _buildTargetFilter() {
    // Filter out self from targets (self-heals)
    final selfUid = widget.dpsData.uid;
    final targetEntries = widget.dpsData.targets.entries
      .where((e) => e.key != selfUid)
      .toList()
      ..sort((a, b) => b.value.totalDamage.compareTo(a.value.totalDamage));
    if (targetEntries.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A2E38), width: 0.5)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildTargetChip(
            label: TranslationService().translate('All'),
            isSelected: _selectedTargetUid == null,
            onTap: () => setState(() => _selectedTargetUid = null),
          ),
          const SizedBox(width: 3),
          ...targetEntries.take(10).map((e) {
            final name = _getTargetName(e.key);
            final short = name.length > 12 ? '${name.substring(0, 12)}...' : name;
            final pct = widget.dpsData.totalAttackDamage > Int64.ZERO
                ? (e.value.totalDamage.toDouble() / widget.dpsData.totalAttackDamage.toDouble() * 100)
                : 0.0;
            return Padding(
              padding: const EdgeInsets.only(right: 3),
              child: _buildTargetChip(
                label: short,
                isSelected: _selectedTargetUid == e.key,
                onTap: () => setState(() => _selectedTargetUid = e.key),
                pct: pct,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTargetChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    double? pct,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.blueAccent.withValues(alpha: 0.5) : Colors.white10,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blueAccent : Colors.white54,
                fontSize: 8,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (pct != null && pct > 0) ...[
              const SizedBox(width: 3),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 7),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- Skills List ---

  Widget _buildSkillsList(Map<String, SkillData> skills) {
    if (skills.isEmpty) {
      return Center(
        child: Text(
          TranslationService().translate('NoSkillData'),
          style: const TextStyle(color: Colors.white24, fontSize: 11),
        ),
      );
    }

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
        existing.critHitCount += skill.critHitCount;
        existing.luckyHitCount += skill.luckyHitCount;
      } else {
        aggregatedSkills[name] = _AggregatedSkill(
          totalDamage: damage,
          totalHeal: heal,
          hitCount: skill.hitCount,
          critHitCount: skill.critHitCount,
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

    final maxSkillTotal = sortedSkills.isNotEmpty
        ? (sortedSkills.first.value.totalDamage.toInt() + sortedSkills.first.value.totalHeal.toInt())
        : 1;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      itemCount: sortedSkills.length,
      itemBuilder: (context, index) {
        final entry = sortedSkills[index];
        final name = entry.key;
        final skill = entry.value;
        final skillTotal = skill.totalDamage.toInt() + skill.totalHeal.toInt();
        final percentage = totalDamageAndHeal > 0 ? (skillTotal / totalDamageAndHeal * 100) : 0.0;
        final barWidthFactor = maxSkillTotal > 0 ? (skillTotal / maxSkillTotal) : 0.0;

        final isHeal = skill.totalHeal > skill.totalDamage;
        final color = isHeal ? const Color(0xFF69F0AE) : const Color(0xFFFF5252);
        final avg = skill.hitCount > 0 ? skillTotal / skill.hitCount : 0;
        final critPct = skill.hitCount > 0 ? (skill.critHitCount / skill.hitCount * 100) : 0.0;
        final luckyPct = skill.hitCount > 0 ? (skill.luckyHitCount / skill.hitCount * 100) : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 1),
          height: 28,
          child: Stack(
            children: [
              FractionallySizedBox(
                widthFactor: barWidthFactor,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.05)],
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Text(
                              _formatNumber(skillTotal),
                              style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${percentage.toStringAsFixed(1)}%',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 8),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              '${skill.hitCount}h',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 7),
                            ),
                            Text(
                              ' ~${_formatNumber(avg)}',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 7),
                            ),
                            if (critPct > 0) ...[
                              Text(
                                ' C:${critPct.toStringAsFixed(0)}%',
                                style: TextStyle(color: const Color(0xFFFF5252).withValues(alpha: 0.5), fontSize: 7),
                              ),
                            ],
                            if (luckyPct > 0) ...[
                              Text(
                                ' L:${luckyPct.toStringAsFixed(0)}%',
                                style: TextStyle(color: const Color(0xFF69F0AE).withValues(alpha: 0.5), fontSize: 7),
                              ),
                            ],
                          ],
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

  // --- Helpers ---

  Color _getClassColor(Classes cls) {
    switch (cls) {
      case Classes.stormblade:
        return const Color(0xFF64B5F6);
      case Classes.frostMage:
        return const Color(0xFFCE93D8);
      case Classes.windKnight:
        return const Color(0xFF81C784);
      case Classes.verdantOracle:
        return const Color(0xFFA5D6A7);
      case Classes.heavyGuardian:
        return const Color(0xFFFFB74D);
      case Classes.marksman:
        return const Color(0xFFFFF176);
      case Classes.shieldKnight:
        return const Color(0xFF7986CB);
      case Classes.soulMusician:
        return const Color(0xFFF48FB1);
      default:
        return Colors.grey;
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
  int critHitCount;
  int luckyHitCount;

  _AggregatedSkill({
    required this.totalDamage,
    required this.totalHeal,
    required this.hitCount,
    required this.critHitCount,
    required this.luckyHitCount,
  });
}
