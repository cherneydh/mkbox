# Changelog

## 1.4.7

The first production release.

### Added

- **`reporttext` / `mkbox --text`: write the report sections only you can write.** The High-Level
  Summary, Recommendations and Methodology can't come from session notes, so `assemble` used to leave
  `TODO` stubs in the report and hand-edits to `report.md` were lost on the next rebuild. These now live
  in `report-parts/` next to the assembled report (`summary.md`, `recommendations.md`,
  `methodology.md`): `reporttext summary` opens a file with a short guidance comment already in it,
  `assemble` pulls the text in (never overwriting it), and every `assemble` ends with a checklist of the
  sections still unwritten, each with the command to fix it. With no argument, `reporttext` shows which
  are done. Aliases: `recs`, `method`.

### Fixed

- **`--pdf` failed with a relative output path.** `mkbox -a report.md --pdf ...` fell back to "ODT only,
  finish by hand" because LibreOffice rejects relative paths as URLs ("Unsupported URL"). The in-shell
  `assemble` always passed an absolute path, so it never showed; the PDF helper now makes both paths
  absolute itself.

### Internal

- `VERSION` is 1.4.7. tests/smoke.sh: 13 new checks for the above (274/274 passing; the new `--pdf` relative-path check only runs where LibreOffice and its `uno` module are installed); one existing check
  updated for the stub's capitalised wording.

## 1.4.6

Install and presentation pass: a fix for an install path that silently broke `--odt`/`--pdf`, a proper
installer, and a more professional default report template.

### Fixed

- **The documented install copied only the `mkbox` script.** mkbox looks for its bundled template
  (`templates/mkbox-default.odt`) and its PDF page-number helper (`lib/mkbox-update-toc.py`) next to the
  real location of the script, so a bare `sudo install mkbox /usr/local/bin/` left `--odt` failing with
  "needs a template" and `--pdf` unable to compute a table of contents. The README now points at the new
  installer and says why a bare copy isn't enough.
- shellcheck warnings: `local -n` name reuse across two functions (SC2178), and an unbraced
  `$ip[[:space:]]` in the box-shell rc (SC1087).

### Added

- **`install.sh`**: installs the script, `lib/` and `templates/` together under `<prefix>/share/mkbox/`
  with a `<prefix>/bin/mkbox` symlink (`--prefix`, `--uninstall`, and `--check` to only report
  dependencies). It verifies the installed tree is complete, then lists any missing dependencies with the
  matching `apt` command.

- **`mkbox --doctor`** (`-d`): reports required and optional dependencies, whether the install is
  complete (bundled template and PDF helper found next to the script), and the `apt` command for what's
  missing. Exits nonzero only if something required is absent. `install.sh --check` now just runs it.
- **`--title="Text"`** (and `$MKBOX_TITLE`) for `mkbox -a` / `assemble`: sets the report title on the
  ODT/PDF cover page and the Markdown draft's heading line, for anything other than the default
  "OSCP Exam Report". Same precedence as `--author`/`--osid`: the flag wins over the environment variable.

### Changed

- **Refreshed default ODT template.** Arial 10.5pt body; upright navy headings (level 1 ruled);
  shaded, ruled tables; code blocks as a shaded panel with an accent bar; a left-aligned cover page
  (title, OSID, author, date); styled table-of-contents entries; and a "Page X of Y" footer with a
  hairline rule.

### Internal

- tests/smoke.sh: the in-shell `assemble` `--odt`/`--pdf` checks now skip when pandoc is missing; the
  outline-numbering check no longer depends on how pandoc lays out `styles.xml`; the `$TARGET`/`$LOCAL`
  test now passes those variables to the box shell unexpanded. New checks cover `install.sh`.
- CI installs pandoc, lints `install.sh`, and runs the suite against both the distro's pandoc and the
  latest upstream release (the latter is allowed to fail, as an early warning rather than a gate).
- `.gitattributes` pins LF line endings and marks the template `.odt` as binary.
- tests/smoke.sh: 14 new checks (installer, `--title`, `--doctor`); 260/260 passing.

## 1.4.5

A second UX audit pass, this time driven by specific ideas rather than a general review: remembering
and retyping IPs by hand, a typo quietly forking your notes into a second box, a recorded credential
that's still a copy-paste away from being useful, no quick way to get a target's hostname into
`/etc/hosts`, and no way to put your OSID on the cover page without hand-editing the draft.

### Added

- **`$TARGET` / `$LOCAL`**: friendlier aliases for `$IP` / `$LHOST`, usable straight in a command
  (`nmap -p- $TARGET`, a payload callback to `$LOCAL`) without retyping or remembering the actual
  address. Both track their counterpart automatically - through `setip`, a VPN reconnect, and across
  tabs - so there's never a stale one sitting around; `boxinfo` and the shell's startup banner both
  advertise them.
- **A "did you mean?" check on new box names.** A typo like `mkbox dc01` when you meant `dc-01`
  used to just quietly start a second, empty box - and whatever you did from there forked into the
  wrong directory until you noticed two box dirs side by side. Creating a box whose name is a close
  (edit-distance <=2) match to an existing sibling now names that existing box right in the same
  message. This never blocks - the typo'd name still gets created either way - it just makes the
  mistake visible before real work goes into the wrong place.
- **`creds [N]`**: lists what `addcred` has recorded, and `creds N` prints ready-to-paste
  `smbclient`/`crackmapexec`/`evil-winrm`/`xfreerdp`/`sshpass`/`ftp` commands for that credential
  against `$TARGET` - the same copy-paste gap `proofshot` already closed for flag text, now closed
  for passwords too.
- **`sethost domain [domain2 ...] [--ip=x.x.x.x]`**: adds an `/etc/hosts` line for an AD box that
  only answers to its hostname, defaulting the IP to `$TARGET`. Idempotent (re-adding the same
  mapping is a no-op), and never silently overwrites a conflicting existing entry - it prints the
  existing line and leaves it alone instead of guessing which one you actually want.
- **`mkbox -a --osid=OS12345`** (and `assemble --osid=...`, same flag): puts your OSID on the ODT/PDF
  cover page, right under the title - OffSec expects it somewhere in the report, and this is one
  fewer thing to add by hand after the fact. Optional, independent of `--author`, and also settable
  once via `$MKBOX_OSID` the same way `--author`/`$MKBOX_AUTHOR` already work.

### Internal

- `sethost` writes through an overridable `MKBOX_HOSTS_FILE` (defaulting to the real `/etc/hosts`) so
  it can be exercised in tests without ever touching the machine the test suite runs on.
- tests/smoke.sh: 25 new checks covering all of the above (245/245 passing).

## 1.4.4

A direct UX pass, prompted by a specific complaint: v1.4.3 made `mkbox -a` more capable (`--pdf`,
readiness checks) but doing any of it still meant leaving every box's shell, retyping every box
name by hand, and retyping the same flags every time you wanted an updated draft. That's exactly
the kind of friction that gets a feature used less often, so the report ends up thinner than it
should be. Fixed directly, not with a wizard or extra prompts (an exam machine is the wrong place
for anything that can block waiting on input you forgot you'd need to supply):

### Added

- **`assemble`**, run from inside *any* box's own shell: rebuilds the whole report - `report.md`,
  and `.odt`/`.pdf` too if you want them - from every box sitting next to this one, with no outfile,
  no box list, and (after the first time) no flags to type. It finds sibling boxes the same way
  `mkbox -l` already does (a `box.env` in each sibling directory), writes the result next to the
  boxes rather than inside whichever one you happened to be in, defaults to `--pdf` when you've
  never told it otherwise (the most complete thing it can hand you, and it degrades gracefully on
  its own exactly like `--pdf` always has if LibreOffice isn't there), and remembers whatever flags
  you *do* give it (in a small `.mkbox-assemble.conf` next to the boxes) so a later bare `assemble`
  repeats them rather than reverting to that default.
- **`boxes`**, also run from inside any box's shell: the same box list `mkbox -l` prints, without
  leaving the shell first to go check what else is in play.

### Internal

- tests/smoke.sh: 9 new checks driving these two exactly as a student would - from inside a piped
  interactive box shell, by name alone (220/220 passing).

## 1.4.3

Three follow-ups: an `--odt` assembled draft's screenshots were silently broken, a submission could
go out missing proof or findings with nothing saying so, a direct PDF was still a manual LibreOffice
step away, and the `shot`/`proofshot` workflow read as more disjointed than it needs to be.

### Added

- **`mkbox -a --pdf`**: exports a PDF straight from the assembled draft, with the Table of Contents
  already updated and real page numbers computed - the step `--odt` alone still left for you to do
  by hand (Tools > Update All) in LibreOffice. Implies `--odt`; both files are written. Does this by
  driving a throwaway, invisible LibreOffice instance over its UNO scripting interface (its own
  `-env:UserInstallation` profile and a random port, so it never collides with an instance you
  already have open), opening the ODT, calling `update()` on every index, resaving, then exporting
  `writer_pdf_Export`. If `soffice` or a uno-capable `python3` aren't available (or LibreOffice
  doesn't come up), `--pdf` degrades to exactly what `--odt` alone already did - the ODT is still
  written, and mkbox tells you to finish it by hand - rather than failing the whole assemble.
- **A pre-submission readiness check** in `mkbox -a`'s own output: for each box with zero recorded
  screenshots and/or zero `addvuln` findings, an informational (not `WARNING:`) line naming the box
  and what's missing. This is separate from the existing warnings carried over from each box's own
  `mkbox -r` (unfilled `addvuln` text, unticked proof, leaked passwords) - it's specifically about
  what a grader expects to see for every target in the report at all, and it's fine for it to fire on
  a box you're still mid-testing.
- **Screenshots embedded in an assembled multi-box draft now actually resolve.** A box's own
  `report.md` references its screenshots with a path relative to where that file lives
  (`../screenshots/foo.png`) - correct for `mkbox -r`, but broken once that content is copied into an
  assembled draft living in an entirely different directory. `mkbox -a` now rewrites those references
  to each box's absolute `screenshots/` path before the content goes into the draft, so the images
  that were already embedding fine in a per-box report now also embed fine in `--odt`/`--pdf`.

### Changed

- **The `shot`/`proofshot` workflow is now spelled out where you'd actually look for it.** The
  `[flag text]` argument to `proofshot`/`markproof` was already optional - the checklist ticks and
  the screenshot is still saved with nothing more than `proofshot local|proof` - but nothing said so
  anywhere, so the natural-feeling but unnecessary path was to copy the flag out of the target's
  output and paste it in as an argument on every call. `proofshot`'s and `markproof`'s own usage
  text, `proofcmd`'s output, and the box shell's startup banner now all say plainly that the text
  argument is only for the write-up and the screenshot alone is the proof, and `proofcmd` now ends
  with the exact next command to run once the flag's on screen.

### Internal

- `_assemble_readiness_checks` originally ended with two bare `[[ cond ]] && action` statements - a
  classic `set -e` trap: when `cond` is false (the common case), that statement's own exit status is
  nonzero, and since nothing here is testing it (unlike an `if`/`while` condition), `set -e` aborted
  the entire `mkbox -a` run silently, with no error message, the moment any assembled box had at
  least one finding or one screenshot. Rewritten as plain `if`/`fi`.
- tests/smoke.sh: 22 new checks covering the readiness check, the screenshot-path rewrite, `--pdf`
  (both a real export when this machine has `soffice`+`uno`, and graceful degradation when it
  doesn't), and the proofshot/proofcmd/banner wording (211/211 passing).

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
