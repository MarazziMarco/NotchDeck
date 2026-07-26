# Changelog

All notable changes to NotchDeck are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow [Semantic Versioning](https://semver.org/) once it reaches 1.0.

NotchDeck is **pre-1.0** and under active development; interfaces may change.

## [Unreleased]

### Added

- **Community module architecture** — `NotchDeckModule`, `ModuleDescriptor`,
  `ModuleCapability`, `ModuleSurface`, `AnyNotchDeckModule`, `ModuleContext`,
  and `CommunityModuleRegistry`. Modules are source-integrated through reviewed
  pull requests and declare the sensitive capabilities they need.
- **Example module** (`Modules/Examples/UptimeExampleModule`) demonstrating the
  architecture; not enabled by default.
- Public-project documentation: README, `LICENSE` (MIT), `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, `SECURITY.md`, `docs/ARCHITECTURE.md`,
  `docs/AGENT_INTEGRATION.md`, `docs/TROUBLESHOOTING.md`, and the
  `docs/modules/` guides.
- GitHub Actions CI (generate project, build Debug + Release, run tests) and
  issue / pull-request templates.

### Notable prior work (pre-history, before the public repository)

- Notch shell: borderless non-activating `NSPanel`, responsive geometry,
  physical-idle vs compact-activity vs expanded presentation.
- Utilities: Quick Note, Now Playing, File Shelf (move / reference staging with
  a crash-safe manifest), Mirror, Pomodoro Focus, Downloads (today + active
  filtering), screenshots.
- Agents: Claude Code / Codex session monitoring via installed hooks, terminal
  presence lifecycle (Active vs Recent), provider logos, Focus Terminal (raise
  the existing tab by TTY), and a synchronous approval bridge with delivery
  acknowledgement and a hybrid terminal-fallback mode.
- Home customization sheet, first-launch Permissions Setup window, and the
  compact live-activity system.

_No versioned releases have been published yet._
