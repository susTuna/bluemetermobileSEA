import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/models/hunt_mob.dart';
import '../core/services/bptimer_service.dart';

class HuntView extends StatefulWidget {
  final bool isActive;

  const HuntView({super.key, this.isActive = true});

  @override
  State<HuntView> createState() => _HuntViewState();
}

class _HuntViewState extends State<HuntView> with SingleTickerProviderStateMixin {
  final BPTimerService _service = BPTimerService();
  late TabController _tabController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _service.addListener(_onServiceUpdate);
  }

  @override
  void didUpdateWidget(HuntView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_initialized) {
      _initialize();
    } else if (!widget.isActive && _initialized) {
      _service.disconnect();
      _initialized = false;
    }
  }

  void _initialize() {
    _initialized = true;
    _service.loadMobs().then((_) {
      _service.connectRealtime();
    });
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _service.disconnect();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Initialize on first active build
    if (widget.isActive && !_initialized) {
      _initialize();
    }

    return Column(
      children: [
        // Tab bar: Boss / Magical Creature  
        SizedBox(
          height: 22,
          child: TabBar(
            controller: _tabController,
            labelPadding: EdgeInsets.zero,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorColor: Colors.blue,
            dividerColor: Colors.transparent,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 10),
            tabs: const [
              Tab(text: 'BOSS'),
              Tab(text: 'CREATURE'),
            ],
          ),
        ),
        // Content
        Expanded(
          child: _service.isLoading
              ? const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                  ),
                )
              : _service.error != null
                  ? Center(
                      child: Text(
                        _service.error!,
                        style: const TextStyle(color: Colors.red, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _MobList(
                          mobs: _service.bosses,
                          service: _service,
                        ),
                        _MobList(
                          mobs: _service.magicalCreatures,
                          service: _service,
                        ),
                      ],
                    ),
        ),
        // Connection status indicator
        Container(
          height: 12,
          color: Colors.black.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _service.isConnected ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _service.isConnected ? 'Live' : 'Offline',
                style: TextStyle(
                  color: _service.isConnected ? Colors.green : Colors.red,
                  fontSize: 8,
                ),
              ),
              const Spacer(),
              // Credit to bptimer.com
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('https://bptimer.com');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, color: Colors.pinkAccent, size: 8),
                    SizedBox(width: 2),
                    Text(
                      'bptimer.com',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 8,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobList extends StatelessWidget {
  final List<HuntMob> mobs;
  final BPTimerService service;

  const _MobList({required this.mobs, required this.service});

  @override
  Widget build(BuildContext context) {
    if (mobs.isEmpty) {
      return const Center(
        child: Text(
          'No data',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: mobs.length,
      itemBuilder: (context, index) {
        final mob = mobs[index];
        final channels = service.getTopChannels(mob.id);

        return _MobTile(mob: mob, channels: channels);
      },
    );
  }
}

class _MobTile extends StatelessWidget {
  final HuntMob mob;
  final List<MobChannelStatus> channels;

  const _MobTile({required this.mob, required this.channels});

  Color _getHpColor(int hp) {
    if (hp >= 80) return Colors.green;
    if (hp >= 50) return Colors.yellow;
    if (hp >= 20) return Colors.orange;
    return Colors.red;
  }

  Color _getMobTypeColor() {
    return mob.isBoss ? Colors.amber : Colors.purpleAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Mob type indicator
          Container(
            width: 2,
            height: 14,
            decoration: BoxDecoration(
              color: _getMobTypeColor(),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 3),
          // Mob name
          Expanded(
            flex: 3,
            child: Text(
              mob.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 3),
          // Channel HP progress labels
          channels.isEmpty
              ? const SizedBox(
                  width: 30,
                  child: Text(
                    '—',
                    style: TextStyle(color: Colors.white24, fontSize: 8),
                    textAlign: TextAlign.center,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: channels.map((ch) {
                    return _ChannelHpBadge(
                      channelNumber: ch.channelNumber,
                      hp: ch.lastHp,
                      hpColor: _getHpColor(ch.lastHp),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }
}

/// Compact channel badge with progress bar background
class _ChannelHpBadge extends StatelessWidget {
  final int channelNumber;
  final int hp;
  final Color hpColor;

  const _ChannelHpBadge({
    required this.channelNumber,
    required this.hp,
    required this.hpColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 13,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: hpColor.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Stack(
        children: [
          // HP progress bar background
          FractionallySizedBox(
            widthFactor: (hp / 100).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: hpColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
          // Channel number label
          Center(
            child: Text(
              '$channelNumber',
              style: TextStyle(
                color: hpColor,
                fontSize: 8,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
