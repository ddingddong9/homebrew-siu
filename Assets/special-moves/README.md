# SIU special moves (1.13.0-beta.1)

User-supplied GIFs: `세레머니.gif` (31 frames), `발재간.gif` (164 frames), `백숏.gif` (53 frames).
On 2026-09-30 the user explicitly confirmed that they have the usage/distribution rights
and authorized public Homebrew distribution. This records the user's confirmation,
not an independent rights audit.

The game uses **71 transparent RGBA PNG frames** in `Sources/MacArrow/Resources`:

| Action | Source frames (zero-based) | Game playback | Trigger |
| --- | --- | --- | --- |
| celebration | 4–22 (19 frames) | 2.1 s | automatic after a goal, AI and LAN |
| stepover | 0–42 (43 frames) | 1.0 s | E, while possessing the ball |
| backheel / 백숏 | 13–21 (9 frames) | 0.65 s | 1v1 Q / 2v2 Shift+Q; back chop retains possession and turns 180°, not a shot |

E/Q are **SIU-specific additions**, not claimed FC Online official controls.
Special moves cannot overlap another special action and respect pause, possession,
kickoff ownership and cooldown. The host validates LAN actions and broadcasts
accepted animation events. Both Macs need protocol 10 / this app version.

Extraction uses `Scripts/extract-special-moves.swift`: original GIF pixels → macOS
Vision foreground instances → red-shirt instance selection → crop/pose guidance →
opponent-blue removal → connected-component cleanup → RGBA frame canvas.
No generated poses were substituted. The user expressly selected this deterministic
method instead of the image generator. macOS 14+ is recommended for extraction;
runtime needs only the already-extracted PNGs and supports macOS 13+.

The source clips are low resolution; motion blur, original top-of-frame clipping
during the celebration, and parts obscured by defenders cannot be reconstructed.
Frame sheets document those limitations. GIF previews have binary alpha and use
game playback timing; the game uses PNG alpha for softer edges.

Rebuild, supplying your own authorized source GIF paths:

```sh
swift Scripts/extract-special-moves.swift celebration /path/to/세레머니.gif Sources/MacArrow/Resources Assets/special-moves
swift Scripts/extract-special-moves.swift stepover /path/to/발재간.gif Sources/MacArrow/Resources Assets/special-moves
swift Scripts/extract-special-moves.swift backheel /path/to/백숏.gif Sources/MacArrow/Resources Assets/special-moves
```
