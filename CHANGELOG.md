# Changelog

## 1.4.2

OffSec's own reporting guidance (see the OSCP Reporting Requirements article) is explicit that no
particular tool or template is required, only a clear PDF write-up of the exam objectives - so
`mkbox -a --odt` no longer assumes you have a copy of OffSec's own exam report template lying
around, or depends on one at all.

### Added

- **A bundled, self-contained ODT template (`templates/mkbox-default.odt`).** `mkbox -a --odt` now
  works with no `=path` and no `$MKBOX_ODT_TEMPLATE` - it falls back to this template, shipped
  alongside the script, instead of refusing to run. Built from pandoc's own default reference
  document (so its heading styles already match pandoc's own naming, with nothing to patch) plus:
  decimal outline numbering wired up for heading levels 1-3 (`1`, `1.1`, `1.1.1`, matching the
  structure `mkbox -a` already builds), a page-number field in the footer, and a paragraph style
  (`MkboxPageBreak`) used to force a page break before the cover page and before the Table of
  Contents. An explicit `--odt=<path>` / `$MKBOX_ODT_TEMPLATE` still work exactly as before, for
  anyone who'd rather use OffSec's own template or a company one.
- **A real cover page and Table of Contents**, generated from the assembled Markdown itself (title,
  `--author "Name"` or `$MKBOX_AUTHOR`, and today's date), via pandoc YAML metadata and a native ODT
  `<text:table-of-content>` field - not copied out of any template, so this works the same whether
  `--odt` uses the bundled default or a custom one. The TOC's entries and page numbers still need one
  manual step after opening the file (Tools > Update > All, or right-click > Update Index) - normal
  for any document with a TOC field, since nothing computes final page numbers before the document is
  actually laid out by LibreOffice/Word.
- `fix_odt_heading_styles` (now doing more than just heading styles - see Internal) patches a
  `MkboxPageBreak` paragraph style into *any* `--odt` template that doesn't already define one, so
  the forced page breaks before the cover page and the Table of Contents work even with a custom
  template that was never built with mkbox in mind.
- **A `Tools Used` subsection under `Methodology`**, pre-filled (not a `TODO`) naming `mkbox` itself
  by version and repo link, with a prompt to list anything else used - OSCP reporting expects any
  non-standard tooling to be documented, and now that doesn't depend on remembering to write it in.
- `--author="Name"` for `mkbox -a` (falls back to `$MKBOX_AUTHOR` if unset), used on the cover page.

### Internal

- The cover page / TOC / forced page breaks are built into a separate temporary Markdown file (YAML
  front matter plus raw `{=opendocument}` blocks for the ODT-specific bits) that's only ever fed to
  pandoc - `outfile.md`, the plain draft a student actually reads, stays free of that scaffolding.
- `fix_odt_heading_styles` now does two independent, unrelated post-processing patches (heading style
  names, and the `MkboxPageBreak` style above) instead of just the one; each is skipped on its own if
  the thing it would fix is already present, or if `python3` is missing entirely.
- `MKBOX_SCRIPT_DIR` is resolved once near the top of the script (via `readlink -f "$0"`) so mkbox can
  find its own bundled `templates/` directory regardless of the working directory or symlinks, on
  every code path - not just the box-shell path that already resolved `MKBOX_BIN` for other reasons.
- tests/smoke.sh: 13 new checks covering the bundled default template, the cover page/TOC/page-break
  scaffolding, the `MkboxPageBreak` patch on a custom template, and the `Tools Used` section (189/189
  passing).

## 1.4.1

Follow-up after actually rendering a multi-box `--odt` draft against the real exam report template
and reading it page by page, rather than just checking the markdown source - three consistency
problems only showed up once rendered.

### Fixed

- **Proof checklist rendered as an empty box instead of a check mark in ODT.** `- [x] local.txt: ...`
  is Markdown task-list syntax; pandoc's ODT writer renders it as a Unicode checkbox glyph
  (`☒`/`☐`), and the exam report template's body font doesn't have that glyph, so every checklist
  line showed up as a blank tofu box. `mkbox -a --odt` now tells pandoc to read task lists as plain
  text (`-f markdown-task_lists`), so it comes through as literal `[x]` / `[ ]` instead.
- **Multiple findings in the same phase ran together with no visual break.** Once a finding's own
  heading is demoted past the template's depth cap and converted to a bold paragraph (see 1.4.0), two
  findings back to back had nothing but a blank line between them, and the template's body paragraph
  style has no visible spacing of its own - they read as one continuous block. `findings_section` now
  puts a `---` rule between consecutive findings.

### Added

- **An unfilled `addvuln` entry is now caught at report time.** If the templated Explanation/Fix
  placeholder text in a `vulns/*.md` file was never actually edited, `mkbox -r` now prints a warning
  naming the file - the same pattern as the existing unticked-Proof-checklist warning - instead of
  that boilerplate text silently making it into the report and the ODT.
- **`mkbox -a` no longer throws away each box's own warnings.** Previously, `mkbox -a` ran each box's
  `make_report` with its output fully discarded (it only wanted the report file as a side effect), so
  an unticked Proof item, an unfilled finding, or a leaked-password warning on any individual box
  never surfaced while assembling. Those warnings are now collected and printed once, prefixed with
  the box name, right after `Assembled draft:` / `ODT draft:`.

## 1.4.0

### Added

- **`addvuln initial|privesc|post <title> <critical|high|medium|low>`.** Opens a small templated
  finding (Explanation/Fix) in `$EDITOR` and files it under `vulns/`, in place of an ad-hoc
  `note "found this: <link>"`. `mkbox -r` collects these into a new **Findings** section, grouped and
  ordered by phase, with title, severity, explanation and fix for each.
- **`setad on|off`, and `--ad` at box creation.** Flags a box as part of an Active Directory set
  (stored as `AD_SET` in `box.env`; `boxinfo` shows `AD set: yes`). Drives how `mkbox -a` (below)
  buckets that box.
- **`mkbox -a|--assemble <outfile.md> [--odt[=template.odt]] [--creds] <box1> [box2 ...]`.** Collates
  several boxes' own reports into a single draft shaped like the official exam report template:
  standalone boxes under `Independent Challenges` (each under its own `Target #N`), AD-flagged boxes
  under `Active Directory Set` (one combined ports table, then each box under its own name), `TODO`
  stubs for `High-Level Summary` / `Recommendations` / `Methodology`, and each box's own report
  content nested underneath with its headings demoted and capped at the template's own depth (deeper
  content becomes bold paragraphs instead of ever-deeper headings, so nothing renders as literal
  `####`). An unfilled `notes.md` section is rewritten as `_(nothing recorded)_` in the assembled
  draft only, to flag gaps at a glance. Deliberately does not add a Maintaining Access / House
  Cleaning stub - the current OSCP Exam Guide doesn't ask for persistence or cleanup on exam hosts.
- **`--odt` conversion for `mkbox -a`.** Converts the assembled draft to ODT via
  `pandoc --reference-doc=<template>`, styled from the official exam report template (or any ODT you
  point it at). Patches the generated file's heading style references to match whatever naming
  convention the template itself actually uses (some templates, including OffSec's, name their
  heading styles `Heading1`/`Heading2` instead of pandoc's own convention, which would otherwise leave
  every heading unstyled). Falls back to `$MKBOX_ODT_TEMPLATE` when `--odt` is given without a path.
  Needs `pandoc`; the style-name patch additionally needs `python3` and silently no-ops without it.
  Copies the template's styles only, not its cover page, TOC, or other content.

### Internal

- `demote_headings` is now fence-aware (tracks ` ``` ` so a `#`-prefixed line inside nmap output or a
  code block is never mistaken for a heading) and caps heading depth with a `<max_level>` argument,
  rather than just adding a fixed number of `#`s with no ceiling - needed once `mkbox -a` nests a whole
  report several levels deep under the template's own numbering.
- Fixed an edge case where an empty `notes.md` placeholder bullet (`-` with nothing after it) could
  cause pandoc's markdown reader to absorb the heading immediately after it as unparsed list content;
  rewriting that bullet to `_(nothing recorded)_` avoids the ambiguity entirely (and is more useful in
  an assembled draft than an empty section would be).

## 1.3.0

### Added

- **`addexploit <file-in-exploits/> <source-url> [what you changed]`.** Records where a public
  exploit came from and what you modified, in `exploits/SOURCES.md`. The report shows these entries
  at the top of **Exploits / scripts**, ahead of the plain file list (`SOURCES.md` itself is left out
  of that list).
- **`pivot <to-host> <via> [note]`.** Records an AD lateral-movement hop as a timeline note
  (`pivot DC01 "psexec with bob:ntlm-hash"`). The report pulls every hop into its own **Pivot chain**
  section, right under the open-ports table, so a multi-host chain doesn't get buried in the full
  timeline further down.
- **`proofshot local|proof [value]`.** `shot` + `markproof` in one step: saves the clipboard image as
  proof evidence and ticks the Proof checklist at the same time, so the screenshot and the tick can't
  drift apart. `user` / `root` are aliases, same as `markproof`.
- **Proof-missing warning.** `mkbox -r` now checks the Proof checklist and prints a
  `WARNING: not yet marked done: ...` naming whichever of `local.txt` / `proof.txt` hasn't been ticked
  with `markproof`/`proofshot` yet. Not a hard stop - it's a nudge to catch a missing proof screenshot
  while you still have access to the box, not after submitting.

### Changed

- `pivot` and `proofshot` commands are left out of the report's command log (their timeline notes
  already say the same thing). `addexploit` is **not** left out: it's the only place the "what you
  changed" text appears in full, alongside the `SOURCES.md` entry.

## 1.2.0

### Added

- **`markproof local|proof [value]`.** Ticks `local.txt` / `proof.txt` in the Proof checklist of
  `notes/notes.md` (`user` and `root` work as aliases), optionally storing the flag value on the line,
  and writes a timeline note. `markproof -u local` unticks it (the stored value stays). `mkbox -l` and
  `boxinfo` already read that checklist, so they now reflect it.
- **`$LHOST`.** Your own VPN address (`tun0`, else `tap0`) is detected when the box shell starts, refreshed
  at every prompt (so it follows a VPN reconnect), shown in the banner and `boxinfo`, and used for the
  `serve` client hints when no `--bind` is given.
- **The report fills itself in where it can.** The top of the report now has the attacker address,
  open TCP/UDP ports (from `box.env`), nmap's service info line, and whether `local.txt` / `proof.txt`
  are captured (with the value you stored). A new **Open ports (from nmap)** table (port, protocol,
  service, version) is built from the newest `services` / `allports` / `udp` scans.

### Changed

- `markproof` commands are left out of the report's command log (the timeline note covers them).

## 1.1.0

### Added

- **`serve --smb` / `serve --webdav`.** `serve` can now share `transfer/` over SMB (impacket's
  `smbserver`, SMB2 on) or WebDAV (WsgiDAV) instead of the default Python HTTP server. New options:
  `--share NAME` and `--auth user:pass` (SMB). Default ports: 445 for SMB, 80 otherwise.
- **Scratchpad.** `pad` inside the box shell (and `mkbox -p <box|-g>` outside it) keeps free-form
  notes and commands in `<box>/scratchpad.md`, or one global pad with `-g`. It persists across sessions
  and is kept out of the report and evidence tarball.
- **`serve` timeline notes.** Start and end notes in `notes/timeline.md` (mode, port, bind, share,
  user - never the password; the end note is written after Ctrl-C too).
- **`serve` client hints.** Prints ready-to-paste download/upload commands for the target when a
  server starts (uses `--bind`, else your `tun0` address).
- **`serve --auth` is masked in reports**, like `sshpass -p`.
- **`Happy Hacking :)`** when a new box is created.
- **Connection transcripts in the report.** What you type and see inside an `ssh`, `ftp`, `smbclient`,
  `nc`, ... session is now included in the report's Timeline at the connection's start time, labelled
  with the tool, end time and exit code (long ones are shortened; `MKBOX_TRANSCRIPT_LINES`). The wrappers
  print a one-line marker to the terminal at start and end, which the report uses to find the transcript.
  Transcripts are not password-masked. See the README.

## 1.0.2

- Added timeline generation when `report` is ran so total timeline is established.
- Improved reliability of proofcmd outputted commands.

## 1.0.1

### Fixed

- **The secrets warning could still fire for `addcred` alone, on a narrow terminal.** On a narrow
  window, readline redraws a wrapped `addcred user:pass ...` line across more than one screen row;
  `clean_log`'s line-based model can't follow that redraw (documented limitation), so the cleaned
  session log could end up missing a leading piece of the word "addcred" - just enough that
  `warn_secrets` no longer recognized the line as the one you typed, and warned about your own
  `addcred` command. `warn_secrets` now also recognizes a credential preceded by a trailing
  fragment of "addcred" ("ddcred", "d", ...), which is what that wrap actually leaves behind.

## 1.0.0

First tagged release.

### Fixed

- **Scan output is really handed back to you.** `portscan`, `udpscan` and `svcscan` run `nmap` under
  `sudo`, which leaves the output files root-owned. The old fix-up only worked when the whole shell
  was a root shell; for a regular user (stock Kali) it did nothing. It now uses `sudo -n chown`.
- **`ssh -p 2222` is no longer logged as `ssh -p ***`.** Password masking is now per tool: `-p` is only
  treated as a password for `sshpass`, `rdesktop`, `ncftp` and `evil-winrm`.
- **More password forms are masked** in the report's command log and the live timeline notes:
  `mysql -pPASS`, `xfreerdp /p: /pth: /gp:`, `smbclient -U user%pass`, `evil-winrm -H`, `lftp -u user,pass`,
  `ncat --proxy-auth`, quoted values (`-p 'two words'`), and an optional leading `sudo`. Both places
  now share one implementation, so they cannot disagree.
- **The secrets warning no longer fires every time you use `addcred`.** The typed `addcred user:pass`
  line is always in the session log, so it is ignored; a warning now means the password turned up
  somewhere else.
- **`chrono_log` read `$dir` before it was assigned** (it only worked because the caller had a variable
  with the same name). Fixed.
- `PROMPT_COMMAND` handling now works on bash older than 5.1 (per-box history flushing and multi-tab
  sync would otherwise silently stop).
- `boxcd` no longer carries on after a failed `cd`.
- A missing `script` binary is now reported instead of falling through.

### Added

- `mkbox -V` / `--version`.
- Clear messages for a new box versus re-entering an existing one, so a typo like `mkbox lmae` says it is
  creating something new (and hints at `setip` when no target IP was given).
- Private by default: box directories created by mkbox are mode 700; raw logs, the cleaned log, the
  report draft and the evidence tarball are mode 600.
- A bash version check (4.4+).
- `tests/smoke.sh` and a GitHub Actions workflow running `shellcheck` and the smoke test.

### Documentation

- Clarified that a leading space keeps a command out of shell history but not out of the session log.
- Documented exactly which password forms are masked, and what is not.
- The evidence tarball's session log includes the `addcred` lines as typed; the report now says so.
