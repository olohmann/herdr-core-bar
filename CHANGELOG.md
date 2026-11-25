# Changelog

All notable changes to Herdr Core Bar are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-11-25

### Changed

- The popover header and About tab show the real app icon instead of a stand-in symbol.
- The menu bar item uses a new glyph taken from the app icon, a menu bar strip above three status dots,
  replacing the generic hexagon grid.

## [0.1.0] - 2026-11-24

Initial release.

### Added

- Menu bar item with live counts of agent terminals that are blocked, done but unread, and working.
- Popover listing every terminal grouped by Herdr space and tab, with status, title, and progress.
- Click a terminal to focus it in Herdr.app; marking it as seen is shared with Herdr.app through `herdr.seen`.
- Terminals on remote machines connected to herdr-core.
- Notifications when an agent becomes blocked or finishes a turn.
- Launch at login.
- Agents-only filter that hides plain shells.
- Automatic updates through Sparkle, signed with EdDSA.

[Unreleased]: https://github.com/olohmann/herdr-core-bar/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/olohmann/herdr-core-bar/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/olohmann/herdr-core-bar/releases/tag/v0.1.0
