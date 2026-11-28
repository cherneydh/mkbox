# mkbox

A small bash utility for organizing and documenting penetration-testing practice boxes (built with the OSCP workflow in mind). It creates a consistent per-box workspace in the **current directory**, drops you into a logged shell inside it, and turns your notes, commands and evidence into a report draft.

`mkbox` is a **note-taking and file-organization tool**. It does not exploit, scan, or attack anything on its own. See [What it does and doesn't do](#what-it-does-and-doesnt-do).

## Contents

- [Install](#install)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Box layout](#box-layout)
- [The box shell](#the-box-shell)
- [Shared state and multiple tabs](#shared-state-and-multiple-tabs)
- [Helpers](#helpers)
  - [Credentials (creds)](#credentials-creds)
  - [Hostnames (sethost)](#hostnames-sethost)
- [Logging connections (ssh, ftp, rdp, ...)](#logging-connections-ssh-ftp-rdp-)
- [Logs](#logs)
- [Reporting](#reporting)
- [Findings (addvuln)](#findings-addvuln)
- [Active Directory sets and assembling the final report](#active-directory-sets-and-assembling-the-final-report)
  - [Assembling without leaving the box](#assembling-without-leaving-the-box)
  - [Writing the sections only you can write](#writing-the-sections-only-you-can-write)
- [What it does and doesn't do](#what-it-does-and-doesnt-do)
- [Caveats](#caveats)
- [Development](#development)

## Install

```
git clone https://github.com/cherneydh/mkbox && cd mkbox
chmod +x install.sh && ./install.sh     # sudo ./install.sh for system-wide; ./install.sh --check (or `mkbox --doctor` any time later) reports dependencies
```

(The `chmod +x` is only needed if your checkout dropped the executable bit, e.g. a zip download; `bash install.sh` works the same. The installer itself sets the right modes on everything it installs.)

`install.sh` puts the whole tree in `<prefix>/share/mkbox/` (the script, `lib/`, and `templates/`) and symlinks `<prefix>/bin/mkbox` to it. The prefix is `/usr/local` when you can write there (or run it with `sudo`), otherwise `~/.local` (make sure `~/.local/bin` is on your `PATH`); pass `--prefix DIR` to choose another. It checks that the installed copy is complete, then lists any missing dependencies along with the `apt` command that fixes them. `./install.sh --uninstall` removes it again.

**Don't just copy the `mkbox` file onto your `PATH`.** The script locates `templates/mkbox-default.odt` (the default `--odt` template) and `lib/mkbox-update-toc.py` (the page-number step behind `--pdf`) relative to where it really lives, so a bare copy works for everything *except* `--odt`/`--pdf`, which will tell you the template is missing. Running straight from a checkout (`./mkbox ...`) or through a symlink to it is fine, since both resolve back to the full tree.

Requirements - everything below is on a stock Kali install except where noted:

- **Required:** `bash` 4.4 or newer (developed and tested on 5.2, which is what current Kali ships), `script` (util-linux), `tar`, `find`, and GNU `date`, `sed`, `awk`, `grep`
- `perl` for log cleanup (without it, cleanup falls back to a cruder `sed` version)
- `nmap` for `portscan`, `udpscan` and `svcscan`
- `xclip` (X11) or `wl-clipboard` (Wayland) for `shot`
- `pandoc` for `assemble --odt` (and `--pdf`, which builds on it)
- `libreoffice-writer` (`soffice`) plus the `uno` Python module (`python3-uno`) for `assemble --pdf`; without them `--pdf` falls back to the `.odt` and tells you how to finish by hand
- `p7zip-full` (`7z`) for `assemble --submit`, which packages the PDF the way OffSec's upload wants it

On Debian/Kali: `sudo apt install nmap xclip pandoc libreoffice-writer python3-uno p7zip-full`

## Quick start

A whole box, start to finish. Everything below `mkbox lame ...` is typed inside the box shell it opens; each helper is covered in detail further down.

```
cd ~/oscp/htb
mkbox lame 10.10.10.3         # create ./lame, enter it, start logging (re-run it in other tabs: all share state)

# --- recon
portscan                      # all-TCP-ports nmap sweep, saved to nmap/ (sets $PORTS)
svcscan                       # default scripts + versions on the open ports
udpscan                       # top-20 UDP ports (slow; try a second tab)
sethost lame.htb              # box only answers to a hostname? adds the /etc/hosts line

# --- while you work
note "anonymous FTP allowed"  # timestamped timeline entry
pad                           # scratchpad: free-form notes/commands, never part of the report
serve                         # serve transfer/ over HTTP (or --smb / --webdav), prints the client commands
addexploit 50064.py https://www.exploit-db.com/exploits/50064 "changed LHOST"   # file in exploits/, with its source
markchanges 50064.py          # preview it, then mark what you changed; the report prints the code with those lines highlighted
addcred bob:hunter2 "ssh"     # record a credential (creds N prints ready-to-paste commands for it)

# --- evidence
shot "anonymous FTP login"    # save the image on your clipboard as a captioned screenshot
addvuln initial "vsftpd 2.3.4 backdoor" critical    # a finding for the report (initial | privesc | post)
proofcmd                      # proof one-liners to paste on the target
proofshot local               # screenshot + tick local.txt in the proof checklist, in one step
pivot DC01 "psexec with bob"  # Active Directory: log a lateral move (shown as a chain in the report)
exit                          # leave; the session log is cleaned automatically

mkbox -r lame                 # build this box's report draft + evidence tarball
```

**Several boxes, one report.** Mark Active Directory machines (`mkbox dc01 10.10.10.5 --ad`, or `setad on` inside a box), then from inside any box's shell:

```
boxes                         # every box next to this one, with target IP and proof status
reporttext                    # the three sections only you can write; which are done, which are TODO
reporttext summary            # opens it in $EDITOR (also: recommendations, methodology)
assemble                      # rebuild the WHOLE report (report.md/.odt/.pdf) from every box; lists what's missing
assemble --final              # the submit-it export: refuses while a section, finding or modified exploit is unfinished
assemble --submit --osid=OS-12345   # same checks, then names the files OffSec's way, builds the .7z and prints its MD5
```

Or in one go from a plain terminal: `mkbox -a report.md --final --author="Jane Q. Tester" --osid=OS-12345 lame dc01 dc02`. Run `mkbox --doctor` any time to check what's installed.

## Commands

```
mkbox [-n|--no-shell] <boxname|path> [target-ip] [--ad]
mkbox -c|--clean  <boxname|path>
mkbox -r|--report [--creds] <boxname|path>
mkbox -p|--pad <boxname|path|-g> [edit|add TEXT|cmd CMD|show|grep PATTERN|path]
mkbox -l|--list
mkbox -a|--assemble <outfile.md> [--odt[=template.odt]|--pdf] [--author="Name"] [--osid=OS-12345] [--title="Text"] [--final|--submit] [--creds] <box1> [box2 ...]
mkbox -t|--text [summary|recommendations|methodology|status]
mkbox -d|--doctor
mkbox -V|--version
```

| Command                    | What it does                                                                     |
| -------------------------- | -------------------------------------------------------------------------------- |
| `mkbox lame 10.10.10.3`    | Creates `./lame`, enters it, starts logging                                      |
| `mkbox lame`               | Re-enters an existing box as a new session (safe to run in several tabs at once) |
| `mkbox .`                  | Uses the current directory as the box                                            |
| `mkbox ~/labs/pg/foo`      | Any path works; the last component is the box name                               |
| `mkbox -n lame 10.10.10.3` | Creates the box without starting a shell                                         |
| `mkbox dc01 10.10.10.5 --ad` | Creates the box already flagged as part of an Active Directory set (see [below](#active-directory-sets-and-assembling-the-final-report)) |
| `mkbox -c lame`            | Rebuilds the cleaned log from the raw session logs                               |
| `mkbox -r lame`            | Builds a report draft and evidence tarball                                       |
| `mkbox -r --creds lame`    | Same, but includes recorded credentials                                          |
| `mkbox -p lame`            | Opens the box's scratchpad in `$EDITOR` (see [Scratchpad](#scratchpad))          |
| `mkbox -l`                 | Lists boxes in the current directory with target IP and proof status             |
| `mkbox -a draft.md lame dc01 dc02` | Collates several boxes' own reports into one document draft - see [below](#active-directory-sets-and-assembling-the-final-report) |
| `mkbox -t [section]`       | Writes the report sections only you can (summary, recommendations, methodology) - see [below](#writing-the-sections-only-you-can-write) |
| `mkbox -d`                 | Doctor: checks dependencies and that the install is complete (template, PDF helper) |
| `mkbox -V`                 | Prints the version                                                               |

If the box doesn't exist yet, `mkbox` creates it and says so (`creating new box 'lame' in ...`, followed by a `Happy Hacking :)`); if it does, it says `re-entering 'lame'`. So a typo like `mkbox lmae` announces that it is making a new box instead of quietly doing it - and if that typo'd name is suspiciously close to a box that already exists next to it (`dc01` vs. `dc-01`, `smok` vs. `smoke`), mkbox names the existing box it's close to, right there in the same message. It still creates `lmae` either way - this never blocks you, it just makes the mistake visible before you've put real recon, screenshots or findings into the wrong directory by accident.

Flags and the box name/IP can be given in any order (`mkbox lame -n 10.10.10.3` works the same as `mkbox -n lame 10.10.10.3`); only the first two non-flag arguments are used, as box name and then IP.

The box is always created relative to where you run the command, so you can organize things however you like (`~/oscp/htb/`, `~/oscp/pg/`, and so on).

Box names must start with a letter or digit and contain only letters, digits, `.`, `_`, `-`.

The target must be an IP or hostname made of letters, digits, `.`, `:` and `-`, and it cannot start with `-`. (That keeps a value like `-sV` from ever being passed to nmap as an option.)

If you re-enter a box with a different IP (`mkbox lame 10.10.10.9`), the IP stored in `box.env` is updated. Inside the shell, prefer `setip`, which also updates the notes header and logs the change to the timeline.

## Box layout

```
lame/
├── nmap/                   scan output (older results are kept, see "Recon wrappers")
├── web/                    web enumeration output
├── loot/                   files pulled from the target
├── exploits/               exploit code and modifications
├── creds/                  credentials and hashes (creds.txt is mode 600)
├── notes/
│   ├── notes.md            template: ports, foothold, privesc, creds, proof, lessons learned
│   └── timeline.md         timestamped entries from `note` and the helpers
├── screenshots/            saved by `shot`; captions.tsv holds timestamp + note per image
├── scratchpad.md           free-form notes/commands, never part of the report (see "Scratchpad")
├── transfer/               files to serve to the target
├── report/                 generated by `mkbox -r`
├── box.env                 shared state: IP, PORTS, UDP_PORTS (read by every tab)
├── session-lame.log        cleaned session log (readable)
├── .sessions/              raw `script` output, one file per mkbox invocation
├── .bash_history_lame      per-box history with timestamps
├── .box.rc                 shell setup (regenerated each run)
└── .gitignore              contains just "*" (created once, see Caveats)
```

`notes/notes.md` is created once and never overwritten.

**Permissions.** When `mkbox` creates a box directory it makes it mode 700, and the raw logs, the cleaned log, the report draft and the evidence tarball are mode 600, because they hold everything you typed. A directory that already exists (including `mkbox .`) keeps whatever permissions you gave it.

## The box shell

Entering a box starts a `bash` session (even if your login shell is zsh) with:

- `script` logging everything to a raw log for this session, flushed after every write so a crash doesn't lose it
- `HISTTIMEFORMAT="%F %T "` so `history` shows dates and times
- a per-box history file, written after every command (not just on exit)
- `$IP`, `$PORTS` and `$UDP_PORTS` kept in sync across tabs (see below), plus `$BOX` and `$BOX_DIR`
- `$LHOST`, your own VPN address (`tun0`, else `tap0`; empty if neither exists). It is looked up again at every prompt, so it follows a VPN reconnect, and it is what the `serve` client hints use when you don't pass `--bind`
- `$TARGET` and `$LOCAL` - friendlier aliases for `$IP` and `$LHOST`, for typing straight into a command (`nmap -p- $TARGET`, `nc -lvnp 4444` while telling a payload to callback `$LOCAL`) without having to remember or retype the actual address. Both track their counterpart automatically, including through `setip` and across tabs, so there's never a stale one lying around
- a `[box:name]` prefix in your prompt
- a leading space on a command keeps it out of history (`HISTCONTROL=ignorespace`). That is the shell history only: `script` still records the command and its output in the session log, so a leading space does not keep a command out of the log or the evidence tarball

Type `exit` to leave. You return to the directory you started in.

## Shared state and multiple tabs

Open `mkbox lame` in as many terminal tabs as you like. Each tab gets its own raw log, so they never overwrite or scramble each other, and each shows up as its own labeled section in `session-lame.log` (ordered by start time, not interleaved).

Shared between tabs:

- **`$IP`, `$PORTS`, `$UDP_PORTS`.** They live in `box.env`, and every tab checks that file's modification time before each prompt and only re-reads it when it has actually changed. Run `setip` after a machine revert, or `portscan` / `udpscan` in one tab, and the other tabs pick up the new values at their next prompt. `box.env` is written atomically (temp file and rename), so a tab never reads a half-written file.
- the timestamped history file (written after every command)
- `notes/timeline.md`, `screenshots/`, and everything else in the box folder

Not shared: output. Each tab's terminal output goes to that tab's own log.

**Manual edits now stick (until something else writes `box.env`).** Typing `IP=10.10.10.50` by hand is no longer reverted at the next prompt, because the sync only re-sources `box.env` when its mtime changes. It's still better to use `setip`, because that also updates the notes header and the timeline - a hand-set `$IP` only changes the variable. And the next `portscan` / `udpscan` in that tab will happily save your hand-set `$IP` back into `box.env` (sharing it with other tabs), since mkbox has no way to tell a manual edit from an intentional one. For other hosts (pivoting, the AD set), use your own variable names such as `$DC` or `$T2` so they never collide with `box.env` at all - and run `pivot <to-host> <via> [note]` each time you move to a new one (`pivot DC01 "psexec with bob:ntlm-hash"`), so the chain shows up as its own section at the top of the report instead of only as scattered notes in the timeline.

On `exit`, mkbox shows a progress bar while it rebuilds the cleaned log (Ctrl-C is ignored until it finishes; set `MKBOX_QUIET=1` to hide the bar). If a session ends abnormally (terminal closed, SSH dropped), cleanup doesn't run. Run `mkbox -c <boxname>` to rebuild the cleaned log.

## Helpers

Available inside the box shell:

| Helper                      | What it does                                                                                                      |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `note "text"`               | Appends a timestamped line to `notes/timeline.md`                                                                 |
| `shot "note"`               | Saves the image on your clipboard to `screenshots/` with a timestamp and note, and logs it to the timeline        |
| `proofshot local\|proof [value]` | `shot` + `markproof` in one step: saves the clipboard image as proof and ticks the checklist, so you can't take the shot and forget to tick it. `[value]` is optional - just text for the write-up. `user` / `root` are aliases, same as `markproof` |
| `boxinfo`                   | Shows target, ports, file counts, proof checklist, recent timeline                                                |
| `boxcd [subdir]`            | `cd` to the box directory or a subfolder (`boxcd nmap`)                                                           |
| `setip <ip>`                | Changes the target IP (after a machine revert); validates it, updates `box.env`, `$TARGET` and the notes header   |
| `sethost domain [domain2 ...] [--ip=x.x.x.x]` | Adds `<ip> domain [domain2 ...]` to `/etc/hosts` (ip defaults to `$TARGET`) for an AD box that only answers to its hostname; idempotent, and never overwrites a conflicting existing entry - see [Hostnames (`sethost`)](#hostnames-sethost) |
| `portscan`                  | Runs `nmap -p- --min-rate 2000 -T4` into `nmap/allports.*`, sets `$PORTS`                                         |
| `udpscan [N]`               | Runs `nmap -sU -sV --top-ports N --open` (default 20) into `nmap/udp.*`, sets `$UDP_PORTS`                        |
| `svcscan [ports]`           | Runs `nmap -sC -sV -p <ports>` into `nmap/services.*` (defaults to `$PORTS`; accepts numbers and ranges)          |
| `serve [--smb\|--webdav] [--bind ip] [port]` | Serves `transfer/`: `python3 -m http.server` by default, `--smb` for an SMB share, `--webdav` for WebDAV - see [Serving files](#serving-files) |
| `pivot <to-host> <via> [note]` | Records a lateral-movement hop in the timeline (`pivot DC01 "psexec with bob:ntlm-hash"`); the report pulls every hop into a standalone **Pivot chain** section - see [Reporting](#reporting) |
| `pad [-g] [edit\|add\|cmd\|show\|grep\|path]` | Scratchpad for notes and commands that don't belong in the report - see [Scratchpad](#scratchpad) |
| `ssh`, `ftp`, `sftp`, `smbclient`, `rdesktop`, `xfreerdp`, `nc`, `telnet`, `mysql`, ... | Logged automatically on connect/disconnect - see [Logging connections](#logging-connections-ssh-ftp-rdp-) |
| `addcred user:pass [where]` | Appends to `creds/creds.txt`; the timeline records only the username                                              |
| `creds [N]`                 | Lists recorded creds with an index; `creds N` prints ready-to-paste `smbclient`/`crackmapexec`/`evil-winrm`/`xfreerdp`/`sshpass`/`ftp` commands for that one, against `$TARGET` - see [Credentials (`creds`)](#credentials-creds) |
| `markchanges <file>` | Previews a file in `exploits/`, then opens it in `$EDITOR` so you can wrap the regions you changed in `mkbox:change` / `mkbox:end` comment lines; the report prints the whole file and highlights those regions - see [Exploit provenance](#exploit-provenance) |
| `addexploit <file> <source-url> [what changed]` | Records where a file in `exploits/` came from and what you modified, in `exploits/SOURCES.md`; the report shows this ahead of the plain file list - see [Reporting](#reporting) |
| `addvuln initial\|privesc\|post <title> <critical\|high\|medium\|low>` | Opens a templated finding in `$EDITOR` (Explanation/Fix) and files it under `vulns/`, in place of an ad-hoc `note "found this: <link>"` - see [Findings](#findings-addvuln) |
| `setad on\|off`              | Flags (or unflags) the current box as part of an Active Directory set, same as creating it with `--ad` - see [Active Directory sets](#active-directory-sets-and-assembling-the-final-report) |
| `proofcmd`                  | Prints one-liners to paste on a target to show proof file, user, hostname, and IP                                 |
| `markproof local\|proof [value]` | Ticks `local.txt` / `proof.txt` in the Proof checklist of `notes/notes.md`, stores the optional value on that line, adds a timeline note. `user` / `root` are aliases; `markproof -u local` unticks (value kept) |
| `cleanlog`                  | Rebuilds the cleaned session log mid-session                                                                      |
| `report [--creds]`          | Same as `mkbox -r` for the current box                                                                            |
| `boxes`                     | Lists every box next to this one (same table as `mkbox -l`) - check what else is in play without leaving this shell |
| `reporttext [summary\|recommendations\|methodology\|status]` | Opens the High-Level Summary / Recommendations / Methodology text in `$EDITOR` (no argument: shows which are still unwritten). Saved next to the boxes, so `assemble` pulls it in and never overwrites it - see [below](#writing-the-sections-only-you-can-write) |
| `assemble [mkbox -a flags]` | Rebuilds the *whole* report from every box next to this one, as `report.md`/`.odt`/`.pdf` in their shared parent directory - no need to leave this shell, list every box by name, or retype flags each time; see [Assembling without leaving the box](#assembling-without-leaving-the-box) |

### Credentials (`creds`)

`addcred` is write-only by design - it appends to `creds/creds.txt` and the timeline only ever gets the username. `creds` is how you read it back without opening the file:

```
$ creds
 1) 2026-11-27 02:08:43  administrator:Password123!  (domain admin via kerberoast)
 2) 2026-11-27 02:08:43  svc_sql:Sup3rS3cr3t  (smb share)
Paste-ready commands for one of these, against the box you're in right now: creds <N>

$ creds 1
Cred #1: administrator : Password123!   ($TARGET below resolves to whatever box you run this in)

smb:          smbclient -U 'administrator%Password123!' //$TARGET/C$
crackmapexec: crackmapexec smb $TARGET -u 'administrator' -p 'Password123!'
evil-winrm:   evil-winrm -i $TARGET -u 'administrator' -p 'Password123!'
rdp:          xfreerdp /v:$TARGET /u:'administrator' /p:'Password123!' +clipboard
ssh:          sshpass -p 'Password123!' ssh 'administrator'@$TARGET
ftp:          ftp $TARGET   (then log in as administrator / Password123!)
```

`$TARGET` in that output is printed literally, not substituted - paste the line as-is and your shell fills in whichever box you're actually sitting in, so a credential found on one box still pastes correctly if you reuse it against another (`cd` to that box's shell first, or just change `$TARGET` yourself before running it).

### Hostnames (`sethost`)

Plenty of AD boxes only answer to their hostname (Kerberos, SMB signing, a site that redirects to its own name), so the first real step on most of them is adding an `/etc/hosts` entry by hand. `sethost` does that instead:

```
sethost dc01.corp.local corp.local
```

- **IP defaults to `$TARGET`/`$IP`** - the box you're sitting in - so there's nothing else to type; pass `--ip=x.x.x.x` to target something else instead.
- **Several domains at once**: `sethost dc01.corp.local corp.local DC01` covers the FQDN, the bare domain, and the NetBIOS name in one line.
- **Idempotent.** Running it again with the same mapping is a no-op - it says so and doesn't write a duplicate line.
- **Never silently overwrites a conflicting entry.** If a domain is already in `/etc/hosts` pointing somewhere else (stale from an earlier box, say), `sethost` prints that existing line and leaves it alone rather than guessing which one you actually want; edit it yourself if it's stale.
- Needs `sudo` to write `/etc/hosts` unless you're already root (same `_sudo` helper `portscan`/`udpscan`/`svcscan` use).

### Serving files

`serve` shares `transfer/`. With no flags it is the same Python HTTP server as before (port 80, all interfaces). Flags pick a different backend:

```
serve                                   # http.server on :80
serve --smb                             # SMB share "share" on :445
serve --smb --share loot --auth bob:pw  # named share, with a login (newer Windows refuses guest SMB)
serve --webdav                          # WebDAV on :80 (anonymous, read/write)
serve --bind 10.10.14.2 --webdav 8080   # restrict to one address / pick a port
```

- `--smb` runs impacket's `smbserver` (`sudo apt install python3-impacket`) with SMB2 support on. Default port 445.
- `--webdav` runs WsgiDAV (`sudo apt install wsgidav`) anonymously. It is writable, so a client can upload into `transfer/` too.
- Ports below 1024 use `sudo` unless you are root. `--bind` limits which address listens; without it every interface does, so prefer `--bind <your-vpn-ip>`.
- `--http` is accepted for completeness; it is the default.
- `--auth` is SMB only (WebDAV is anonymous).
- **Client hints.** When the server starts it prints copy-paste commands for the target (`wget`/`certutil`/`iwr` for HTTP, `copy \\ip\share\FILE .` and `net use ...` for SMB, the `DavWWWRoot` path and `curl -T` upload for WebDAV). The address used is your `--bind` value, else your `tun0` address, else the placeholder `<your-ip>`. The `net use` hint shows `<password>`, never the real one.
- **Timeline notes.** Like the connection wrappers, `serve` writes a start and an end note to `notes/timeline.md`, for example `serve: smb started (port 445, share loot, user bob)` and `serve: smb ended (exit 130, 312s)` (130 is Ctrl-C). The password is never written to the note.
- **`--auth` and the report.** The report's command log masks the password (`serve --smb --auth bob:***`), the same way it masks `sshpass -p`. The raw session log and your shell history still have the real command, as with every other command.

### Scratchpad

A scratch file for notes and commands you want to keep handy but that don't belong in the report. It is a separate file from `notes/`, so it is never merged into the report draft or bundled in the evidence tarball, and it lives in the box folder, which is already git-ignored. It persists across sessions and tabs.

```
pad                       # open in $VISUAL/$EDITOR (falls back to nano, vim, vi)
pad add "try the upload form with a .phtml"
pad cmd 'curl -s http://$IP/?page=../../etc/passwd'
pad cmd                   # no argument: saves the previous command you ran
pad show                  # print it
pad grep passwd           # case-insensitive search
pad path                  # print the file location
pad -g ...                # the same, on one global pad shared by every box
```

From outside the box shell: `mkbox -p lame add "text"`, `mkbox -p lame` (opens the editor), `mkbox -p -g show`. `-p` must be the first argument.

The per-box pad is `<box>/scratchpad.md`; the global one is `${XDG_DATA_HOME:-~/.local/share}/mkbox/scratchpad.md`. Both are mode 600, since commands you save may contain passwords.

### Screenshots

Take a screenshot with whatever tool you like, copy it to the clipboard, then run:

```
shot "anonymous FTP login works"
```

This saves the clipboard image as `screenshots/<YYYYmmdd-HHMMSS>-<note-slug>.png`, records the note and time in `screenshots/captions.tsv`, and adds a line to `notes/timeline.md`. `mkbox -r` embeds each screenshot in the report draft with its caption and timestamp, in the order you took them.

- The image is saved exactly as copied. `shot` never edits or annotates it.
- It needs `xclip` on X11 (`sudo apt install xclip`) or `wl-clipboard` on Wayland. The clipboard must contain a PNG; anything else is rejected without saving.
- Over plain SSH there is no desktop clipboard, so `shot` won't work there.

**`proofshot local|proof [value]`** is `shot` + `markproof` in one step, for the two screenshots that matter most. The whole workflow is three steps, and only the last one is typed into mkbox:

1. Run `proofcmd` for a one-liner to paste on the target - it prints `local.txt`/`proof.txt` alongside `whoami`/`hostname`/the IP, so one screenshot covers everything a grader needs to see.
2. Once that's on screen, take the screenshot (so it's on your clipboard) - same as for any other `shot`.
3. Back in mkbox: `proofshot local|proof`.

That's it - `[value]` is **optional**. It's only there to also record the flag text in `notes/notes.md` for your own write-up; the checklist still ticks and the screenshot still saves with nothing more than step 3 above, so there's no need to copy the flag out of the target's output first unless you want it written down:

```
proofshot proof 0a1b2c3d4e5f     # also records the flag text
proofshot proof                  # same result otherwise - ticks the checklist, saves the screenshot
```

Either way this saves the screenshot, labels it, and ticks the Proof checklist in `notes/notes.md`, all at once - the same thing `shot "..."` followed by `markproof proof [value]` would do, just without the chance of doing one and forgetting the other. `markproof -u` still works afterward if you need to untick it.

### Recon wrappers

`portscan`, `udpscan` and `svcscan` are thin wrappers that run `nmap` with the fixed flags shown above, so you can read exactly what they do in the script. They use `sudo` unless you are already root.

- **Re-runs keep your old results.** Before a scan overwrites `nmap/allports.*`, `nmap/udp.*` or `nmap/services.*`, the previous files are renamed with the time of that scan (for example `allports-20261009-160035.nmap`). The report includes all of them, oldest first.
- **UDP is slow.** `udpscan` can take minutes; run it in a second tab. Only ports nmap reports as `open` go into `$UDP_PORTS`. Ports reported as `open|filtered` are printed and noted in the timeline, but not stored; check `nmap/udp.nmap` for them.
- **Output isn't left root-owned.** `nmap -oA` runs under `sudo`, so its output files are written as root; mkbox hands them back to you right after each scan (`sudo chown` as a regular user, which reuses the credentials `sudo` just cached and never prompts, or `chown` to `$SUDO_USER` if your whole shell is a root shell from `sudo -i`), so you don't need `sudo` just to read your own results. If that `chown` can't run, the files simply stay root-owned and world-readable.

## Logging connections (ssh, ftp, rdp, ...)

Connecting out to the target is one of the most report-relevant things you do, so mkbox wraps a set of common remote/transfer commands - `ssh`, `sshpass`, `ftp`, `sftp`, `ncftp`, `lftp`, `smbclient`, `rdesktop`, `xfreerdp`, `remmina`, `nc`, `ncat`, `netcat`, `telnet`, `mysql`, `psql`, `evil-winrm` - and logs each one to `notes/timeline.md` automatically:

```
2026-10-09 18:04:08  ssh: started (-p 2222 bob@10.10.10.9)
2026-10-09 18:04:41  ssh: ended (exit 0, 33s)
```

**This is passthrough, not a new feature to interact with.** Each wrapper runs the real binary directly, in the foreground, with your terminal exactly as it would be without mkbox: interactive password prompts, full-screen programs (`vim` or a shell over `ssh`), `scp`/`sftp` progress bars, Ctrl-C, and the real exit code all behave normally. Nothing is piped, backgrounded, or given its own pty. The one visible addition is a marker line printed to the terminal when the connection starts and ends (`[mkbox >>> ssh started 2026-10-09 18:04:08]` / `[mkbox <<< ssh ended 2026-10-09 18:04:41 exit 0]`, only when stderr is a terminal); the report uses them to find the connection's transcript in the session log. A command is only wrapped if that binary is actually on your `PATH` when the box shell starts, so nothing is ever shadowed by a "command not found."

- **Password masking is best-effort.** The timeline note above and the report's command log use the same masking rules (one shared piece of code), and each tool only gets the rules that fit it. For example `ssh -p 2222` is a port and is left alone, while `sshpass -p` is a password and is masked:

  | Tool | What is masked |
  | ---- | -------------- |
  | every wrapped tool | `--password` / `--pass` (with `=` or a space), and the password in `user:pass@host` URLs |
  | `sshpass`, `rdesktop`, `ncftp`, `evil-winrm` | `-p PASS` (`evil-winrm` also `-H HASH`) |
  | `mysql` | `-pPASS` (attached, the way mysql wants it; a bare `-p` just prompts) |
  | `smbclient` | `-U user%pass`, `--user=user%pass` |
  | `xfreerdp`, `remmina` | `/p:PASS`, `/pth:HASH`, `/gp:PASS` |
  | `lftp` | `-u user,pass` |
  | `ncat` | `--proxy-auth user:pass` |
  | `serve` (the box shell's helper) | `--auth user:PASS` / `--auth=user:PASS` |

  What it does not catch: tools outside the wrapped list (`curl -u`, `hydra`, `impacket-*`, ...), anything after the first command on a line (`a; mysql -pX`, pipes, `&&`), a password spelled some other way, and passwords with spaces that aren't quoted. A password typed at an interactive prompt was never on the command line, so there is nothing to mask. An optional `sudo` in front is ignored. The **raw session log always has the real command** (that's what `script` records), so masking only affects the generated report's command log and the timeline note, never your actual history.
- **`sudo` bypasses the wrapper**, because `sudo` resolves the real binary from `PATH`, not from your shell's functions - `sudo nc ...` is still captured in your history and session log like any other command, just without the start/end timeline note.
- **To run the real binary once without logging it**: `command ssh ...` or `\ssh ...`.
- **To wrap more tools** (or fewer): set `MKBOX_NET_CMDS` to a space-separated list of binary names, either in your shell before running `mkbox`, or in your own `~/.bashrc` (which loads before `.box.rc` and is respected). Setting it in the environment you run `mkbox` from also makes the report's command log mask the generic rules (`--password`, `user:pass@`) for those tools; the tool-specific rules in the table above apply to the tools named there.

## Logs

- `.sessions/<start-time>-<pid>.raw` is the raw `script` output for one `mkbox` invocation, including escape codes. Every invocation gets its own file.
- `session-<boxname>.log` is the readable version. It is rebuilt from all the raw session logs every time you exit, oldest first, with a `===== session <start time> =====` header before each one, so earlier sessions are never lost.

Cleanup behaves like a simple terminal: carriage returns and backspaces move a cursor and later characters **overwrite** earlier ones, `ESC[K` erases to end of line, cursor-move and delete sequences from readline are applied, and colors, window titles and other control codes are dropped. Tab completion, Ctrl-R and history recall therefore come out as the final line you saw. It cannot follow cursor-up redraws of a command that wraps across several screen rows, so very long wrapped lines can still show leftover fragments. Commands and their output are always preserved. Without `perl`, cleanup falls back to a cruder version that strips escapes but doesn't apply overwrites.

## Reporting

`mkbox -r <box>` writes two files into `<box>/report/`:

- `<boxname>-report.md`: a draft assembled from your notes, a chronological log, nmap results, screenshots, exploit and loot filenames, and a credentials section.
**Excluding clutter.** Python virtualenvs (any folder containing `pyvenv.cfg`, whatever its name), `venv`, `.venv`, `node_modules`, `__pycache__`, `*.pyc`, `.git`, `.tox`, `*.egg-info` and `site-packages` are skipped automatically: they stay out of the report's file lists and inlined code and out of the evidence tarball. To skip more, put one glob per line in `<box>/.mkboxignore` (`#` comments allowed; a pattern containing `/`, like `tools/vendor`, matches the path inside the scanned folder, e.g. `exploits/`) or set `MKBOX_EXCLUDE="pat1 pat2"`. The files themselves are never touched.

- `<boxname>-evidence.tar.gz`: `notes/`, `screenshots/`, `nmap/`, `exploits/`, `web/`, the cleaned session log, and the report draft.

### What the report fills in for you

Where the information exists, the top of the report is filled in without you writing anything:

- **Summary lines:** target, your own address (`$LHOST`, or `unknown` when there is no `tun0`/`tap0`), open TCP and UDP ports (from `box.env`), the `Service Info:` line from `nmap/services.nmap` (usually the OS), and whether `local.txt` and `proof.txt` are captured, with the value you gave `markproof`. Run `markproof` (or `proofshot`, below) before `mkbox -r`; the lines read from the checklist in `notes/notes.md`.
- **Open ports (from nmap):** a table of port, protocol, service and version built from the newest scans: `nmap/services.gnmap` (or `nmap/allports.gnmap` if there is no service scan yet) plus `nmap/udp.gnmap`. Only ports nmap reports as `open` are listed. Older, time-stamped scan files are not used for the table (they are still in the **Nmap results** section).
- **Pivot chain:** every `pivot <to-host> <via> [note]` you ran, in order, as its own section right under the ports table - a one-glance view of how an AD set's hosts chain together, since the full timeline further down can bury them among everything else. Left out entirely if you never ran `pivot`.

Nothing is guessed: a line or table with no data behind it is simply left out or reads `not recorded yet` / `none found`. Your own **Notes** section is copied as-is.

### Exploit provenance

OSCP reports expect you to say where a public exploit came from and what you changed to make it work. `addexploit <file-in-exploits/> <source-url> [what you changed]` records that in `exploits/SOURCES.md`:

```
addexploit cve-2021-9999.py https://www.exploit-db.com/exploits/9999 "retargeted offsets for Ubuntu 22.04, fixed the LPORT substitution"
```

`mkbox -r` shows `SOURCES.md`'s entries at the top of the **Exploits / scripts** section, ahead of the plain file list (`SOURCES.md` itself is left out of that list, since its content is already shown above it). If you never run `addexploit`, the section is unchanged from before: just the files in `exploits/`, oldest first.

**Exploit code in the report.** The exam guide wants the *modified* exploit's code in the report with your changes highlighted (an exploit you used as-is is just its URL), and any scripts or PoCs of your own as text. So `mkbox -r` now prints the code of every file in `exploits/` that is:

- recorded by `addexploit` **with** a change note, or carries change markers: printed in full, plus a **Highlighted changes** list of the regions you marked, with line numbers;
- not recorded by `addexploit` at all (your own script): printed in full;
- recorded by `addexploit` **without** a change note: not printed, only listed with its URL. Binary files are never printed, and a file over 5000 lines is replaced by a note to include the relevant part by hand.

To mark your changes, run `markchanges <file>` in the box shell. It shows a numbered preview, then opens the file in `$EDITOR`; wrap each region you changed in two comment lines using the file's own comment syntax:

```
# mkbox:change
LHOST = "10.10.14.5"
LPORT = 4444
# mkbox:end
```

The marker lines are left out of the printed code, and the whole file is printed (not just the marked parts) because the guide asks for the modified code itself. Only what's between the markers is called out as your change, so mark everything you touched. If a modified exploit has no marked changes, or the markers don't pair up, `mkbox -r` warns and `--final` refuses to export.

### The chronological log

The **Timeline** section merges four sources by time:

- **commands** from the box's history file, shown in code blocks with a timestamp
- **notes** from `notes/timeline.md`
- **screenshots** from `screenshots/captions.tsv`, listed with file name and caption (the images themselves are embedded in the **Screenshots** section)
- **connection transcripts** from the session log: for every `ssh`, `ftp`, `smbclient`, `nc`, ... connection, everything that appeared in the terminal between the start and end markers, so the commands you typed on the target and their output are in the report too

Each transcript sits at the connection's start time, under a bold label naming the tool, with when it ended and its exit code:

````
- **2026-10-09 18:04:08** - **[ssh session transcript]** (until 18:04:41, exit 0)

```text
bob@target:~$ id
uid=1000(bob) gid=1000(bob) groups=1000(bob)
```
````

Transcripts have no per-command timestamps (the terminal log has no timing); the connection's start, end and exit code are what is timed. A transcript is the raw terminal text: it includes the remote prompt and any password you typed that the remote side echoed, and, unlike the local command log, it is **not** password-masked. Transcripts longer than 300 lines are cut to the first and last 150 with a `[... N lines omitted ...]` line in between (the full text is always in the session log and the tarball); set `MKBOX_TRANSCRIPT_LINES=N` to change the limit, or `0` to never cut. A connection whose end marker never reached the log (terminal closed mid-session) is labelled `the log ended before the connection did`. `sudo`-prefixed or unwrapped tools have no markers, so no transcript block.

What it leaves out or changes:

- Trivial commands are skipped: `ls`, `ll`, `la`, `cd`, `pwd`, `clear`, `history`, `exit`, `logout`, and the helpers `note`, `shot`, `proofshot`, `pivot`, `boxinfo`, `boxcd`, `cleanlog`, `proofcmd`, `markproof`, `report` - each of these already has its own note, screenshot caption or report section that says the same thing, so the raw command would just be a duplicate.
- `addcred user:pass ...` appears as `addcred user:***`, so the password never reaches the report. `addexploit` is **not** skipped: its command line is the only place the "what you changed" text is shown in full, so it stays in the command log alongside the `SOURCES.md` entry in **Exploits / scripts**.
- A password passed to a wrapped tool (`sshpass -p`, `mysql -pPASS`, `xfreerdp /p:`, `smbclient -U user%pass`, a `user:pass@host` URL, ...) is masked the same way as in the live timeline note - see [Logging connections](#logging-connections-ssh-ftp-rdp-) for the per-tool rules and what they don't catch.
- Commands you start with a space aren't in your history, so they aren't in the log either (they are still in the session log).

If there's no history yet, the section falls back to the raw `timeline.md`. The merge needs GNU `date`. If a timestamp in `notes/timeline.md` or `screenshots/captions.tsv` can't be parsed, `mkbox -r` prints a `WARNING` to stderr and leaves that source out of the merged **Timeline** section for this run rather than silently dropping it - the raw notes/captions themselves are untouched and still go into the evidence tarball.

### What is and isn't included

By default credentials are **not** inlined and `loot/` contents are never bundled (filenames only). Pass `--creds` to include `creds/`.

That only covers those folders. Notes, exploits and the session log are bundled as you typed them, and other passwords you typed into commands not covered by the masking above (a `hydra` line, say, or a tool-specific password flag the [connection wrappers](#logging-connections-ssh-ftp-rdp-) don't recognize) appear in the chronological log. When you run without `--creds`, `mkbox -r` checks every password in `creds/creds.txt` against the files going into the bundle and prints a `WARNING` naming where it found one. The `addcred user:pass` line you typed is always in the session log (that's what the log is for, and `mkbox -r` says so in its output), so lines containing `addcred ` don't trigger the warning: if you see one, the password also turned up somewhere else, such as a note, a command or a pasted file. It can't catch passwords you never recorded with `addcred`.

`mkbox -r` also checks the Proof checklist and prints a `WARNING: not yet marked done: ...` naming whichever of `local.txt` / `proof.txt` `markproof` (or `proofshot`) hasn't ticked yet. It's just a reminder at report time, not a hard stop - run `mkbox -r` again once you've run `markproof`/`proofshot` and the warning clears. The point is to catch a missing proof screenshot while you still have access to the box, not after submitting.

The draft is a starting point: you still write the actual report.

## Findings (`addvuln`)

The OSCP exam report expects each finding written up as a vulnerability explanation, a fix, and a severity - not an ad-hoc `note "found this: <link to exploit>"`. `addvuln` gives you a structured way to capture that as you go, instead of reconstructing it from memory at the end:

```
addvuln initial "Anonymous SMB share leads to WordPress RCE" critical
addvuln privesc "AlwaysInstallElevated" high
addvuln post    "Clear-text creds in a scheduled task" medium
```

The three phases are `initial` (Initial Access), `privesc` (Privilege Escalation), and `post` (Post Exploitation) - the same breakdown the exam report template uses per target. Severity is `critical`, `high`, `medium`, or `low`.

Running `addvuln` opens a small templated file in `$EDITOR` (`vi` if `$EDITOR` isn't set):

```
# Phase: initial
# Title: Anonymous SMB share leads to WordPress RCE
# Severity: critical

## Vulnerability Explanation
(what the vulnerability is, and why this target is affected)

## Vulnerability Fix
(the concrete remediation)
```

Fill in the two sections and save; the file is stored under `vulns/` (numbered and slugged from the title, e.g. `vulns/01-initial-anonymous-smb-share-leads-to-wordpress-rce.md`), and a one-line entry is added to the timeline (`vuln recorded: [initial] Anonymous SMB share leads to WordPress RCE (critical)`).

If you exit the editor without filling in the placeholders, the file is still kept - but unlike the rest of `vulns/`, `mkbox -r` **does** check this one thing: if either placeholder (`(what the vulnerability is...)` / `(the concrete remediation)`) is still sitting there untouched, it prints a warning naming the file, the same way it warns about an unticked Proof checklist item. It's still on you to go back and write the real explanation and fix - this only catches the "forgot entirely" case, not a thin or wrong one.

`mkbox -r` collects everything under `vulns/` into a **Findings** section in the report, grouped and ordered by phase (Initial Access, then Privilege Escalation, then Post Exploitation), each with its title, severity, explanation and fix, separated from the next finding by a rule so two findings in the same phase don't run together - this is what `mkbox -a` (below) pulls into each target's write-up.

## Active Directory sets and assembling the final report

The exam report template splits your work into two parts: standalone targets under **Independent Challenges** (each with its own Initial Access / Service Enumeration / Privilege Escalation / Post Exploitation write-up), and, for the AD set, one combined ports table followed by a per-host write-up under **Active Directory Set**. `mkbox` tracks which boxes belong to which with a single flag.

**Marking a box as part of the AD set.** Either at creation:

```
mkbox dc01 10.10.10.5 --ad
```

or at any point from inside the box shell:

```
setad on     # or: setad off
```

`boxinfo` shows `AD set: yes` once it's flagged. This is stored in `box.env` (`AD_SET`), so it's per-box and persists across sessions.

**Assembling the final document.** Once you've got reports' worth of material across several boxes, `mkbox -a <outfile.md> <box1> [box2 ...]` regenerates each box's own report and collates them into one draft, shaped like the real template:

```
mkbox -a draft.md lame dc01 dc02 filesrv03
```

Any `WARNING:` line a box's own `mkbox -r` would have printed (an unticked Proof item, an unfilled `addvuln` entry, a password that turns up somewhere it shouldn't) is captured instead of being thrown away, and printed once under `Assembled draft:`, prefixed with the box it came from - previously these were silently lost the moment a box was rolled into `-a` instead of reported on its own.

Alongside those, a **Readiness check** prints for any box with zero recorded screenshots and/or zero `addvuln` findings - informational, not a `WARNING:`, since it's entirely normal for a box you're still mid-testing to have neither yet. It's specifically there for the pass right before you submit, as a second check that nothing's missing across the whole report: a target with no proof screenshot, or no write-up at all, is easy to miss once several boxes' worth of content are all mixed into one draft.

Screenshots embedded in each box's own report carry through into the assembled draft too, with their image paths automatically rewritten from relative (correct only for that box's own `mkbox -r`) to absolute (correct wherever `draft.md`/`--odt`/`--pdf` end up living) - nothing to do on your end for this to work.

### Assembling without leaving the box

Typing `mkbox -a draft.md --pdf --author="Jane" lame dc01 dc02 filesrv03` from a plain terminal works, but it means leaving every box's shell, remembering every box's exact name, and retyping the same flags each time you want an updated draft - tedious enough, especially mid-exam, that you're liable to just stop checking it until the very end. **`assemble`**, run from inside *any* box's own shell, does the same thing with none of that:

```
[box:lame] root@kali:~/lame# assemble
Assembling 4 box(es) into /home/kali/labs/report.md: dc01 dc02 filesrv03 lame
...
ODT draft:       /home/kali/labs/report.odt
PDF draft:       /home/kali/labs/report.pdf  (table of contents already updated and page numbers computed...)
```

No outfile, no box list, no flags required:

- **Every box next to this one** (same directory `boxinfo`/`boxcd` already treat as "the labs folder") is found automatically by looking for a `box.env` in each sibling directory - the same check `mkbox -l` uses - so a box you haven't touched in days is still included without you having to remember it exists.
- **The output always lands at `report.md`/`.odt`/`.pdf` next to the boxes**, not inside any one of them, so it's in the same place every time regardless of which box's shell you ran it from.
- **With no flags given, it defaults to `--pdf`** - the single most complete thing it can hand you - and that degrades to `--odt`, or even just the Markdown draft, on its own if LibreOffice isn't available (same as `--pdf` always does), so a bare `assemble` is never worse than typing nothing at all.
- **Flags you do give are remembered** (in a small `.mkbox-assemble.conf` file next to the boxes) and reused by the next bare `assemble` - so `assemble --odt --author="Jane Q. Tester"` once, and every later plain `assemble` keeps producing exactly that, until you explicitly pass something different.

**`boxes`**, also run from inside any box's shell, is the same box list `mkbox -l` prints, without leaving the shell to check what else is in play first.

This produces `draft.md` with:

- `High-Level Summary`, `Recommendations`, and `Methodology` - `mkbox` only knows what happened on each box, not what to say about it, so (same as everywhere else) it doesn't guess. Write them once with `reporttext` (see [below](#writing-the-sections-only-you-can-write)); until you do, each is a `TODO` stub and `assemble` lists exactly which ones are still missing. The `Methodology` guidance is a reminder to write up Information Gathering / Service Enumeration / Penetration from what you actually did; it deliberately does **not** add a Maintaining Access / House Cleaning stub, since the current OSCP Exam Guide doesn't ask for persistence or cleanup on exam hosts - check the guide yourself before adding one, in case that changes.
- A **Tools Used** section under `Methodology`, already filled in (not a `TODO`) naming `mkbox` itself and its version/repo link, alongside a reminder to list anything else you used - OSCP reporting expects any extra tooling beyond the standard set to be documented, and this one you don't have to remember to add yourself.
- `Independent Challenges`, with every box you didn't flag as AD, each nested under its own `Target #N - <ip>` heading.
- `Active Directory Set`, with every flagged box: first one combined ports table (IP + open TCP ports, across all of them), then each box's own write-up nested under `<boxname> - <ip>` instead of a generic `Target #N`.
- Each box's own report content (ports, findings, notes, pivot chain, nmap output, screenshots, exploits, loot, credentials) nested underneath, with its headings demoted so they sit at the right depth under the template's own numbering, and its own top `# <name> - report draft` title line dropped (that title now exists one level up). Headings that would end up deeper than the template actually supports (level 3) are converted to **bold paragraphs** instead of ever-deeper heading syntax, so nothing silently renders as unstyled `####` text.
- Any `notes.md` section you never filled in (an empty `-` placeholder bullet, such as an unfilled **Rabbit holes**) is rewritten as `_(nothing recorded)_` in the assembled draft - this is intentional, so a glance at the draft shows you exactly what's still unfinished, rather than hiding it as an empty section.

Pass `--creds` to include `creds/creds.txt` for every box, same as `mkbox -r --creds`.

**Converting to ODT.** Pass `--odt` and `mkbox -a` also produces `<outfile>.odt` - a real document, not just differently-styled Markdown:

```
mkbox -a draft.md --odt --author="Jane Q. Tester" --osid=OS-12345 lame dc01 dc02 filesrv03
```

By default (no `=path`, and `$MKBOX_ODT_TEMPLATE` unset) this uses mkbox's own bundled template (`templates/mkbox-default.odt`, shipped alongside the script), which needs nothing from you and gives you, entirely deterministically:

- **A real cover page** - title (`OSCP Exam Report` by default; `--title="Acme Q4 Pentest"`, or set `$MKBOX_TITLE`, for anything else), your OSID (`--osid`, or set `$MKBOX_OSID` once - OffSec expects it somewhere on the report, this just saves retyping it), your name (`--author`, or set `$MKBOX_AUTHOR` once instead of typing it every time), and the date - on its own page. Both `--osid` and `--author` are optional and independent of each other.
- **A real Table of Contents.** Pandoc and LibreOffice/Word build the field structure, but don't actually compute page numbers at generation time - open the ODT and do **Tools > Update > All** once (or right-click the TOC and choose **Update Index**) and it fills in correctly, exactly as it would for any other document with a TOC field. This is a one-click, completely normal step for any ODT/DOCX with a table of contents, not a sign anything is broken.
- **Automatically numbered headings** (`1`, `1.1`, `1.1.1`, matching the Independent Challenges / Active Directory Set structure `mkbox -a` already builds), and **page numbers** in the footer - both wired up in the bundled template's styles, so there's nothing left to configure.

This is why the OffSec exam guide's note on reporting flexibility (any reasonable tool/workflow is fine, as long as the final report is a clear PDF write-up of what you did) matters here: you are **not** required to submit on OffSec's own template, so there's no need to track down your own copy of it or point `--odt` at one. If you'd rather use a different template anyway (OffSec's own, or your own company's), you still can - pass `--odt=<path-to-template.odt>`, or set `$MKBOX_ODT_TEMPLATE` once so you can leave the path off on later runs. A few things worth knowing either way:

- **It copies the template's styles, not its original content.** Any boilerplate text that was already written into the *body* of a template you point `--odt` at (OffSec's own included) isn't reproduced - only mkbox's own bundled template gets a cover page and TOC, generated fresh for every draft, since those are built from the Markdown itself, not copied out of any .odt. Pointing `--odt` at a different template still gets you a cover page, TOC and forced page breaks the same way (mkbox patches a page-break style into it if it doesn't have one) - just not that template's own original wording or layout beyond its styles.
- Some ODT templates (including OffSec's own) name their heading styles `Heading1`/`Heading2`/`Heading3` instead of pandoc's own `Heading 1`/`Heading 2` convention - without extra handling, `--reference-doc` would copy the style *definitions* but nothing in the generated document would actually reference them, so every heading would silently render as plain body text. `mkbox` detects this and patches the generated file to use whichever naming the template actually uses, after pandoc runs. (The bundled default template already matches pandoc's own naming, so this never triggers for it.)
- The Proof checklist (`- [x] local.txt: ...`) is Markdown task-list syntax; converted at face value it renders as a Unicode checkbox glyph, and most ODT templates' body font (including OffSec's own) doesn't have that glyph, so it shows up as an empty box instead of a check mark. `mkbox` tells pandoc to read it as plain text instead, so it comes through as `[x] local.txt: ...` - legible, if not styled as a real checkbox.
- This needs `pandoc` installed; if it isn't, `mkbox` says so and skips the ODT step (the Markdown draft is still produced).

**Exporting straight to PDF.** OSCP submission wants a PDF anyway, and the one manual step `--odt` still leaves you - opening the file and doing Tools > Update All so the Table of Contents actually has page numbers - is exactly what `--pdf` automates:

```
mkbox -a draft.md --pdf --author="Jane Q. Tester" --osid=OS-12345 lame dc01 dc02 filesrv03
```

`--pdf` implies `--odt` (so you still get both `draft.odt` and `draft.pdf`), then drives a throwaway, invisible LibreOffice instance over its own UNO scripting interface to do what you'd otherwise do by hand: open the ODT, update every index (which is what actually computes real page numbers), resave it, and export the PDF from that updated copy - so the TOC in `draft.pdf` is already correct, not frozen at "no page computed yet". It uses its own LibreOffice profile and a random port each run, so it won't conflict with a LibreOffice window you already have open.

This needs `soffice` (LibreOffice itself) and a `python3` with its `uno` module available - both are already present on a normal LibreOffice install (true for Kali and most exam-VM setups by default). If either is missing, or the LibreOffice instance never comes up, `--pdf` degrades to exactly what `--odt` alone would have done: the ODT is still written, and `mkbox` tells you to finish it yourself (Tools > Update All, then File > Export As PDF) rather than failing the whole assemble over a nice-to-have.

**A hard stop before you submit: `--final`.** `--pdf` on its own is happy to build a PDF with `TODO` stubs still in it (it only warns). Add `--final` for the real export:

```
mkbox -a draft.md --final --author="Jane Q. Tester" --osid=OS-12345 lame dc01 dc02 filesrv03
```

If the High-Level Summary, Recommendations or Methodology is still unwritten, any `addvuln` finding is still the blank template, or a modified exploit has no marked changes, `mkbox` lists what's missing, writes the Markdown draft as usual, but **does not build the ODT/PDF** and exits non-zero. It also exits non-zero if the PDF itself couldn't be produced (no LibreOffice), instead of quietly falling back to an ODT. `--final` on its own implies `--pdf`; with `--odt` it only does the unwritten-sections check. In the box shell, `assemble --final` does the same; it is never remembered between runs, so a plain `assemble` stays a no-fuss work-in-progress rebuild.

**Packaging for upload: `--submit`.** The exam guide wants a PDF named exactly `OSCP-OS-XXXXX-Exam-Report.pdf`, inside an unencrypted `OSCP-OS-XXXXX-Exam-Report.7z` (nothing else in it, at most 200MB), uploaded to upload.offsec.com with the MD5 checked against the one the site shows. `--submit` does all of that after the `--final` checks pass:

```
mkbox -a report.md --submit --osid=OS-12345 lame dc01 dc02 filesrv03
```

It writes both files next to `report.md`, then prints the archive's MD5 to compare. The OSID is required (`--osid`, or `$MKBOX_OSID`) and is accepted as `OS-12345`, `OS12345` or `os-12345`; the file names always use `OS-12345`. It needs `7z` (`sudo apt install p7zip-full`), refuses an archive over 200MB, and rebuilds the `.7z` from scratch every time. In the box shell, `assemble --submit` works the same way and is never remembered between runs. Read the PDF through before you upload it: a submission is final.

### Writing the sections only you can write

Three sections of the report can't come from your notes: the **High-Level Summary**, the **Recommendations**, and the **Methodology**. Write them without leaving the box shell:

```
reporttext                    # which of the three are written, which are still TODO
reporttext summary            # opens it in $EDITOR (a short guidance comment is already at the top)
reporttext recommendations    # alias: recs
reporttext methodology        # alias: method
assemble                      # pulls them in; lists whatever is still a TODO stub
```

Outside the shell the same thing is `mkbox --text [section]`, run from the directory your boxes (and `report.md`) live in.

- **They live in `report-parts/` next to the assembled report** (`summary.md`, `recommendations.md`, `methodology.md`), not inside `report.md`, so rebuilding the report - which regenerates `report.md` from the boxes every time - never overwrites your writing.
- **Write plain paragraphs and lists, and skip `#` headings** - `mkbox` adds the section heading itself. If you use one anyway (including the underlined `Title` over `=====` style), it is pushed down a level (`#` becomes `##`, and anything deeper than the report's third level becomes a bold line) so it can't disturb the heading numbering; `#` lines inside code fences are left alone, and `assemble` tells you when it demoted something. The guidance comment at the top of each new file is ignored; you can leave it or delete it. A file that's empty or still starts with `TODO` counts as unwritten.
- **Every `assemble` ends with a checklist** of whatever is still unwritten, with the exact command for each, so you find out before the PDF rather than after.
- The `Tools Used` subsection under `Methodology` is added automatically after your text.

## What it does and doesn't do

**It does:**

- create folders and a notes template on your own machine
- record your own terminal session to a local log file
- keep timestamped shell history
- wrap `nmap`, `python3 -m http.server`, and common connection tools (`ssh`, `ftp`, `rdesktop`, ...) in short helpers that you invoke yourself - see [Logging connections](#logging-connections-ssh-ftp-rdp-)
- read your clipboard, only when you run `shot`, and only to save an image you copied
- assemble your notes, commands and screenshots into a markdown draft and a tarball

**It doesn't:**

- run any scan, exploit, or tool automatically; every action is a command you type
- send data anywhere or make any network connection of its own - the connection wrappers (`ssh`, `ftp`, ...) only run the real binary with the exact arguments you typed, exactly when you typed it, and only add a local timeline note before and after
- automate exploitation, brute-forcing, or vulnerability scanning
- modify the target or anything outside the box directory

The whole tool is a single readable bash script (`mkbox`), so it is easy to audit. If you are using it for an exam, check the current exam guide for tool and logging rules; this tool does not change what is or isn't permitted.

## Caveats

- The raw log, cleaned log, and history capture everything you type or paste, including passwords. **Do not commit box directories to a public repository.** Only commit the tool itself. Every box directory now gets a `.gitignore` containing just `*` the first time it's created (never overwritten if you replace it yourself), so this requires an explicit `git add -f` to defeat rather than a stray `git add -A`.
- The session log in the evidence tarball includes the `addcred user:pass` lines exactly as you typed them. `--creds` only controls whether `creds/` itself is bundled.
- `.box.rc` is regenerated on every run. To change helpers or shell settings, edit the heredoc in `mkbox`, not the generated file.
- Changing `$IP` by hand now sticks until `box.env` is next written (by `setip`, `portscan`, `udpscan`, or another tab) - see the gotcha in [Shared state and multiple tabs](#shared-state-and-multiple-tabs). Prefer `setip`.
- `ssh`, `ftp`, `rdesktop`, and the other commands listed in [Logging connections](#logging-connections-ssh-ftp-rdp-) are wrapped to log a start/end timeline note; this is passthrough and doesn't change how they behave - see that section for exactly what it does and doesn't catch.
- `mkbox` expects GNU `find`, `date` and `realpath` (standard on Kali and most Linux distros).
- The password-masking rules are written in portable awk and were tested with `mawk` (Kali's default `awk`).
- `mkbox -a` caps nested heading depth at 3 levels to match what the official exam report template itself supports; anything a box's own report would otherwise put deeper becomes a bold paragraph instead of a numbered heading. It also rewrites an unfilled `notes.md` placeholder bullet as `_(nothing recorded)_` in the assembled draft only - your live `notes.md` and each box's own standalone `mkbox -r` report are untouched.
- `--odt` needs `pandoc` on `$PATH`, plus `python3` for the heading-style and forced-page-break patches described in [Active Directory sets and assembling the final report](#active-directory-sets-and-assembling-the-final-report); without `python3` those patches are silently skipped rather than failing, which (only when pointed at a custom, non-bundled template) can mean unstyled headings or a missing page break before the cover page / TOC.
- The Table of Contents in a `--odt` output needs one manual step: open the file and do Tools > Update > All (or right-click it and choose Update Index) so LibreOffice/Word fills in the real page numbers. This is ordinary behavior for any document with a TOC field, not something mkbox could skip - pandoc and LibreOffice/Word don't compute final page numbers until the document is actually laid out by one of them. `--pdf` does this step for you, automatically, as part of exporting the PDF.
- `--pdf` additionally needs `soffice` and a `python3` with its `uno` module - both ship with a normal LibreOffice install. Without them (or if LibreOffice fails to start in time), `--pdf` degrades to the same result as `--odt` alone: the ODT is still written, with a message telling you to finish it by hand.

## Development

`tests/smoke.sh` is a self-contained smoke test (stubs for `nmap`, `sudo`, `ssh` and friends; no network, nothing outside a temp directory). CI runs it together with `shellcheck`:

```
shellcheck mkbox install.sh tests/smoke.sh
bash tests/smoke.sh
```

The `--odt` checks need `pandoc` and are skipped when it isn't installed; the `--pdf` checks additionally need LibreOffice with `uno`. Set `MKBOX_REQUIRE_PDF=1` to make a missing pandoc/LibreOffice/`uno` a failure instead of a skip (CI does this, so the PDF path can't go untested unnoticed). The CI job installs `pandoc libreoffice-writer python3-uno poppler-utils` to run them.

See `CHANGELOG.md` for what changed in each release.
