import 'dart:math';
import 'package:flutter/material.dart';
import '../core/models/dps_data.dart';
import '../core/data/skill_names.dart';

class PlayerDpsChart extends StatefulWidget {
  final DpsData dpsData;
  final double height;

  const PlayerDpsChart({
    super.key,
    required this.dpsData,
    this.height = 150,
  });

  @override
  State<PlayerDpsChart> createState() => _PlayerDpsChartState();
}

class _PlayerDpsChartState extends State<PlayerDpsChart> {
  int? _selectedTime;
  Offset? _touchPosition;

  @override
  Widget build(BuildContext context) {
    if (widget.dpsData.timeline.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            "Pas de données graphiques",
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Chart Area
        GestureDetector(
          onPanStart: (details) => _handleTouch(details.localPosition, context),
          onPanUpdate: (details) => _handleTouch(details.localPosition, context),
          onPanEnd: (_) => setState(() {
            _selectedTime = null;
            _touchPosition = null;
          }),
          child: Container(
            height: widget.height,
            width: double.infinity,
            color: Colors.transparent, // Capture touches
            child: CustomPaint(
              painter: _ChartPainter(
                timeline: widget.dpsData.timeline,
                selectedTime: _selectedTime,
              ),
            ),
          ),
        ),
        
        // Tooltip Overlay
        if (_selectedTime != null && widget.dpsData.timeline.containsKey(_selectedTime))
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(child: _buildTooltip(widget.dpsData.timeline[_selectedTime]!)),
          ),
      ],
    );
  }

  void _handleTouch(Offset localPosition, BuildContext context) {
    final timeline = widget.dpsData.timeline;
    if (timeline.isEmpty) return;

    final maxTime = timeline.keys.reduce(max);
    final width = context.size?.width ?? 1;
    
    // Calculate time from X position
    final timePerPixel = maxTime / width;
    final selectedTime = (localPosition.dx * timePerPixel).round();
    
    // Find closest available time
    int? closestTime;
    int minDiff = 999999;
    
    for (var t in timeline.keys) {
      final diff = (t - selectedTime).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestTime = t;
      }
    }

    if (closestTime != null && minDiff < 5) { // Snap within 5 seconds
      setState(() {
        _selectedTime = closestTime;
        _touchPosition = localPosition;
      });
    }
  }

  Widget _buildTooltip(TimeSlice slice) {
    final topSkills = slice.skillDamage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    // Take top 3 skills
    final displaySkills = topSkills.take(3).toList();

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "T: ${_formatDuration(_selectedTime! * 1000)}",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
              ),
              Row(
                children: [
                  if (slice.damage > 0) Text("D: ${_formatNumber(slice.damage)} ", style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                  if (slice.heal > 0) Text("H: ${_formatNumber(slice.heal)} ", style: const TextStyle(color: Colors.greenAccent, fontSize: 10)),
                  if (slice.taken > 0) Text("T: ${_formatNumber(slice.taken)}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 10)),
                ],
              )
            ],
          ),
          if (displaySkills.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...displaySkills.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      getSkillName(int.tryParse(e.key) ?? 0),
                      style: const TextStyle(color: Colors.white70, fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _formatNumber(e.value),
                    style: const TextStyle(color: Colors.white, fontSize: 9),
                  ),
                ],
              ),
            )),
          ]
        ],
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  String _formatNumber(num number) {
    if (number >= 1000000) return "${(number / 1000000).toStringAsFixed(1)}m";
    if (number >= 1000) return "${(number / 1000).toStringAsFixed(1)}k";
    return number.toStringAsFixed(0);
  }
}

class _ChartPainter extends CustomPainter {
  final Map<int, TimeSlice> timeline;
  final int? selectedTime;

  _ChartPainter({required this.timeline, this.selectedTime});

  @override
  void paint(Canvas canvas, Size size) {
    if (timeline.isEmpty) return;

    final maxTime = timeline.keys.reduce(max);
    if (maxTime == 0) return;

    // Find max value for Y axis scaling
    int maxValue = 0;
    for (var slice in timeline.values) {
      maxValue = max(maxValue, slice.damage);
      maxValue = max(maxValue, slice.heal);
      maxValue = max(maxValue, slice.taken);
    }
    if (maxValue == 0) maxValue = 1;

    final widthPerSecond = size.width / maxTime;
    final heightPerValue = size.height / maxValue;

    final paintDmg = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final paintHeal = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
      
    final paintTaken = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final pathDmg = Path();
    final pathHeal = Path();
    final pathTaken = Path();

    bool first = true;
    // Sort keys to draw in order
    final sortedKeys = timeline.keys.toList()..sort();

    for (var t in sortedKeys) {
      final slice = timeline[t]!;
      final x = t * widthPerSecond;
      
      // Invert Y because canvas 0,0 is top-left
      final yDmg = size.height - (slice.damage * heightPerValue);
      final yHeal = size.height - (slice.heal * heightPerValue);
      final yTaken = size.height - (slice.taken * heightPerValue);

      if (first) {
        pathDmg.moveTo(x, yDmg);
        pathHeal.moveTo(x, yHeal);
        pathTaken.moveTo(x, yTaken);
        first = false;
      } else {
        pathDmg.lineTo(x, yDmg);
        pathHeal.lineTo(x, yHeal);
        pathTaken.lineTo(x, yTaken);
      }
    }

    canvas.drawPath(pathDmg, paintDmg);
    canvas.drawPath(pathHeal, paintHeal);
    canvas.drawPath(pathTaken, paintTaken);

    // Draw selection line
    if (selectedTime != null) {
      final x = selectedTime! * widthPerSecond;
      final paintLine = Paint()
        ..color = Colors.white
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintLine);
      
      // Draw dot at intersection points
      if (timeline.containsKey(selectedTime)) {
        final slice = timeline[selectedTime]!;
        final yDmg = size.height - (slice.damage * heightPerValue);
        canvas.drawCircle(Offset(x, yDmg), 3, Paint()..color = Colors.red);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
