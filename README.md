# Purr Pat · 撸猫

A calm cat-petting toy for iPhone and iPad. A cat lies on a cushion by the window. Stroke with the fur and it purrs — in the speaker, and in your hand.

## Open

```
brew install xcodegen && xcodegen generate && open PurrPat.xcodeproj
```

Run the **Purr Pat** scheme. The scheme includes `Products.storekit`, so Pro can be purchased in the simulator without App Store Connect.

## What you can do

- Stroke the head and back, along the fur. The coat parts and slowly springs back.
- Drag outward from the base of the tail to stretch it. Let go and it curls home.
- Stay gentle and a purr builds. Rough or backward strokes cool the cat off. When it is really happy it stretches or kneads. A small heart is the only meter.
- Purr is on by default. Audio follows the silent switch. The haptic rumble does not.
- Four coats and the daylight cushion are free. **Purr Pat Pro** (`com.limuye.purrpat.pro`, one time) unlocks the rest of the coats, moonlight, rain, and the other sleeves.
- Share a still from the arrow button.

Languages: English, Simplified Chinese, Traditional Chinese, Japanese.

## How the fur works

A groom map remembers which way the coat was pushed. Every frame a damped spring carries it back toward the natural grain. On a device that has a GPU, a Metal shader turns that map into parted, silky fur at the display refresh rate. In the simulator, and for screenshots, the same idea is drawn on the CPU so the picture is still there when there is no GPU.

## CI

- `.github/workflows/build.yml` builds and runs unit tests on a simulator for pull requests.
- `.github/workflows/screenshots.yml` captures the daylight stroke, moonlight, the coat row, the paywall, and a short stroking video.
- `.github/workflows/testflight.yml` archives with automatic signing (build number = run number + 9) on a tag `v*` or when the workflow is run by hand. The App Store Connect app is `6838995846` (`com.limuye.purrpat`). After upload it marks the build as using no non-exempt encryption and adds it to the internal TestFlight group. If `com.limuye.purrpat.pro` is not in App Store Connect yet, the paywall still shows US$2.99.
