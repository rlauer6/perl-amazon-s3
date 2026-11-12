# Amazon::S3 2.1.3 Release Notes

## Overview

This is a bug-fix release that corrects the CRC32 checksum
implementation and removes three unnecessary runtime dependencies.
It also includes significant internal build system improvements
provided by an updated `CPAN::Maker::Bootstrapper`.

## Bug Fixes

### CRC32 Checksum Correctness

The CRC32 digest in `Amazon::S3::Constants` previously returned a
raw integer. It now wraps the result with `pack 'L>'` to produce
the correct four big-endian bytes that AWS expects. This fixes
checksum verification for objects uploaded or retrieved with the
CRC32 algorithm.

A new test subtest (`t/08-checksums.t`) confirms that the digest
produces `cbf43926` for the standard input `123456789` and that
`_verify_checksums` correctly accepts the matching base64-encoded
value (`y/Q5Jg==`).

## Dependency Changes

Three modules have been removed from the runtime dependency list
as they automatically included with other dependencies.

- `CLI::Simple::Constants`
- `CLI::Simple::Utils`
- `URI::Escape`

## Build System Updates

The internal build infrastructure managed by
`CPAN::Maker::Bootstrapper` has been substantially overhauled.
These changes do not affect the installed module but improve the
development and CI experience:

- **Makefile**: Added GNU Make 4.3 grouped-target guard; introduced
  `build-config.mk`; added `real-quick` target; improved
  incremental build behaviour for `cpanfile`, dependency scans,
  and `provides` by skipping rewrites when content is unchanged.
- **`perl.mk`**: Simplified lint tool detection; converted tidy
  and critic rules to grouped targets; separated syntax and POD
  checks into sentinel files; `deps.mk` is now a hard include.
- **`local.mk`**: Added optional `cpm --experimental-config`
  support; Carton installs now cover both runtime and test
  cpanfiles.
- **`update.mk`**: Replaced `MANAGED_FILES` with separate
  `MANAGED_MK_FILES` and `MANAGED_SOURCE_FILES`; added
  `pre-update` hook; improved version-drift detection with
  case-insensitive comparisons and clearer error messages.
- **`builder`**: Now accepts the project directory as an argument;
  lint tool installation is gated on `LINT=on` and the presence
  of a corresponding rc file; build steps are now run as discrete
  `make` invocations.
- **New includes**: `add-plugin.mk`, `build-init.mk`,
  `builder.mk`, `test.mk`.
- **Removed**: `release-notes.mk` (superseded by other tooling).
