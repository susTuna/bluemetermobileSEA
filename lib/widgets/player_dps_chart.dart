import 'dart:math';
import 'package:flutter/material.dart';
import '../core/models/dps_data.dart';
import '../core/data/skill_names.dart';

class PlayerDpsChart extends StatefulWidget {
  final DpsData dpsData;
  final double height;
  final bool showDps;
  final bool showHps;
  final bool showTaken;

  const PlayerDpsChart({
    super.key,
    required this.dpsData,
    this.height = 150,
    this.showDps = true,
    this.showHps = true,
    this.showTaken = true,
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
                showDps: widget.showDps,
                showHps: widget.showHps,
                showTaken: widget.showTaken,
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
    // Aggregate skills by name to avoid duplicates
    final Map<String, int> aggregatedSkills = {};
    for (var entry in slice.skillDamage.entries) {
      final skillId = int.tryParse(entry.key) ?? 0;
      final skillName = getSkillName(skillId);
      aggregatedSkills[skillName] = (aggregatedSkills[skillName] ?? 0) + entry.value;
    }

    final topSkills = aggregatedSkills.entries.toList()
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
                  if (widget.showDps && slice.damage > 0) Text("D: ${_formatNumber(slice.damage)} ", style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                  if (widget.showHps && slice.heal > 0) Text("H: ${_formatNumber(slice.heal)} ", style: const TextStyle(color: Colors.greenAccent, fontSize: 10)),
                  if (widget.showTaken && slice.taken > 0) Text("T: ${_formatNumber(slice.taken)}", style: const TextStyle(color: Colors.orangeAccent, fontSize: 10)),
                ],
              )
            ],
          ),
          if (displaySkills.isNotEmpty && widget.showDps) ...[
            const SizedBox(height: 4),
            ...displaySkills.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
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
  final bool showDps;
  final bool showHps;
  final bool showTaken;

  _ChartPainter({
    required this.timeline,
    this.selectedTime,
    required this.showDps,
    required this.showHps,
    required this.showTaken,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (timeline.isEmpty) return;

    final maxTime = timeline.keys.reduce(max);
    if (maxTime == 0) return;

    // Find max value for Y axis scaling
    int maxValue = 0;
    for (var slice in timeline.values) {
      if (showDps) maxValue = max(maxValue, slice.damage);
      if (showHps) maxValue = max(maxValue, slice.heal);
      if (showTaken) maxValue = max(maxValue, slice.taken);
    }
    if (maxValue == 0) maxValue = 1;

    final widthPerSecond = size.width / maxTime;
    final heightPerValue = size.height / maxValue;

    // Draw Grid
    _drawGrid(canvas, size);

    final paintDmg = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintHeal = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
      
    final paintTaken = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Collect points
    final pointsDmg = <Offset>[];
    final pointsHeal = <Offset>[];
    final pointsTaken = <Offset>[];

    final sortedKeys = timeline.keys.toList()..sort();

    for (var t in sortedKeys) {
      final slice = timeline[t]!;
      final x = t * widthPerSecond;
      
      if (showDps) pointsDmg.add(Offset(x, size.height - (slice.damage * heightPerValue)));
      if (showHps) pointsHeal.add(Offset(x, size.height - (slice.heal * heightPerValue)));
      if (showTaken) pointsTaken.add(Offset(x, size.height - (slice.taken * heightPerValue)));
    }

    if (showDps) canvas.drawPath(_computeSmoothPath(pointsDmg), paintDmg);
    if (showHps) canvas.drawPath(_computeSmoothPath(pointsHeal), paintHeal);
    if (showTaken) canvas.drawPath(_computeSmoothPath(pointsTaken), paintTaken);

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
        
        if (showDps) {
          final yDmg = size.height - (slice.damage * heightPerValue);
          canvas.drawCircle(Offset(x, yDmg), 4, Paint()..color = Colors.red);
        }
        if (showHps) {
          final yHeal = size.height - (slice.heal * heightPerValue);
          canvas.drawCircle(Offset(x, yHeal), 4, Paint()..color = Colors.green);
        }
        if (showTaken) {
          final yTaken = size.height - (slice.taken * heightPerValue);
          canvas.drawCircle(Offset(x, yTaken), 4, Paint()..color = Colors.orange);
        }
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;

    // Vertical lines (Time) - Draw 5 lines
    int timeSteps = 5;
    for (int i = 1; i < timeSteps; i++) {
      double x = (size.width / timeSteps) * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintGrid);
    }

    // Horizontal lines (Value) - Draw 4 lines
    int valueSteps = 4;
    for (int i = 1; i < valueSteps; i++) {
      double y = (size.height / valueSteps) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }
  }

  Path _computeSmoothPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points[0].dx, points[0].dy);
    if (points.length < 2) return path;

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i < points.length - 2 ? points[i + 2] : p2;

      final cp1x = p1.dx + (p2.dx - p0.dx) * 0.2;
      final cp1y = p1.dy + (p2.dy - p0.dy) * 0.2;
      final cp2x = p2.dx - (p3.dx - p1.dx) * 0.2;
      final cp2y = p2.dy - (p3.dy - p1.dy) * 0.2;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
