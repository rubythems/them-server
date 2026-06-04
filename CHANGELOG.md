# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

### Changed

- Refreshed generated project templates with `kettle-jem`.

### Deprecated

### Removed

### Fixed

- Restored the app-specific Rackup binstub and Rake tasks after the template
  refresh.
- Fixed Hanami route boot by removing the missing `:main` slice mount.
- Fixed Rack boot by loading the actual authentication app.
- Fixed authentication app boot by not starting an undefined Hanami mail
  provider.
- Aligned generated Hanami DB and type namespaces with `Them::Server`.
- Completed the `Them::Server` namespace and require-path migration from the
  legacy upstream naming.
- Configured the Hanami DB provider and legacy DB helper to share Hanami-style
  test database URL handling, including parallel worker suffixes.

### Security

## [0.1.0] - 2025-10-10

- Initial release
