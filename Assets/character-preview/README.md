# SIU kick character preview

Source: the GIF supplied by the user at `/Users/gwonjaewon/Downloads/i15792788660.gif`.

The eight `kick-frames/kick-XX.png` images are consecutive 10 fps frames from the approach and kick, with a true alpha channel. `siu-kick-preview.png` is the transparent animated PNG. `siu-kick-preview.gif` is an opaque dark-background preview for easy viewing. `siu-kick-sheet.png` shows all eight poses.

The person mask was extracted with macOS Vision and cleaned with FFmpeg's green despill filter. The last frame was clipped to keep the game's separate football out of the character sprite. The original footage is low resolution, so some fine edges remain soft.

The movement sprites (`move-frames` and `run-frames`) and tackle sprites (`tackle-frames`) were generated with the built-in image generator using the user's kick cutout as a visual reference. The generator output had a painted checkerboard rather than alpha; `Scripts/extract-sprite-sheet.swift` used Vision person segmentation, and `Scripts/trim-sprite.swift` removed transparent margins. The game bundles trimmed copies in `Sources/MacArrow/Resources`.

Additional generated strips cover front/back running, front/side shooting, and front/back tackling. Those strips were also segmented and trimmed into transparent per-frame PNGs. The game now bundles 44 character frames in total and chooses an action set based on the nearest of eight visual directions; only the original back-view shot uses the user-supplied GIF.

The source footage's distribution rights were previously unverified. On 2026-09-30,
the user was explicitly asked about public Homebrew distribution and the existing
footage warning, confirmed usage/distribution rights, and authorized publication.
This records that confirmation, not an independent rights audit. The generated
poses still approximate the player and should be reviewed before distribution.
