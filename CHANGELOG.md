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

- Added support for JRuby 10.1 and TruffleRuby 34.0.

### Changed

- Retemplated project metadata and CI/development automation with `kettle-jem` v7.0.0.

### Deprecated

### Removed

### Fixed

### Security

## [0.1.0] - 2026-06-14

- TAG: [v0.1.0][0.1.0t]
- COVERAGE: 72.28% -- 777/1075 lines in 28 files
- BRANCH COVERAGE: 51.76% -- 147/284 branches in 28 files
- 77.50% documented
- Initial release

### Changed

- Raised the runtime dependency floor for `oauth2` to `>= 2.0.21`.
- Updated the locked `auth-sanitizer` runtime dependency to v0.2.1.
- Updated the locked `snaky_hash` runtime dependency to v2.0.5.
- Refreshed generated project templates with `kettle-jem`.
- Retemplated generated project metadata and documentation links for the
  `rubythems` repository organization.

### Fixed

- Restored `docs/CNAME` so the generated documentation site keeps its custom domain.
- Split SQLite adapter dependencies into platform-aware appraisal gemfiles and
  route JRuby SQLite URLs through JDBC so JRuby CI does not install native
  `sqlite3`.
- Kept the MRI-only `debug` gem out of cross-platform appraisal dependency
  resolution so JRuby and TruffleRuby CI do not try to install it.
- Fixed remaining CI failures from E2E database cleanup, gem file fixtures, and
  inherited template coverage thresholds.
- Fixed CI appraisal gemfiles by declaring test dependencies in the gemspec.
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

[Unreleased]: https://github.com/rubythems/them-server/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rubythems/them-server/compare/2a13af94f52cddc9142f80fe00f66c800ad2d8eb...v0.1.0
[0.1.0t]: https://github.com/rubythems/them-server/releases/tag/v0.1.0
