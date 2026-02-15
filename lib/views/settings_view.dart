import 'package:flutter/material.dart';
import '../core/models/overlay_settings.dart';

class SettingsView extends StatelessWidget {
  final OverlaySettings settings;
  final VoidCallback onThemeChanged;
  final VoidCallback onOpacityChanged;
  final Function(OverlayAnchor anchor) onAnchorSelected;

  const SettingsView({
    super.key,
    required this.settings,
    required this.onThemeChanged,
    required this.onOpacityChanged,
    required this.onAnchorSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = settings.theme;
    final textColor = theme.textColor;
    final secondaryColor = theme.secondaryTextColor;
    final accentColor = theme.accentColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Anchors Section ---
          _SectionHeader(title: 'Position', textColor: textColor),
          const SizedBox(height: 4),
          _AnchorRow(
            settings: settings,
            onAnchorSelected: onAnchorSelected,
            accentColor: accentColor,
            textColor: textColor,
            secondaryColor: secondaryColor,
          ),
          const SizedBox(height: 8),

          // --- Theme Section ---
          _SectionHeader(title: 'Thème', textColor: textColor),
          const SizedBox(height: 4),
          _ThemeSelector(
            currentThemeId: settings.themeId,
            onThemeSelected: (id) {
              settings.themeId = id;
              settings.saveTheme();
              onThemeChanged();
            },
            accentColor: accentColor,
            textColor: textColor,
          ),
          const SizedBox(height: 8),

          // --- Opacity Section ---
          _SectionHeader(title: 'Opacité', textColor: textColor),
          const SizedBox(height: 2),
          _OpacitySlider(
            value: settings.backgroundOpacity,
            onChanged: (v) {
              settings.backgroundOpacity = v;
              settings.saveOpacity();
              onOpacityChanged();
            },
            accentColor: accentColor,
            textColor: textColor,
            secondaryColor: secondaryColor,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color textColor;

  const _SectionHeader({required this.title, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: textColor,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _AnchorRow extends StatelessWidget {
  final OverlaySettings settings;
  final Function(OverlayAnchor) onAnchorSelected;
  final Color accentColor;
  final Color textColor;
  final Color secondaryColor;

  const _AnchorRow({
    required this.settings,
    required this.onAnchorSelected,
    required this.accentColor,
    required this.textColor,
    required this.secondaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: kOverlayAnchors.map((anchor) {
        return Expanded(
          child: GestureDetector(
            onTap: () => onAnchorSelected(anchor),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(anchor.icon, size: 14, color: accentColor),
                  const SizedBox(height: 2),
                  Text(
                    anchor.name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  final String currentThemeId;
  final Function(String) onThemeSelected;
  final Color accentColor;
  final Color textColor;

  const _ThemeSelector({
    required this.currentThemeId,
    required this.onThemeSelected,
    required this.accentColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: kOverlayThemes.entries.map((entry) {
        final theme = entry.value;
        final isSelected = entry.key == currentThemeId;
        return GestureDetector(
          onTap: () => onThemeSelected(entry.key),
          child: Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? theme.accentColor : theme.accentColor.withValues(alpha: 0.3),
                width: isSelected ? 1.5 : 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: theme.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  theme.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _OpacitySlider extends StatefulWidget {
  final double value;
  final Function(double) onChanged;
  final Color accentColor;
  final Color textColor;
  final Color secondaryColor;

  const _OpacitySlider({
    required this.value,
    required this.onChanged,
    required this.accentColor,
    required this.textColor,
    required this.secondaryColor,
  });

  @override
  State<_OpacitySlider> createState() => _OpacitySliderState();
}

class _OpacitySliderState extends State<_OpacitySlider> {
  late double _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
  }

  @override
  void didUpdateWidget(_OpacitySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _currentValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '${(_currentValue * 100).round()}%',
          style: TextStyle(
            color: widget.secondaryColor,
            fontSize: 10,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: widget.accentColor,
              inactiveTrackColor: widget.accentColor.withValues(alpha: 0.2),
              thumbColor: widget.accentColor,
              overlayColor: widget.accentColor.withValues(alpha: 0.1),
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: _currentValue,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              onChanged: (v) {
                setState(() {
                  _currentValue = v;
                });
              },
              onChangeEnd: (v) {
                widget.onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
