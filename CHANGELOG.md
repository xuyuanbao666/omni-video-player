# Changelog

## 0.4.2

- Require a persistent owner-managed Android release signing key and pinned certificate SHA-256; no temporary signing fallback in release CI.
- Verify in-place universal APK upgrades using adb install -r with increasing versionCode, retained first-install timestamp and launch smoke test.
- First migration from old temporary certificates may require one uninstall; the initial upgrade fixture is re-signed for test only.
- Replace the default Flutter Android launcher with Omni adaptive and legacy icons.

## 0.4.1

- Fix narrow portrait player layout; use full-width 16:9 canvas and useful empty state.
- Isolated scrubber with one seek on release, stable video texture and delayed buffering overlay.
- Mobile orientation selection and landscape fullscreen with restore.
- Build universal Android APK with signature and emulator install/start checks.

## 0.4.0

- Minimal floating playback dock, auto-hide, compact advanced controls, mobile navigation and desktop split view.
- New in-app Omni mark and reduced-motion-aware entrance animation.
- Local played-video preview cache, grid/list media library, progress and optional video-derived accent colors.
- Categorized settings, bounded local thumbnail cache and privacy controls.

## 0.3.1

- Frosted glass surfaces, app-local aurora gradients and a rounded playback dock.
- Light and dark variants with a persisted glass appearance toggle.
- Preserve existing media playback, library and localization features.
- Feature branches run six-platform artifact builds without auto-publishing.

## 0.3.0

- Professional responsive player layout and light/dark themes, Chinese/English UI.
- Imported media library with folder scan on desktop, search, sort and favorites.
- Touch gestures, keyboard shortcuts, audio track selection and video fit modes.
- GitHub stable release update checker (no automatic installation).
- Playback/history safeguards and six-platform development builds.

## 0.2.0

- Subtitle track picker and external UTF-8 subtitle loading.
- Local playback history, resume positions and privacy settings.
- Video frame capture with desktop save or mobile/web share.
- Native hardware acceleration preference (restart required).
- Android picture-in-picture bridge and desktop compact view.
- History regression tests and updated repository links.

Platform compatibility and signing limitations are documented in README.md.
