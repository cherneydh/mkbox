# Changelog

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
