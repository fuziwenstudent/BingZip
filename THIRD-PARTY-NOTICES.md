# Third-Party Notices

BingZip is an independent macOS GUI built on top of the 7-Zip command-line
engine. It is not affiliated with or endorsed by the 7-Zip project.

## 7-Zip 26.05

- Copyright (C) 1999-2026 Igor Pavlov
- Website: <https://7-zip.org>
- Source included in this repository: `C/`, `CPP/`, `Asm/`, `DOC/`

The 7-Zip source code is distributed under the licenses described in
[`DOC/License.txt`](DOC/License.txt). In summary:

- Most files are covered by the **GNU LGPL**.
- `CPP/7zip/Compress/Rar*` files are covered by the **GNU LGPL with the
  unRAR license restriction**. You must follow both the LGPL and the unRAR
  restriction. In particular, the RAR decompression code must not be used to
  develop a RAR-compatible compression algorithm.
- A few files are covered by the BSD 3-clause license, the BSD 2-clause
  license, or are public domain where explicitly stated in the source file.

The complete and authoritative license text is in
[`DOC/License.txt`](DOC/License.txt). Please read it before redistributing
BingZip or the bundled engine.

BingZip invokes the separately built `7zz` executable at runtime. The release
packages also bundle `7zz`, `7zr` and `lzma`, which are built from the 7-Zip
sources in this repository. The corresponding source code is included here.

## RAR creation

Creating RAR archives requires RARLAB's proprietary `rar` command-line tool.
BingZip does **not** bundle that tool. RAR extraction is provided by the built-in
7-Zip engine. If you install and use RARLAB's `rar` tool, you must comply with
RARLAB's own license terms.

## Apple frameworks

BingZip uses Apple's AppKit, FinderSync and related system frameworks. These
frameworks are provided by macOS and are not part of this repository.

## App icon and documentation

The BingZip app icon, screenshots and original documentation are part of the
BingZip project and are covered by the project's MIT license unless stated
otherwise.
