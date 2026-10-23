# The GIF Wardrobe

This folder is the ONLY place GIFs live in nightjar — one GIF per
area, filed by the operator. A slot with a GIF in it lights its area
up; a slot without one leaves the built-in ceremony standing, exactly
as the app runs today.

## The slots

Upload a GIF here with EXACTLY its slot's name, replacing whatever
was there before:

| File | Area |
| --- | --- |
| `boot.gif` | The boot ceremony — played as the boot film, ahead of the bundled device films |
| `centipede.gif` | The Centipede release splash |
| `eazy.gif` | The EAZY ignition |
| `magdump.gif` | The MAGDUMP ignition |
| `redframe.gif` | The EMCON Alpha (redframe) splash |
| `assault.gif` | The Net-Assault ignition |

## How to file one

1. Bring the GIF into this folder (`ios/nightjar/gifs/`) under its
   slot's exact name — one at a time.
2. Tell Skelli which area it's for, so the change is pushed and
   verified like any other.
3. Rebuild. The area picks its film up on its own.

## What the app does with it

- Any screen size is handled: a GIF whose shape disagrees with the
  screen hangs whole and centered on black; a GIF whose shape
  matches fills the screen. Nothing is cropped past its edges.
- Splashes play one full loop, held between three and six seconds —
  shorter films get the house's three-second beat, longer ones are
  capped at six. Tap still skips.
- The boot GIF is the boot: when `boot.gif` is filed, the glitch
  flood stands down and the film's own ceremony plays.
- The house GIF master switch still rules: with GIFs stilled in
  settings, a wardrobe film stands on its first frame.
