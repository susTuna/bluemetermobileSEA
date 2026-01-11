import 'package:flutter/material.dart';
import '../../core/models/classes.dart';
import '../../core/services/translation_service.dart';

class DpsView extends StatefulWidget {
  final List<Map<String, dynamic>> players;
  final int combatTime;
  final Function(String) onSelectPlayer;
  final Function(int) onTabChanged;

  const DpsView({
    super.key,
    required this.players,
    required this.combatTime,
    required this.onSelectPlayer,
    required this.onTabChanged,
  });

  @override
  State<DpsView> createState() => _DpsViewState();
}

class _DpsViewState extends State<DpsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        widget.onTabChanged(_tabController.index);
      }
    });
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Bar with Tabs and Timer
        SizedBox(
          height: 32,
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
                    Tab(child: Icon(Icons.flash_on, size: 16)),
                    Tab(child: Icon(Icons.shield, size: 16)),
                    Tab(child: Icon(Icons.local_hospital, size: 16)),
                  ],
                ),
              ),
              // Timer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _formatTime(widget.combatTime),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _PlayerList(players: widget.players, metricType: "dps", onSelectPlayer: widget.onSelectPlayer),
              _PlayerList(players: widget.players, metricType: "taken", onSelectPlayer: widget.onSelectPlayer),
              _PlayerList(players: widget.players, metricType: "heal", onSelectPlayer: widget.onSelectPlayer),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerList extends StatefulWidget {
  final List<Map<String, dynamic>> players;
  final String metricType;
  final Function(String) onSelectPlayer;

  const _PlayerList({
    required this.players,
    required this.metricType,
    required this.onSelectPlayer,
  });

  @override
  State<_PlayerList> createState() => _PlayerListState();
}

class _PlayerListState extends State<_PlayerList> {
  final ScrollController _scrollController = ScrollController();

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

  Color _getClassColor(Classes cls) {
    switch (cls) {
      case Classes.stormblade:
        return Colors.blueAccent;
      case Classes.frostMage:
        return Colors.purpleAccent;
      case Classes.windKnight:
        return Colors.greenAccent;
      case Classes.verdantOracle:
        return Colors.lightGreenAccent;
      case Classes.heavyGuardian:
        return Colors.orangeAccent;
      case Classes.marksman:
        return Colors.yellowAccent;
      case Classes.shieldKnight:
        return Colors.indigoAccent;
      case Classes.soulMusician:
        return Colors.pinkAccent;
      default:
        return Colors.grey;
    }
  }

  Widget _buildRow(Map<String, dynamic> p, int index, double maxVal, String rateKey, String totalKey) {
    final cls = Classes.fromId(p['classId']);
    final val = (p[rateKey] as num?)?.toDouble() ?? 0.0;
    final total = (p[totalKey] as num?)?.toInt() ?? 0;
    // Calculate percent based on TOTAL, not Rate, to match previous fix
    final percent = (total / maxVal).clamp(0.0, 1.0);

    String name = p['name']?.toString() ?? "Unknown";
    if (p['isMe'] == true && (name == "Unknown" || name.isEmpty)) {
      name = "Moi";
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final uidStr = p['uid'] as String?;
        if (uidStr != null && uidStr.isNotEmpty) {
           widget.onSelectPlayer(uidStr);
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

  @override
  Widget build(BuildContext context) {
    String rateKey = 'dps';
    String totalKey = 'total';
    if (widget.metricType == 'heal') {
      rateKey = 'hps';
      totalKey = 'totalHeal';
    } else if (widget.metricType == 'taken') {
      rateKey = 'takenDps';
      totalKey = 'totalTaken';
    }

    var filtered = widget.players.where((p) {
      final total = (p[totalKey] as num?)?.toDouble() ?? 0.0;
      return total > 0;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(TranslationService().translate('NoData'), style: const TextStyle(color: Colors.white54, fontSize: 10)),
      );
    }

    // Sort by Total
    filtered.sort((a, b) {
      final valA = (a[totalKey] as num?)?.toDouble() ?? 0.0;
      final valB = (b[totalKey] as num?)?.toDouble() ?? 0.0;
      return valB.compareTo(valA);
    });

    double maxVal = 0.0;
    if (filtered.isNotEmpty) {
      maxVal = (filtered.first[totalKey] as num?)?.toDouble() ?? 0.0;
    }
    if (maxVal == 0) maxVal = 1.0;

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
}
