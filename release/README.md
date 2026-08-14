# Kudora Candidate Release

This directory documents the Kudora candidate/devnet release pipeline.
`make release-package` generates `manifest.json` and `checksums.sha256`; those
build-specific files are intentionally ignored and must not be edited or
committed by hand.

- Release version: read from `VERSION`
- Release track: `candidate`
- Release type: `devnet_candidate`
- Mainnet launch-ready: `false`

This is not a final mainnet release. The candidate genesis remains structurally
valid but not launch-ready because the committed allocation addresses are
temporary candidate addresses and real validator gentx files are still absent.
