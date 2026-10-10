#!/usr/bin/env bash
# Smoke test for mkbox. Needs bash, script (util-linux), perl, GNU date/find/tar. No network, no
# real nmap: harmless stubs for nmap, sudo, ssh, sshpass and chown are put first on PATH.
#
#   bash tests/smoke.sh
#
# Exits non-zero if any check fails. Safe to run anywhere: everything happens in a temp directory.

set -uo pipefail

MK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/mkbox"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/my labs"          # a space in the path on purpose
export PATH="$T/bin:$PATH"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }
has()   { grep -qF -- "$2" "$1"; }                       # has <file> <text>
lacks() { ! grep -qF -- "$2" "$1"; }                     # lacks <file> <text>
mode()  { [ "$(stat -c %a "$1")" = "$2" ]; }             # mode <path> <octal>

# --- stubs --------------------------------------------------------------------------------------
cat > "$T/bin/nmap" <<'STUB'
#!/usr/bin/env bash
# writes the three -oA files the way nmap does
base=""
while [ $# -gt 0 ]; do if [ "$1" = "-oA" ]; then base="$2"; fi; shift; done
printf 'Nmap scan report\n22/tcp open ssh\n' > "$base.nmap"
printf 'Host: 10.10.10.9 ()\tPorts: 22/open/tcp//ssh///, 80/open/tcp//http///\n' > "$base.gnmap"
printf '<nmaprun/>\n' > "$base.xml"
STUB
cat > "$T/bin/sudo" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "-n" ]; then shift; fi
exec "$@"
STUB
cat > "$T/bin/chown" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${CHOWN_LOG:-/dev/null}"
exec "$(PATH="${PATH#*:}" command -v chown)" "$@"
STUB
# serve backends: record the arguments instead of starting a server
for tool in impacket-smbserver wsgidav; do
  # shellcheck disable=SC2016  # the stub script must expand $* and ${SERVE_LOG} when it runs, not now
  printf '#!/usr/bin/env bash\necho "%s $*" >> "${SERVE_LOG:-/dev/null}"\n' "$tool" > "$T/bin/$tool"
done
for tool in ssh sshpass; do
  printf '#!/usr/bin/env bash\necho "stub %s $*"\n' "$tool" > "$T/bin/$tool"
done
chmod +x "$T/bin/"*
export CHOWN_LOG="$T/chown.log"
export SERVE_LOG="$T/serve.log"

cd "$T/my labs" || exit 1

# --- basics -------------------------------------------------------------------------------------
echo "basics"
check "--version prints mkbox X.Y.Z"     bash -c "'$MK' --version | grep -Eq '^mkbox [0-9]+\.[0-9]+\.[0-9]+\$'"
"$MK" -n smoke 10.10.10.9 > "$T/n1.out" 2>&1
check "-n creates the box"               has "$T/n1.out" "Created"
check "box layout exists"                test -d smoke/nmap -a -d smoke/screenshots -a -f smoke/notes/notes.md
check ".gitignore is just *"             test "$(cat smoke/.gitignore)" = '*'
check "new box dir is private (700)"     mode smoke 700
check "box.env remembers the IP"         has smoke/box.env "10.10.10.9"
"$MK" -n smoke > "$T/n2.out" 2>&1
check "-n on an existing box says so"    has "$T/n2.out" "already exists"
check "bad box name rejected"            bash -c "! '$MK' -n 'bad name' 2>/dev/null"
check "IP starting with - rejected"      bash -c "! '$MK' -n other -sV 2>/dev/null"
check "-l lists the box"                 bash -c "'$MK' -l | grep -q '^smoke .*10.10.10.9'"

# --- a real logged session (script + interactive bash), fed from a pipe --------------------------
echo "session"
printf '%s\n' \
  'note started recon' \
  'portscan' \
  'svcscan' \
  'addcred bob:Hunter2pw ssh' \
  'ssh -p 2222 user@10.10.10.9' \
  'sshpass -p Sup3rSecret ssh admin@10.10.10.9' \
  'exit' | "$MK" smoke 10.10.10.9 > "$T/session.out" 2>&1
check "banner says re-entering"          has "$T/session.out" "re-entering 'smoke'"
check "portscan set \$PORTS"             has smoke/notes/timeline.md "portscan: open ports 22,80"
# shellcheck disable=SC2016  # the single quotes are intentional: the inner bash expands $PORTS
check "ports shared via box.env"         bash -c '. smoke/box.env && [ "$PORTS" = "22,80" ]'
check "svcscan ran"                      test -f smoke/nmap/services.nmap
check "addcred: timeline has username"   has smoke/notes/timeline.md "cred recorded for bob"
check "addcred: timeline has no password" lacks smoke/notes/timeline.md "Hunter2pw"
check "creds.txt holds the password"     has smoke/creds/creds.txt "bob:Hunter2pw"
check "creds.txt is mode 600"            mode smoke/creds/creds.txt 600
check "ssh wrapper: start note, port intact" has smoke/notes/timeline.md "ssh: started (-p 2222 user@10.10.10.9)"
check "ssh wrapper: end note"            has smoke/notes/timeline.md "ssh: ended (exit 0"
check "sshpass note masks the password"  has smoke/notes/timeline.md "sshpass: started (-p *** ssh admin@10.10.10.9)"
check "sshpass password not in timeline" lacks smoke/notes/timeline.md "Sup3rSecret"
check "cleaned session log exists"       test -s smoke/session-smoke.log
check "cleaned log is mode 600"          mode smoke/session-smoke.log 600
check "cleaned log has no escape codes"  bash -c "! grep -q \$'\\x1b' smoke/session-smoke.log"
check "raw session log is mode 600"      bash -c "for f in smoke/.sessions/*.raw; do [ \"\$(stat -c %a \"\$f\")\" = 600 ] || exit 1; done"
if [ "$(id -u)" -ne 0 ]; then
  check "scan output is chowned back to you (non-root)" test -s "$CHOWN_LOG"
else
  echo "  skip  scan-output chown check (running as root)"
fi

# --- reporting ----------------------------------------------------------------------------------
echo "report"
now="$(date +%s)"
{
  echo "#$((now + 1))"; echo "mysql -u root -pSecret123 -h 10.10.10.9"
  echo "#$((now + 2))"; echo "xfreerdp /v:10.10.10.9 /u:admin /p:Passw0rd! /cert:ignore"
  echo "#$((now + 3))"; echo "smbclient //10.10.10.9/share -U 'admin%Passw0rd!'"
  echo "#$((now + 4))"; echo "evil-winrm -i 10.10.10.9 -u admin -p 'Passw0rd!'"
} >> smoke/.bash_history_smoke
"$MK" -r smoke > "$T/r1.out" 2>&1
R=smoke/report/smoke-report.md
check "report written"                   test -s "$R"
check "report is mode 600"               mode "$R" 600
check "evidence tarball written"         test -s smoke/report/smoke-evidence.tar.gz
check "tarball is mode 600"              mode smoke/report/smoke-evidence.tar.gz 600
check "tarball leaves creds/ out"        bash -c "! tar -tzf smoke/report/smoke-evidence.tar.gz | grep -q '^creds/'"
check "no secrets warning for addcred alone" bash -c "! grep -q 'WARNING: the password' '$T/r1.out'"
check "timeline: addcred masked"         has "$R" "addcred bob:***"
check "timeline: ssh port not masked"    has "$R" "ssh -p 2222 user@10.10.10.9"
check "timeline: sshpass masked"         has "$R" "sshpass -p *** ssh admin@10.10.10.9"
check "timeline: mysql -pPASS masked"    has "$R" "mysql -u root -p*** -h 10.10.10.9"
check "timeline: xfreerdp /p: masked"    has "$R" "/p:*** /cert:ignore"
check "timeline: smbclient -U masked"    has "$R" "-U 'admin%***'"
check "timeline: evil-winrm -p masked"   has "$R" "evil-winrm -i 10.10.10.9 -u admin -p ***"
check "no real password left in report"  bash -c "! grep -qE 'Secret123|Passw0rd|Sup3rSecret|Hunter2pw' '$R'"
"$MK" -r --creds smoke > /dev/null 2>&1
check "--creds puts creds/ in the tarball" bash -c "tar -tzf smoke/report/smoke-evidence.tar.gz | grep -q '^creds/creds.txt'"
echo "bob's password is Hunter2pw (oops)" >> smoke/notes/notes.md
"$MK" -r smoke > "$T/r2.out" 2>&1
check "leaked password in notes triggers a warning" has "$T/r2.out" "notes/notes.md"

# --- scratchpad + serve backends ----------------------------------------------------------------
echo "scratchpad"
"$MK" -p smoke add "check -foo flag on the upload form" > /dev/null 2>&1
"$MK" -p smoke cmd 'curl -s http://10.10.10.9/?x=1 | head' > /dev/null 2>&1
check "pad file is mode 600"             mode smoke/scratchpad.md 600
check "pad add stores text (dash ok)"    has smoke/scratchpad.md "check -foo flag on the upload form"
check "pad cmd stores a fenced command"  has smoke/scratchpad.md "curl -s http://10.10.10.9/?x=1 | head"
check "pad grep finds entries"           bash -c "'$MK' -p smoke grep UPLOAD | grep -q foo"
check "pad path prints the file"         bash -c "[ \"\$('$MK' -p smoke path)\" = \"$PWD/smoke/scratchpad.md\" ]"
"$MK" -r smoke > /dev/null 2>&1
check "pad is not in the evidence tarball" bash -c "! tar -tzf smoke/report/smoke-evidence.tar.gz | grep -q scratchpad"
check "pad on a non-box fails"           bash -c "! '$MK' -p nosuchbox show 2>/dev/null"
XDG_DATA_HOME="$T/xdg" "$MK" -p -g add "global note" > /dev/null 2>&1
check "global pad lives under XDG dir"   has "$T/xdg/mkbox/scratchpad.md" "global note"
printf '%s\n' 'echo first-cmd' 'pad cmd' 'pad add "from inside the shell"' 'exit' | "$MK" smoke > "$T/pad.out" 2>&1
check "in-shell: bare pad cmd saves previous command" has smoke/scratchpad.md "echo first-cmd"
check "in-shell: pad add works"          has smoke/scratchpad.md "from inside the shell"

echo "serve backends"
printf '%s\n' 'serve --smb --share loot --bind 10.10.14.2 4455' \
  'serve --smb --auth bob:pw1234' \
  'serve --webdav --bind 10.10.14.2 8080' \
  'serve --smb --share "bad share"' \
  'exit' | "$MK" smoke > "$T/serve.out" 2>&1
check "smb: share, port, bind passed"    has "$SERVE_LOG" "-smb2support -port 4455 -ip 10.10.14.2 loot $PWD/smoke/transfer"
check "smb: default port 445 + auth"     has "$SERVE_LOG" "-port 445 -username bob -password pw1234 share"
check "webdav: host/port/root passed"    has "$SERVE_LOG" "wsgidav --host 10.10.14.2 --port 8080 --root $PWD/smoke/transfer --auth anonymous"
check "smb: bad share name rejected"     has "$T/serve.out" "--share must be"

# --- re-entering vs typos -----------------------------------------------------------------------
echo "new vs existing"
printf 'exit\n' | "$MK" smoke > "$T/e1.out" 2>&1
printf 'exit\n' | "$MK" smok > "$T/e2.out" 2>&1
check "existing box: re-entering"        has "$T/e1.out" "re-entering 'smoke'"
check "typo: says creating new box"      has "$T/e2.out" "creating new box 'smok'"
check "typo: hints about setip"          has "$T/e2.out" "setip"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
