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
- [Logging connections (ssh, ftp, rdp, ...)](#logging-connections-ssh-ftp-rdp-)
- [Logs](#logs)
- [Reporting](#reporting)
- [What it does and doesn't do](#what-it-does-and-doesnt-do)
- [Caveats](#caveats)

## Install

```
git clone https://github.com/cherneydh/mkbox mkbox && cd mkbox
sudo install -m 755 mkbox /usr/local/bin/mkbox
```

Or put `mkbox` anywhere on your `PATH` (for example `~/bin`) and `chmod +x mkbox`.

Requirements:

- `bash`, `script` (util-linux), `tar`, `find`, and GNU `date`, `sed`, `awk`, `grep` (all standard on Kali)
- `perl` for log cleanup (preinstalled on Kali; without it, cleanup falls back to a cruder `sed` version)
- `nmap` for `portscan`, `udpscan` and `svcscan`
- `xclip` (X11) or `wl-clipboard` (Wayland) for `shot`

## Quick start

```
cd ~/oscp/htb
mkbox lame 10.10.10.3        # create ./lame, enter it, start logging

# inside the box shell
portscan                     # all-TCP-ports nmap sweep, saved to nmap/
svcscan                      # default scripts + versions on the open ports
udpscan                      # top-20 UDP ports (slow; try a second tab)
note "anonymous FTP allowed" # timestamped timeline entry
addcred bob:hunter2 "ssh"    # record a credential
exit                         # leave; the session log is cleaned automatically

mkbox -r lame                # build a report draft + evidence tarball
```

## Commands

```
mkbox [-n|--no-shell] <boxname|path> [target-ip]
mkbox -c|--clean  <boxname|path>
mkbox -r|--report [--creds] <boxname|path>
mkbox -l|--list
```

| Command                    | What it does                                                                     |
| -------------------------- | -------------------------------------------------------------------------------- |
| `mkbox lame 10.10.10.3`    | Creates `./lame`, enters it, starts logging                                      |
| `mkbox lame`               | Re-enters an existing box as a new session (safe to run in several tabs at once) |
| `mkbox .`                  | Uses the current directory as the box                                            |
| `mkbox ~/labs/pg/foo`      | Any path works; the last component is the box name                               |
| `mkbox -n lame 10.10.10.3` | Creates the box without starting a shell                                         |
| `mkbox -c lame`            | Rebuilds the cleaned log from the raw session logs                               |
| `mkbox -r lame`            | Builds a report draft and evidence tarball                                       |
| `mkbox -r --creds lame`    | Same, but includes recorded credentials                                          |
| `mkbox -l`                 | Lists boxes in the current directory with target IP and proof status             |

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

## The box shell

Entering a box starts a `bash` session (even if your login shell is zsh) with:

- `script` logging everything to a raw log for this session, flushed after every write so a crash doesn't lose it
- `HISTTIMEFORMAT="%F %T "` so `history` shows dates and times
- a per-box history file, written after every command (not just on exit)
- `$IP`, `$PORTS` and `$UDP_PORTS` kept in sync across tabs (see below), plus `$BOX` and `$BOX_DIR`
- a `[box:name]` prefix in your prompt
- a leading space on a command keeps it out of history (`HISTCONTROL=ignorespace`)

Type `exit` to leave. You return to the directory you started in.

## Shared state and multiple tabs

Open `mkbox lame` in as many terminal tabs as you like. Each tab gets its own raw log, so they never overwrite or scramble each other, and each shows up as its own labeled section in `session-lame.log` (ordered by start time, not interleaved).

Shared between tabs:

- **`$IP`, `$PORTS`, `$UDP_PORTS`.** They live in `box.env`, and every tab checks that file's modification time before each prompt and only re-reads it when it has actually changed. Run `setip` after a machine revert, or `portscan` / `udpscan` in one tab, and the other tabs pick up the new values at their next prompt. `box.env` is written atomically (temp file and rename), so a tab never reads a half-written file.
- the timestamped history file (written after every command)
- `notes/timeline.md`, `screenshots/`, and everything else in the box folder

Not shared: output. Each tab's terminal output goes to that tab's own log.

**Manual edits now stick (until something else writes `box.env`).** Typing `IP=10.10.10.50` by hand is no longer reverted at the next prompt, because the sync only re-sources `box.env` when its mtime changes. It's still better to use `setip`, because that also updates the notes header and the timeline - a hand-set `$IP` only changes the variable. And the next `portscan` / `udpscan` in that tab will happily save your hand-set `$IP` back into `box.env` (sharing it with other tabs), since mkbox has no way to tell a manual edit from an intentional one. For other hosts (pivoting, the AD set), use your own variable names such as `$DC` or `$T2` so they never collide with `box.env` at all.

If a session ends abnormally (terminal closed, SSH dropped), cleanup doesn't run. Run `mkbox -c <boxname>` to rebuild the cleaned log.

## Helpers

Available inside the box shell:

| Helper                      | What it does                                                                                                      |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `note "text"`               | Appends a timestamped line to `notes/timeline.md`                                                                 |
| `shot "note"`               | Saves the image on your clipboard to `screenshots/` with a timestamp and note, and logs it to the timeline        |
| `boxinfo`                   | Shows target, ports, file counts, proof checklist, recent timeline                                                |
| `boxcd [subdir]`            | `cd` to the box directory or a subfolder (`boxcd nmap`)                                                           |
| `setip <ip>`                | Changes the target IP (after a machine revert); validates it, updates `box.env` and the notes header              |
| `portscan`                  | Runs `nmap -p- --min-rate 2000 -T4` into `nmap/allports.*`, sets `$PORTS`                                         |
| `udpscan [N]`               | Runs `nmap -sU -sV --top-ports N --open` (default 20) into `nmap/udp.*`, sets `$UDP_PORTS`                        |
| `svcscan [ports]`           | Runs `nmap -sC -sV -p <ports>` into `nmap/services.*` (defaults to `$PORTS`; accepts numbers and ranges)          |
| `serve [--bind ip] [port]`  | Runs `python3 -m http.server` in `transfer/` (default port 80, all interfaces; uses `sudo` for ports below 1024 if you aren't root) |
| `ssh`, `ftp`, `sftp`, `smbclient`, `rdesktop`, `xfreerdp`, `nc`, `telnet`, `mysql`, ... | Logged automatically on connect/disconnect - see [Logging connections](#logging-connections-ssh-ftp-rdp-) |
| `addcred user:pass [where]` | Appends to `creds/creds.txt`; the timeline records only the username                                              |
| `proofcmd`                  | Prints one-liners to paste on a target to show proof file, user, hostname, and IP                                 |
| `cleanlog`                  | Rebuilds the cleaned session log mid-session                                                                      |
| `report [--creds]`          | Same as `mkbox -r` for the current box                                                                            |

### Screenshots

Take a screenshot with whatever tool you like, copy it to the clipboard, then run:

```
shot "anonymous FTP login works"
```

This saves the clipboard image as `screenshots/<YYYYmmdd-HHMMSS>-<note-slug>.png`, records the note and time in `screenshots/captions.tsv`, and adds a line to `notes/timeline.md`. `mkbox -r` embeds each screenshot in the report draft with its caption and timestamp, in the order you took them.

- The image is saved exactly as copied. `shot` never edits or annotates it.
- It needs `xclip` on X11 (`sudo apt install xclip`) or `wl-clipboard` on Wayland. The clipboard must contain a PNG; anything else is rejected without saving.
- Over plain SSH there is no desktop clipboard, so `shot` won't work there.

### Recon wrappers

`portscan`, `udpscan` and `svcscan` are thin wrappers that run `nmap` with the fixed flags shown above, so you can read exactly what they do in the script. They use `sudo` unless you are already root.

- **Re-runs keep your old results.** Before a scan overwrites `nmap/allports.*`, `nmap/udp.*` or `nmap/services.*`, the previous files are renamed with the time of that scan (for example `allports-20261009-160035.nmap`). The report includes all of them, oldest first.
- **UDP is slow.** `udpscan` can take minutes; run it in a second tab. Only ports nmap reports as `open` go into `$UDP_PORTS`. Ports reported as `open|filtered` are printed and noted in the timeline, but not stored; check `nmap/udp.nmap` for them.
- **Output isn't left root-owned.** `nmap -oA` runs under `sudo`, so its output files are written as root; mkbox hands them back to you (`chown`) right after each scan, so you don't need `sudo` just to read your own results.

## Logging connections (ssh, ftp, rdp, ...)

Connecting out to the target is one of the most report-relevant things you do, so mkbox wraps a set of common remote/transfer commands - `ssh`, `sshpass`, `ftp`, `sftp`, `ncftp`, `lftp`, `smbclient`, `rdesktop`, `xfreerdp`, `remmina`, `nc`, `ncat`, `netcat`, `telnet`, `mysql`, `psql`, `evil-winrm` - and logs each one to `notes/timeline.md` automatically:

```
2026-10-09 18:04:08  ssh: started (-p *** bob@10.10.10.9)
2026-10-09 18:04:41  ssh: ended (exit 0, 33s)
```

**This is passthrough, not a new feature to interact with.** Each wrapper runs the real binary directly, in the foreground, with your terminal exactly as it would be without mkbox: interactive password prompts, full-screen programs (`vim` or a shell over `ssh`), `scp`/`sftp` progress bars, Ctrl-C, and the real exit code all behave normally. Nothing is piped, backgrounded, or given its own pty. A command is only wrapped if that binary is actually on your `PATH` when the box shell starts, so nothing is ever shadowed by a "command not found."

- **Password masking is best-effort**, same spirit and same limits as `addcred`/`warn_secrets`: it catches `-p`/`-P`/`--password[=]`/`--pass[=]` followed by a value, and the credential portion of a `user:pass@host` URL. It does not catch a password spelled some other tool's own way, and it doesn't need to catch one typed at an interactive prompt - that one was never on the command line. The **raw session log always has the real command** (that's what `script` records), so masking only affects the generated report's chronological log and the timeline note, never your actual history.
- **`sudo` bypasses the wrapper**, because `sudo` resolves the real binary from `PATH`, not from your shell's functions - `sudo nc ...` is still captured in your history and session log like any other command, just without the start/end timeline note.
- **To run the real binary once without logging it**: `command ssh ...` or `\ssh ...`.
- **To wrap more tools** (or fewer): set `MKBOX_NET_CMDS` to a space-separated list of binary names, either in your shell before running `mkbox`, or in your own `~/.bashrc` (which loads before `.box.rc` and is respected).

## Logs

- `.sessions/<start-time>-<pid>.raw` is the raw `script` output for one `mkbox` invocation, including escape codes. Every invocation gets its own file.
- `session-<boxname>.log` is the readable version. It is rebuilt from all the raw session logs every time you exit, oldest first, with a `===== session <start time> =====` header before each one, so earlier sessions are never lost.

Cleanup behaves like a simple terminal: carriage returns and backspaces move a cursor and later characters **overwrite** earlier ones, `ESC[K` erases to end of line, cursor-move and delete sequences from readline are applied, and colors, window titles and other control codes are dropped. Tab completion, Ctrl-R and history recall therefore come out as the final line you saw. It cannot follow cursor-up redraws of a command that wraps across several screen rows, so very long wrapped lines can still show leftover fragments. Commands and their output are always preserved. Without `perl`, cleanup falls back to a cruder version that strips escapes but doesn't apply overwrites.

## Reporting

`mkbox -r <box>` writes two files into `<box>/report/`:

- `<boxname>-report.md`: a draft assembled from your notes, a chronological log, nmap results, screenshots, exploit and loot filenames, and a credentials section.
- `<boxname>-evidence.tar.gz`: `notes/`, `screenshots/`, `nmap/`, `exploits/`, `web/`, the cleaned session log, and the report draft.

### The chronological log

The **Timeline** section merges three sources by time:

- **commands** from the box's history file, shown in code blocks with a timestamp
- **notes** from `notes/timeline.md`
- **screenshots** from `screenshots/captions.tsv`, listed with file name and caption (the images themselves are embedded in the **Screenshots** section)

What it leaves out or changes:

- Trivial commands are skipped: `ls`, `ll`, `la`, `cd`, `pwd`, `clear`, `history`, `exit`, `logout`, and the helpers `note`, `shot`, `boxinfo`, `boxcd`, `cleanlog`, `proofcmd`, `report`.
- `addcred user:pass ...` appears as `addcred user:***`, so the password never reaches the report.
- A password passed to `ssh`/`ftp`/`smbclient`/etc. via `-p`, `-P`, `--password[=]`, `--pass[=]`, or in a `user:pass@host` URL is masked the same way - see [Logging connections](#logging-connections-ssh-ftp-rdp-) for exactly what that does and doesn't catch.
- Commands you start with a space aren't in your history, so they aren't in the log either (they are still in the session log).

If there's no history yet, the section falls back to the raw `timeline.md`. The merge needs GNU `date`. If a timestamp in `notes/timeline.md` or `screenshots/captions.tsv` can't be parsed, `mkbox -r` prints a `WARNING` to stderr and leaves that source out of the merged **Timeline** section for this run rather than silently dropping it - the raw notes/captions themselves are untouched and still go into the evidence tarball.

### What is and isn't included

By default credentials are **not** inlined and `loot/` contents are never bundled (filenames only). Pass `--creds` to include `creds/`.

That only covers those folders. Notes, exploits and the session log are bundled as you typed them, and other passwords you typed into commands not covered by the masking above (a `hydra` line, say, or a tool-specific password flag the [connection wrappers](#logging-connections-ssh-ftp-rdp-) don't recognize) appear in the chronological log. When you run without `--creds`, `mkbox -r` checks every password in `creds/creds.txt` against the files going into the bundle and prints a `WARNING` naming where it found one. It can't catch passwords you never recorded with `addcred`.

The draft is a starting point: you still write the actual report.

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
- `.box.rc` is regenerated on every run. To change helpers or shell settings, edit the heredoc in `mkbox`, not the generated file.
- Changing `$IP` by hand now sticks until `box.env` is next written (by `setip`, `portscan`, `udpscan`, or another tab) - see the gotcha in [Shared state and multiple tabs](#shared-state-and-multiple-tabs). Prefer `setip`.
- `ssh`, `ftp`, `rdesktop`, and the other commands listed in [Logging connections](#logging-connections-ssh-ftp-rdp-) are wrapped to log a start/end timeline note; this is passthrough and doesn't change how they behave - see that section for exactly what it does and doesn't catch.
- `mkbox` expects GNU `find`, `date` and `realpath` (standard on Kali and most Linux distros).
