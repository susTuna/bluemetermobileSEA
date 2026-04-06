# BlueMeterSEA — DPS Meter for Blue Protocol: Star Resonance SEA

## Screenshots

<p float="left">
  <img src="images/Screenshot_BPSR_20260214_172155.jpg" width="240" />
  <img src="images/Screenshot_BPSR_20260214_172147.jpg" width="240" />
  <img src="images/Screenshot_BPSR_20260214_172140.jpg" width="240" />
</p>

## Quick Links

- [Latest Release](https://github.com/sustuna/bluemeterseamobilesea/releases/latest)

---

### Description

BlueMeterSEA is a mobile DPS/Heal meter for **Blue Protocol: Star Resonance SEA**.
The app provides real-time combat information through an Android floating overlay.

### What's New — Version 1.1

- Better handling of game-transmitted data.
- More information on the DPS detail screen.
- Small compass for nearby monsters *(may still be unreliable in some situations)*.
- Line number display.
- HP-by-line display for Boss/Monster thanks to **bptimer.com** *(may still be unreliable in some situations)*.

### Key Features

- Floating overlay with DPS / Heal / Damage taken (instant + total).
- Quick counters reset.
- Enhanced DPS detail view.
- Nearby monster information.

### Platform

- Android only.
- iOS: not planned in the short term (overlay limitations).

### Installation

1. Clone the repository and open the Flutter project.
2. Create a file dart_defines.json with : {"BPTIMER_API_KEY": "xxxxxxxxxxxx"} (Ask to bptimer for a key)
3. Build the APK:

```bash
flutter build apk --release --split-debug-info=./debug_info --obfuscate --dart-define-from-file=dart_defines.json
```

4. Install the APK on your Android device.
5. Allow the "display over other apps" permission.

### Usage

- Start the game, then launch bluemetersea.
- Ensure overlay permission is granted.
- Use the reset button whenever needed.

### Quick Troubleshooting

- Overlay not visible: check the "display over other apps" permission.
- Overlay drag issues: restart the app.
- Nearby compass may be inaccurate in some cases while improvements are ongoing.

### Contributing

- Contributions (issues / PRs) are welcome.

### Privacy & Security

- No personal data is collected or transmitted.

### License

- GNU Affero General Public License v3.

### Acknowledgements

- Thanks to the PC bluemetersea project: https://github.com/caaatto/bluemetersea
- Thanks to **bptimer.com** for HP-by-line data used in the app: https://bptimer.com
- Thanks to the Mobile bluemetersea project: https://github.com/jbourny/bluemeterseamobile