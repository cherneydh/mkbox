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
for tool in impacket-smbserver wsgidav python3; do
  # shellcheck disable=SC2016  # the stub script must expand $* and ${SERVE_LOG} when it runs, not now
  printf '#!/usr/bin/env bash\necho "%s $*" >> "${SERVE_LOG:-/dev/null}"\n' "$tool" > "$T/bin/$tool"
done
printf '#!/usr/bin/env bash\necho "stub ssh $*"\n' > "$T/bin/ssh"
# sshpass must not echo its arguments (the test password would then be "remote output")
printf '#!/usr/bin/env bash\necho "stub sshpass ran"\n' > "$T/bin/sshpass"
# nc: 50 lines of output, to exercise transcript truncation
printf '#!/usr/bin/env bash\nseq 1 50\n' > "$T/bin/nc"
# ip: knows one fact, our tun0 address, and only when FAKE_TUN0 is set (so most checks see "no VPN")
# shellcheck disable=SC2016  # the stub script must expand ${FAKE_TUN0} and ${6} when it runs, not now
printf '#!/usr/bin/env bash\n[ -n "${FAKE_TUN0:-}" ] && [ "${6:-}" = tun0 ] && echo "5: tun0    inet $FAKE_TUN0/23 scope global tun0"\nexit 0\n' > "$T/bin/ip"
# xclip: always "has" a minimal, valid PNG on the clipboard, so `shot`/`proofshot` can be tested
# without a real X11/Wayland session
printf '#!/usr/bin/env bash\nprintf "\\x89\\x50\\x4e\\x47\\x0d\\x0a\\x1a\\x0a"\n' > "$T/bin/xclip"
chmod +x "$T/bin/"*
export CHOWN_LOG="$T/chown.log"
export SERVE_LOG="$T/serve.log"

cd "$T/my labs" || exit 1

# --- basics -------------------------------------------------------------------------------------
echo "basics"
check "--version prints mkbox X.Y.Z"     bash -c "'$MK' --version | grep -Eq '^mkbox [0-9]+\.[0-9]+\.[0-9]+\$'"
"$MK" -n smoke 10.10.10.9 > "$T/n1.out" 2>&1
check "-n creates the box"               has "$T/n1.out" "Created"
check "-n on a new box says Happy Hacking" has "$T/n1.out" "Happy Hacking :)"
check "box layout exists"                test -d smoke/nmap -a -d smoke/screenshots -a -f smoke/notes/notes.md
check ".gitignore is just *"             test "$(cat smoke/.gitignore)" = '*'
check "new box dir is private (700)"     mode smoke 700
check "box.env remembers the IP"         has smoke/box.env "10.10.10.9"
"$MK" -n smoke > "$T/n2.out" 2>&1
check "-n on an existing box says so"    has "$T/n2.out" "already exists"
check "existing box: no greeting"        bash -c "! grep -q 'Happy Hacking' '$T/n2.out'"
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
  'nc 10.10.10.9 80' \
  'markproof local 0123abcd' \
  'markproof root' \
  'markproof bogus' \
  'exit' | FAKE_TUN0=10.10.14.7 "$MK" smoke 10.10.10.9 > "$T/session.out" 2>&1
check "banner says re-entering"          has "$T/session.out" "re-entering 'smoke'"
# shellcheck disable=SC2016  # literal text: the banner prints the characters $LHOST=
check "banner shows our tun0 address"    has "$T/session.out" '= 10.10.14.7'
check "markproof: local ticked with value" has smoke/notes/notes.md "- [x] local.txt: 0123abcd"
check "markproof: root is an alias for proof" has smoke/notes/notes.md "- [x] proof.txt:"

# $TARGET/$LOCAL: friendlier aliases for $IP/$LHOST, so a command typed mid-engagement doesn't
# need either memorized or retyped - must track $IP/$LHOST exactly, including through setip
# shellcheck disable=SC2016  # single quotes on purpose: the box shell must expand $TARGET/$LOCAL, not this script
printf '%s\n' \
  'echo "T1=$TARGET L1=$LOCAL"' \
  'setip 10.10.10.55' \
  'echo "T2=$TARGET"' \
  'exit' | FAKE_TUN0=10.10.14.7 "$MK" smoke > "$T/aliases.out" 2>&1
check "\$TARGET starts out equal to \$IP"        has "$T/aliases.out" "T1=10.10.10.9"
check "\$LOCAL starts out equal to \$LHOST"      has "$T/aliases.out" "L1=10.10.14.7"
check "\$TARGET follows setip immediately"       has "$T/aliases.out" "T2=10.10.10.55"
printf '%s\n' 'boxinfo' 'exit' | FAKE_TUN0=10.10.14.7 "$MK" smoke > "$T/aliases2.out" 2>&1
check "boxinfo: mentions \$TARGET alias"         has "$T/aliases2.out" "(also \$TARGET)"
check "boxinfo: mentions \$LOCAL alias"          has "$T/aliases2.out" "(also \$LOCAL)"
check "markproof: timeline note"         has smoke/notes/timeline.md "proof: local.txt marked done (0123abcd)"
check "markproof: bad argument gives usage" has "$T/session.out" "usage: markproof local|proof"
check "markproof: notes.md keeps its mode" bash -c "[ \"\$(stat -c %a smoke/notes/notes.md)\" != 600 ]"
check "-l counts both proof lines"       bash -c "'$MK' -l | grep -q '^smoke .*2/2'"
printf '%s\n' 'markproof -u local' 'exit' | "$MK" smoke > /dev/null 2>&1
check "markproof -u: unticked, value kept" has smoke/notes/notes.md "- [ ] local.txt: 0123abcd"
check "markproof -u: timeline note"      has smoke/notes/timeline.md "proof: local.txt unmarked"
printf '%s\n' 'markproof local' 'exit' | "$MK" smoke > /dev/null 2>&1
check "markproof: re-tick keeps old value" has smoke/notes/notes.md "- [x] local.txt: 0123abcd"
check "portscan set \$PORTS"             has smoke/notes/timeline.md "portscan: open ports 22,80"
# shellcheck disable=SC2016  # the single quotes are intentional: the inner bash expands $PORTS
check "ports shared via box.env"         bash -c '. smoke/box.env && [ "$PORTS" = "22,80" ]'
check "svcscan ran"                      test -f smoke/nmap/services.nmap
check "addcred: timeline has username"   has smoke/notes/timeline.md "cred recorded for bob"
check "addcred: timeline has no password" lacks smoke/notes/timeline.md "Hunter2pw"
check "creds.txt holds the password"     has smoke/creds/creds.txt "bob:Hunter2pw"
check "creds.txt is mode 600"            mode smoke/creds/creds.txt 600

# creds: lists what addcred recorded, and prints a ready-to-paste command block for one of them -
# closes the "copy the password out of a file by hand" gap the same way proofshot already did for
# the flag text. Its own dedicated box, not "smoke" - typing a password into this box's shell is
# exactly what trips the leaked-password warning checked elsewhere, and that check is pinned to
# "smoke" having exactly the one cred added to it earlier in this file.
"$MK" -n credsbox 10.10.10.62 > /dev/null 2>&1
printf '%s\n' 'addcred admin:Winter2026! rdp' 'addcred svc:Sup3rS3cr3t smb share' 'creds' 'creds 2' 'creds 99' 'exit' \
  | "$MK" credsbox > "$T/creds.out" 2>&1
check "creds: lists recorded entries with an index"   has "$T/creds.out" "1) "
check "creds: lists the second entry too"             has "$T/creds.out" "2) "
check "creds: per-entry view names the right user"    has "$T/creds.out" "Cred #2: svc : Sup3rS3cr3t"
check "creds: per-entry view gives an evil-winrm line" has "$T/creds.out" "evil-winrm -i \$TARGET -u 'svc' -p 'Sup3rS3cr3t'"
check "creds: per-entry view gives an smb line"        has "$T/creds.out" "smbclient -U 'svc%Sup3rS3cr3t'"
check "creds: unknown index errors instead of guessing" has "$T/creds.out" "no entry #99"
check "creds: with nothing recorded, says so"          bash -c "
  '$MK' -n credsnobody 10.10.10.61 >/dev/null 2>&1
  printf 'creds\nexit\n' | '$MK' credsnobody 2>&1 | grep -q 'nothing recorded yet'"
rm -rf credsbox credsnobody

# sethost: adds an /etc/hosts-style line for a domain name, idempotently, without clobbering a
# conflicting existing entry - exercised against a throwaway MKBOX_HOSTS_FILE, never the real
# /etc/hosts (this is a test suite, not something that should ever touch the machine it runs on).
# Its own dedicated box, so its IP is never in question even if an earlier test in this file
# reassigned "smoke"'s via setip.
"$MK" -n sethostbox 10.10.10.63 > /dev/null 2>&1
FAKE_HOSTS="$T/fake-hosts"
: > "$FAKE_HOSTS"
printf '%s\n' 'sethost dc01.corp.local corp.local' 'exit' \
  | MKBOX_HOSTS_FILE="$FAKE_HOSTS" "$MK" sethostbox > "$T/sethost1.out" 2>&1
check "sethost: confirms what it added"        has "$T/sethost1.out" "added '10.10.10.63  dc01.corp.local corp.local'"
check "sethost: actually wrote the fake hosts file" has "$FAKE_HOSTS" "10.10.10.63	dc01.corp.local corp.local"
printf '%s\n' 'sethost dc01.corp.local' 'exit' \
  | MKBOX_HOSTS_FILE="$FAKE_HOSTS" "$MK" sethostbox > "$T/sethost2.out" 2>&1
check "sethost: re-adding the same mapping is a no-op, not a duplicate" has "$T/sethost2.out" "already in"
check "sethost: no duplicate line was written"  bash -c "[ \"\$(grep -c 'dc01.corp.local' '$FAKE_HOSTS')\" -eq 1 ]"
printf '%s\n' 'sethost dc01.corp.local --ip=9.9.9.9' 'exit' \
  | MKBOX_HOSTS_FILE="$FAKE_HOSTS" "$MK" sethostbox > "$T/sethost3.out" 2>&1
check "sethost: a conflicting existing mapping is reported, not overwritten" has "$T/sethost3.out" "pointing somewhere else"
check "sethost: the conflicting line is still the original one"             has "$FAKE_HOSTS" "10.10.10.63	dc01.corp.local corp.local"
check "sethost: no IP available gives a clear error" bash -c "
  '$MK' -n sethostnoip >/dev/null 2>&1
  printf 'sethost somedomain.local\nexit\n' | MKBOX_HOSTS_FILE='$T/fake-hosts2' '$MK' sethostnoip 2>&1 | grep -q \"isn't set\""
rm -rf sethostbox sethostnoip
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
  echo "#$((now + 5))"; echo "serve --smb --share loot --auth bob:Sm8Secret"
  echo "#$((now + 6))"; echo "serve --smb --auth='carl:Qu0tedPw'"
  echo "#$((now + 7))"; echo "markproof local deadbeef"
} >> smoke/.bash_history_smoke
"$MK" -r smoke > "$T/r1.out" 2>&1
R=smoke/report/smoke-report.md
check "report written"                   test -s "$R"
check "timeline: markproof command left out" lacks "$R" "deadbeef"
check "summary: open TCP ports"          has "$R" "- **Open TCP ports:** 22,80"
check "summary: no tun0 -> attacker unknown" has "$R" "- **Attacker (this machine):** unknown"
# shellcheck disable=SC2016  # the backticks are literal markdown in the report, not a command substitution
check "summary: local.txt value filled in" has "$R" '- **local.txt:** captured (`0123abcd`)'
check "summary: proof.txt captured"      has "$R" "- **proof.txt:** captured"
check "ports table: header"              has "$R" "| Port | Proto | Service | Version |"
check "ports table: ssh row"             has "$R" "| 22 | tcp | ssh | - |"
check "ports table: http row"            has "$R" "| 80 | tcp | http | - |"
FAKE_TUN0=10.10.14.7 "$MK" -r smoke > /dev/null 2>&1
check "summary: attacker = tun0 address" has "$R" "- **Attacker (this machine):** 10.10.14.7"
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
check "timeline: serve --auth masked"    has "$R" "serve --smb --share loot --auth bob:***"
check "timeline: serve --auth= quoted masked" has "$R" "serve --smb --auth='carl:***'"
check "no real password left in report"  bash -c "! grep -qE 'Secret123|Passw0rd|Sup3rSecret|Hunter2pw|Sm8Secret|Qu0tedPw' '$R'"
check "transcript: ssh block labelled"   has "$R" "**[ssh session transcript]** (until "
check "transcript: ssh output captured"  has "$R" "stub ssh -p 2222 user@10.10.10.9"
check "transcript: sshpass block labelled" has "$R" "**[sshpass session transcript]**"
check "transcript: nc block labelled"    has "$R" "**[nc session transcript]**"
check "transcript: nc output present"   bash -c "grep -qx '50' '$R'"
check "transcript: exit code shown"      has "$R" ", exit 0)"
check "transcript: markers not in report text" bash -c "! grep -q '\[mkbox >>>' '$R'"
"$MK" -r --creds smoke > /dev/null 2>&1
check "--creds puts creds/ in the tarball" bash -c "tar -tzf smoke/report/smoke-evidence.tar.gz | grep -q '^creds/creds.txt'"
MKBOX_TRANSCRIPT_LINES=10 "$MK" -r smoke > /dev/null 2>&1
check "transcript: long output is shortened" has "$R" "lines omitted"
check "transcript: shortened keeps the ends" bash -c "grep -qx '1' '$R' && grep -qx '50' '$R' && ! grep -qx '25' '$R'"
MKBOX_TRANSCRIPT_LINES=0 "$MK" -r smoke > /dev/null 2>&1
check "transcript: 0 = never shortened"  bash -c "grep -qx '25' '$R' && ! grep -q 'lines omitted' '$R'"
# a connection whose end marker never reached the log (terminal closed mid-session)
printf '[mkbox >>> ssh started 2020-01-01 00:00:01]\r\nlost connection output\r\n' > smoke/.sessions/20200101-000000-1.raw
"$MK" -r smoke > /dev/null 2>&1
check "transcript: unfinished connection noted" has "$R" "the log ended before the connection did"
check "transcript: unfinished text kept"  has "$R" "lost connection output"
rm -f smoke/.sessions/20200101-000000-1.raw
"$MK" -c smoke > /dev/null 2>&1
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
  'serve --webdav --auth a:b' \
  'serve --http 8000' \
  'serve --smb --share "bad share"' \
  'exit' | "$MK" smoke > "$T/serve.out" 2>&1
check "smb: share, port, bind passed"    has "$SERVE_LOG" "-smb2support -port 4455 -ip 10.10.14.2 loot $PWD/smoke/transfer"
check "smb: default port 445 + auth"     has "$SERVE_LOG" "-port 445 -username bob -password pw1234 share"
check "webdav: host/port/root passed"    has "$SERVE_LOG" "wsgidav --host 10.10.14.2 --port 8080 --root $PWD/smoke/transfer --auth anonymous"
check "smb: bad share name rejected"     has "$T/serve.out" "--share must be"
check "serve timeline: smb start note"   has smoke/notes/timeline.md "serve: smb started (port 4455, bind 10.10.14.2, share loot)"
check "serve timeline: webdav start note" has smoke/notes/timeline.md "serve: webdav started (port 8080, bind 10.10.14.2)"
check "serve timeline: user, no password" has smoke/notes/timeline.md "serve: smb started (port 445, share share, user bob)"
check "serve timeline: password not logged" lacks smoke/notes/timeline.md "pw1234"
check "serve timeline: end note"         has smoke/notes/timeline.md "serve: smb ended (exit 0"
check "hint: smb copy line"              has "$T/serve.out" 'copy \\10.10.14.2\loot\FILE .'
check "hint: smb net use with user"      has "$T/serve.out" 'net use \\<your-ip>\share /user:bob <password>'
check "hint: webdav DavWWWRoot + port"   has "$T/serve.out" 'copy \\10.10.14.2@8080\DavWWWRoot\FILE .'
check "http: python http.server, port"   has "$SERVE_LOG" "python3 -m http.server 8000"
check "hint: http wget/certutil"         has "$T/serve.out" "certutil -urlcache -split -f http://<your-ip>:8000/FILE FILE"
check "serve --auth needs --smb"         has "$T/serve.out" "--auth is only supported with --smb"

# --- exploit provenance, AD pivot chain, proof-missing warning, proofshot -----------------------
echo "exploit provenance + pivot chain + proof warnings"
mkdir -p smoke/exploits
echo '#!/usr/bin/env python3' > smoke/exploits/cve-2021-9999.py
printf '%s\n' \
  'addexploit cve-2021-9999.py https://example.com/exploit-db/9999 "changed LHOST/LPORT, fixed offset for 8.2"' \
  'pivot DC01 "psexec with bob:ntlm-hash"' \
  'pivot FILE02 "smb relay via DC01"' \
  'exit' | "$MK" smoke > "$T/prov.out" 2>&1
check "addexploit: timeline note"         has smoke/notes/timeline.md "exploit recorded: cve-2021-9999.py (source: https://example.com/exploit-db/9999)"
check "addexploit: SOURCES.md has source" has smoke/exploits/SOURCES.md "https://example.com/exploit-db/9999"
check "addexploit: SOURCES.md has mods"   has smoke/exploits/SOURCES.md "changed LHOST/LPORT, fixed offset for 8.2"
check "pivot: first hop recorded"         has smoke/notes/timeline.md "pivot -> DC01 via psexec with bob:ntlm-hash"
check "pivot: second hop recorded"        has smoke/notes/timeline.md "pivot -> FILE02 via smb relay via DC01"
check "pivot: confirms to the terminal"   has "$T/prov.out" "pivot recorded: -> DC01 via psexec with bob:ntlm-hash"
"$MK" -r smoke > /dev/null 2>&1
R=smoke/report/smoke-report.md
check "report: exploit source shown"      has "$R" "https://example.com/exploit-db/9999"
check "report: exploit modification shown" has "$R" "changed LHOST/LPORT, fixed offset for 8.2"
check "report: exploit file still listed" has "$R" "cve-2021-9999.py"
check "report: SOURCES.md excluded from file bullet list" bash -c "! grep -qx '- SOURCES.md' '$R'"
check "report: pivot chain section"       has "$R" "## Pivot chain"
check "report: pivot chain first hop"     has "$R" "pivot -> DC01 via psexec with bob:ntlm-hash"
check "report: pivot chain second hop"    has "$R" "pivot -> FILE02 via smb relay via DC01"
check "timeline: addexploit command shown (mod text only lives there)" has "$R" '$ addexploit cve-2021-9999.py https://example.com/exploit-db/9999 "changed LHOST/LPORT, fixed offset for 8.2"'
check "timeline: pivot command not duplicated"    bash -c "! grep -q '\\\$ pivot DC01' '$R'"

"$MK" -n nopro 10.10.10.50 > /dev/null 2>&1
"$MK" -r nopro > "$T/nopro.out" 2>&1
check "proof warning: fires when nothing is marked" has "$T/nopro.out" "WARNING: not yet marked done: local.txt proof.txt"
printf '%s\n' 'markproof local aaa' 'markproof proof bbb' 'exit' | "$MK" nopro > /dev/null 2>&1
"$MK" -r nopro > "$T/nopro2.out" 2>&1
check "proof warning: clears once both are marked" bash -c "! grep -q 'WARNING: not yet marked' '$T/nopro2.out'"

"$MK" -n shotbox 10.10.10.51 > /dev/null 2>&1
printf '%s\n' 'proofshot local cafebabe' 'proofshot bogus' 'exit' | "$MK" shotbox > "$T/proofshot.out" 2>&1
check "proofshot: screenshot file created"  bash -c "compgen -G 'shotbox/screenshots/*.png' >/dev/null"
check "proofshot: caption recorded"       has shotbox/screenshots/captions.tsv "local.txt proof (cafebabe)"
check "proofshot: notes.md ticked"        has shotbox/notes/notes.md "- [x] local.txt: cafebabe"
check "proofshot: timeline has the mark"  has shotbox/notes/timeline.md "proof: local.txt marked done (cafebabe)"
check "proofshot: bad arg gives usage"    has "$T/proofshot.out" "usage: proofshot local|proof"
check "proofshot: bad-arg usage clarifies the flag text is optional" has "$T/proofshot.out" "optional"
"$MK" -r shotbox > /dev/null 2>&1
check "timeline: proofshot command not duplicated" bash -c "! grep -q '\\\$ proofshot local' 'shotbox/report/shotbox-report.md'"

# proofshot with no flag text at all still ticks the checklist - the UX fix is that this is
# actually all that's required; nothing to copy out of the target's output first
"$MK" -n shotbox2 10.10.10.52 > /dev/null 2>&1
printf '%s\n' 'proofshot local' 'exit' | "$MK" shotbox2 > "$T/proofshot2.out" 2>&1
check "proofshot with no flag text: still ticks the checklist" has shotbox2/notes/notes.md "- [x] local.txt:"
check "proofshot with no flag text: screenshot still saved"    bash -c "compgen -G 'shotbox2/screenshots/*.png' >/dev/null"

# the proof workflow hint shows up where a student would actually look for it: proofcmd's own
# output, and the box shell's startup banner
printf '%s\n' 'proofcmd' 'exit' | "$MK" shotbox2 > "$T/proofcmd.out" 2>&1
check "proofcmd: ends with the proofshot next-step hint" has "$T/proofcmd.out" "proofshot local|proof"
printf 'exit\n' | "$MK" shotbox2 > "$T/banner.out" 2>&1
check "startup banner: shows the one-line proof workflow" has "$T/banner.out" "screenshot it (clipboard) -> proofshot local|proof"

# --- addvuln ------------------------------------------------------------------------------------
echo "addvuln"
cat > "$T/bin/fake-editor" <<'STUB'
#!/usr/bin/env bash
sed -i \
  -e 's/(what the vulnerability is, and why this target is affected)/SMB share allowed anonymous read access to a password file./' \
  -e 's/(the concrete remediation)/Disable anonymous\/guest SMB access./' \
  "$1"
STUB
chmod +x "$T/bin/fake-editor"
EDITOR="$T/bin/fake-editor" printf '%s\n' \
  'addvuln initial "Anonymous SMB share leads to WordPress RCE" critical' \
  'addvuln privesc "AlwaysInstallElevated" high' \
  'addvuln bogus "x" critical' \
  'addvuln initial "x" bogus' \
  'exit' | env EDITOR="$T/bin/fake-editor" "$MK" smoke > "$T/vuln.out" 2>&1
check "addvuln: two files created"        bash -c "[ \$(find smoke/vulns -maxdepth 1 -name '*.md' | wc -l) -eq 2 ]"
check "addvuln: numbered and phase-named" bash -c "ls smoke/vulns/01-initial-*.md smoke/vulns/02-privesc-*.md >/dev/null"
check "addvuln: explanation written"      bash -c "grep -ql 'password file' smoke/vulns/01-*.md"
check "addvuln: fix written"              bash -c "grep -ql 'Disable anonymous' smoke/vulns/01-*.md"
check "addvuln: severity stored lowercase" has smoke/vulns/02-privesc-alwaysinstallelevated.md "Severity: high"
check "addvuln: timeline note"            has smoke/notes/timeline.md "vuln recorded: [initial] Anonymous SMB share leads to WordPress RCE (critical)"
check "addvuln: bad phase gives usage"    has "$T/vuln.out" "usage: addvuln initial|privesc|post"
check "addvuln: bad severity gives usage" bash -c "grep -c 'usage: addvuln' '$T/vuln.out' | grep -q 2"
"$MK" -r smoke > "$T/smoke-report.out" 2>&1
R=smoke/report/smoke-report.md
check "report: Findings section"            has "$R" "## Findings"
check "report: initial access heading"       has "$R" "### Initial Access - Anonymous SMB share leads to WordPress RCE"
check "report: privesc heading, after initial" bash -c "grep -n 'Initial Access -' '$R' | cut -d: -f1 > $T/i.n; grep -n 'Privilege Escalation -' '$R' | cut -d: -f1 > $T/p.n; [ \"\$(cat $T/i.n)\" -lt \"\$(cat $T/p.n)\" ]"
check "report: severity shown"               has "$R" "**Severity:** Critical"
check "timeline: addvuln command not duplicated" bash -c "! grep -q '\\\$ addvuln initial' '$R'"
check "report: blank line before Notes (no literal #### from a missing one)" bash -c "! grep -q '####' '$R'"
check "report: findings separated by a rule" bash -c "grep -n '^---\$' '$R' | cut -d: -f1 > $T/sep.n; grep -n 'Initial Access -' '$R' | cut -d: -f1 > $T/i2.n; grep -n 'Privilege Escalation -' '$R' | cut -d: -f1 > $T/p2.n; [ \"\$(cat $T/i2.n)\" -lt \"\$(cat $T/sep.n)\" ] && [ \"\$(cat $T/sep.n)\" -lt \"\$(cat $T/p2.n)\" ]"

# an addvuln entry whose template text was never actually edited (EDITOR=true is a no-op) should be
# caught at report time, the same way an unmarked proof checklist item is
"$MK" -n unfilled 10.9.9.9 > /dev/null 2>&1
printf 'addvuln initial "Left blank by mistake" high\nexit\n' | EDITOR=true "$MK" unfilled > /dev/null 2>&1
"$MK" -r unfilled > "$T/unfilled.out" 2>&1
check "addvuln left unfilled: caught by mkbox -r" has "$T/unfilled.out" "WARNING: addvuln entries still have unfilled template text"
check "addvuln left unfilled: names the file"     bash -c "grep 'WARNING: addvuln' '$T/unfilled.out' | grep -q '01-initial-left-blank-by-mistake.md'"
check "addvuln filled in: no false positive"      bash -c "! grep -q 'WARNING: addvuln entries' '$T/smoke-report.out'"

# --- setad / --ad / mkbox -a assemble ------------------------------------------------------------
echo "setad + --ad + mkbox -a"
"$MK" -n ad-dc 10.5.5.30 --ad > /dev/null 2>&1
"$MK" -n ad-file 10.5.5.20 > /dev/null 2>&1
printf 'setad on\npivot ad-dc "golden ticket, krbtgt hash"\nexit\n' | "$MK" ad-file > "$T/adfile.out" 2>&1
check "--ad at creation: boxinfo shows it"  bash -c "printf 'boxinfo\nexit\n' | '$MK' ad-dc 2>&1 | grep -q 'AD set: yes'"
check "setad on: boxinfo shows it"          bash -c "printf 'boxinfo\nexit\n' | '$MK' ad-file 2>&1 | grep -q 'AD set: yes'"
check "setad on: confirms to the terminal"  has "$T/adfile.out" "AD_SET=1"
check "setad bad arg gives usage"           bash -c "printf 'setad bogus\nexit\n' | '$MK' ad-file 2>&1 | grep -q 'usage: setad on|off'"
check "box never flagged: no AD set line"   bash -c "! (printf 'boxinfo\nexit\n' | '$MK' smoke 2>&1 | grep -q 'AD set')"

"$MK" -a "$T/assembled.md" smoke ad-dc ad-file unfilled > "$T/assemble.out" 2>&1
A="$T/assembled.md"
check "assemble: confirms the draft path"      has "$T/assemble.out" "Assembled draft: $T/assembled.md"
check "assemble: surfaces a box's own warning instead of swallowing it" has "$T/assemble.out" "Carried over from each box's own report"
check "assemble: warning is prefixed with the box name"                has "$T/assemble.out" "unfilled: WARNING: addvuln entries still have unfilled template text"
check "assemble: box with filled-in findings has no addvuln warning"   bash -c "! grep -q 'smoke: WARNING: addvuln' '$T/assemble.out'"
check "assemble: Independent Challenges section" has "$A" "# Independent Challenges"
check "assemble: Active Directory Set section"   has "$A" "# Active Directory Set"
check "assemble: standalone box nested as Target" has "$A" "## Target #1 - "
check "assemble: AD box uses its own name, not Target" has "$A" "## ad-dc - 10.5.5.30"
check "assemble: combined AD ports table header"  has "$A" "| IP Address | Ports Open |"
check "assemble: combined AD ports table row"     has "$A" "| 10.5.5.30 |"
check "assemble: pivot chain carried through"      has "$A" "pivot -> ad-dc via golden ticket, krbtgt hash"
check "assemble: findings carried through (bold, past the heading-depth cap)" has "$A" "**Initial Access - Anonymous SMB share leads to WordPress RCE**"
check "assemble: no literal #### anywhere"         bash -c "! grep -q '^####' '$A'"
check "assemble: box's own H1 title dropped"       bash -c "! grep -q '^# smoke - report draft' '$A'"
check "assemble: unfilled notes section flagged"   has "$A" "_(nothing recorded)_"
check "assemble: TODO stubs present"               has "$A" "TODO: A short, non-technical paragraph"
check "assemble: no outfile given gives usage"     bash -c "'$MK' -a 2>&1 | grep -q 'usage: mkbox -a'"
check "assemble: no boxes given gives usage"       bash -c "'$MK' -a '$T/x.md' 2>&1 | grep -q 'usage: mkbox -a'"
check "assemble: unknown box errors out"           bash -c "! '$MK' -a '$T/x.md' not-a-real-box 2>/dev/null"

# readiness check: smoke/ad-dc/ad-file/unfilled all have zero screenshots, so every one of them
# should get a "no screenshots recorded" note; only smoke has real findings (ad-dc/ad-file have
# none, unfilled's one addvuln entry still counts as a findings file even though it's unfilled)
check "assemble: readiness heading present"            has "$T/assemble.out" "Readiness check"
check "assemble: readiness flags smoke for no screenshots" has "$T/assemble.out" "smoke: no screenshots recorded"
check "assemble: readiness flags ad-dc for no findings"    has "$T/assemble.out" "ad-dc: no findings recorded"
check "assemble: readiness flags ad-file for no findings"  has "$T/assemble.out" "ad-file: no findings recorded"
check "assemble: readiness does not flag smoke for findings (it has some)" bash -c "! grep -q 'smoke: no findings' '$T/assemble.out'"
check "assemble: readiness does not flag unfilled for findings (file exists)" bash -c "! grep -q 'unfilled: no findings' '$T/assemble.out'"

# screenshot path fix: give shotbox a recorded screenshot (already created by the proofshot checks
# above), assemble it alone, and confirm its image reference becomes an absolute path pointing at
# shotbox's own screenshots/ dir rather than the broken "../screenshots/..." relative one
"$MK" -a "$T/assembled-shot.md" shotbox > "$T/assemble-shot.out" 2>&1
check "assemble: readiness does not flag shotbox for no screenshots" bash -c "! grep -q 'shotbox: no screenshots' '$T/assemble-shot.out'"
check "assemble: screenshot path rewritten to an absolute path" bash -c "
  grep -oE '\]\([^)]*screenshots/[^)]*\)' '$T/assembled-shot.md' | head -1 | grep -q \"\$(cd shotbox && pwd)/screenshots\""
check "assemble: screenshot path no longer relative"            bash -c "! grep -q '](\.\./screenshots/' '$T/assembled-shot.md'"

if command -v pandoc >/dev/null 2>&1; then
  TPL="$T/fake-template.odt"
  REALPYTHON3="$(PATH="${PATH#*:}" command -v python3)"   # python3 itself is stubbed above; skip past it
  "$REALPYTHON3" -I -c "
import zipfile
with zipfile.ZipFile('$TPL', 'w') as z:
    z.writestr('mimetype', 'application/vnd.oasis.opendocument.text', compress_type=zipfile.ZIP_STORED)
    z.writestr('content.xml', '<?xml version=\"1.0\"?><office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\"><office:body><office:text/></office:body></office:document-content>')
    z.writestr('styles.xml', '<?xml version=\"1.0\"?><office:document-styles xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\"><office:styles><style:style style:name=\"Heading1\" style:family=\"paragraph\"/><style:style style:name=\"Heading2\" style:family=\"paragraph\"/><style:style style:name=\"Heading3\" style:family=\"paragraph\"/></office:styles></office:document-styles>')
"
  # mkbox's own ODT post-processing shells out to python3 too; our "python3" stub above (for the
  # serve-backend tests) would otherwise swallow that call silently. Put the real one first for
  # these checks only, then put the stub back on top.
  REALPY_DIR="$(dirname -- "$REALPYTHON3")"
  PATH="$REALPY_DIR:$PATH" "$MK" -a "$T/assembled2.md" --odt="$TPL" smoke ad-dc ad-file > "$T/assemble2.out" 2>&1
  check "assemble --odt: ODT file produced"   bash -c "[ -s '$T/assembled2.odt' ]"
  check "assemble --odt: confirms the path"   has "$T/assemble2.out" "ODT draft:"
  check "assemble --odt: heading style patched to template's own naming" bash -c "
    cd '$T' && rm -rf odtcheck && mkdir odtcheck && cd odtcheck && unzip -o -q ../assembled2.odt content.xml
    grep -q 'text:style-name=\"Heading1\"' content.xml"
  check "assemble --odt: proof checklist is plain text, not a checkbox glyph" bash -c "
    cd '$T/odtcheck' && grep -q '\[x\] local.txt' content.xml"
  check "assemble --odt: no --osid given means no OSID line on the cover page" bash -c "
    ! grep -q 'OSID:' '$T/odtcheck/content.xml'"
  check "assemble --odt: a custom template without MkboxPageBreak still gets one patched in" bash -c "
    cd '$T' && rm -rf odtcheck2 && mkdir odtcheck2 && cd odtcheck2 && unzip -o -q ../assembled2.odt styles.xml
    grep -q 'style:name=\"MkboxPageBreak\"' styles.xml"
  check "assemble --odt: outfile.md itself has no YAML/raw-ODT cover-page clutter" bash -c "
    ! grep -q 'opendocument' '$T/assembled2.md'"

  # with no --odt=path and no \$MKBOX_ODT_TEMPLATE, mkbox now falls back to its own bundled
  # templates/mkbox-default.odt instead of erroring out - this is the main point of this round
  PATH="$REALPY_DIR:$PATH" "$MK" -a "$T/assembled3.md" --odt --author="Jane Q. Tester" --osid=OS12345 smoke > "$T/assemble3.out" 2>&1
  check "assemble --odt, no template: uses the bundled default instead of erroring" bash -c "[ -s '$T/assembled3.odt' ]"
  check "assemble --odt, no template: says so"                                     has "$T/assemble3.out" "bundled template"
  rm -rf "$T/odtcheck3" && mkdir "$T/odtcheck3" && (cd "$T/odtcheck3" && unzip -o -q ../assembled3.odt)
  check "assemble --odt (default template): cover page has the author"    has "$T/odtcheck3/content.xml" "Jane Q. Tester"
  check "assemble --odt (default template): cover page has the OSID"      has "$T/odtcheck3/content.xml" "OSID: OS12345"
  check "assemble --odt (default template): cover page has today's date" has "$T/odtcheck3/content.xml" "$(date '+%Y-%m-%d')"
  check "assemble --odt (default template): a real TOC field is present" has "$T/odtcheck3/content.xml" "text:table-of-content"
  check "assemble --odt (default template): forced page breaks present" bash -c "grep -c 'MkboxPageBreak' '$T/odtcheck3/content.xml' | grep -qv '^0$'"
  # layout/attribute-order independent: pandoc versions differ in how they re-serialize styles.xml
  check "assemble --odt (default template): decimal outline numbering"  bash -c "
    tr '\n' ' ' < '$T/odtcheck3/styles.xml' |
      grep -Eq '<text:outline-level-style[^>]*(text:level=\"1\"[^>]*style:num-format=\"1\"|style:num-format=\"1\"[^>]*text:level=\"1\")'"
  MKBOX_VER="$("$MK" -V | awk '{print $2}')"
  check "assemble: Tools Used section present"           has "$T/assembled3.md" "## Tools Used"
  check "assemble: Tools Used section names mkbox itself" has "$T/assembled3.md" "\`mkbox\` v$MKBOX_VER"
  check "assemble: Tools Used links the repo"             has "$T/assembled3.md" "github.com/cherneydh/mkbox"

  # --pdf: only exercised when this machine actually has a uno-capable python and soffice (same as
  # a student's exam VM normally would, since LibreOffice ships both); --pdf degrades gracefully
  # without them (checked separately below), so there's nothing to skip here either way.
  if PATH="$REALPY_DIR:$PATH" command -v soffice >/dev/null 2>&1 && \
     PATH="$REALPY_DIR:$PATH" python3 -c 'import uno' >/dev/null 2>&1; then
    PATH="$REALPY_DIR:$PATH" "$MK" -a "$T/assembled4.md" --pdf --author="PDF Tester" smoke > "$T/assemble4.out" 2>&1
    check "assemble --pdf: PDF file produced"        bash -c "[ -s '$T/assembled4.pdf' ]"
    check "assemble --pdf: ODT file also produced"   bash -c "[ -s '$T/assembled4.odt' ]"
    check "assemble --pdf: confirms the PDF path"    has "$T/assemble4.out" "PDF draft:"
    if command -v pdftotext >/dev/null 2>&1; then
      pdftotext "$T/assembled4.pdf" "$T/assembled4.pdf.txt" 2>/dev/null
      check "assemble --pdf: TOC has a real, non-zero page number, not a placeholder" bash -c "
        grep -A1 'Table of Contents' '$T/assembled4.pdf.txt' | grep -Eq '\.{3,}[[:space:]]*[1-9][0-9]*[[:space:]]*\$|[1-9][0-9]*\$'"
    fi
  else
    echo "  skip  --pdf checks (no uno-capable python3 and/or soffice on this machine)"
  fi
  # --pdf without a working soffice still has to degrade to "the ODT is fine, here's how to finish
  # it by hand" instead of failing outright. $T/bin is first on PATH (set at the top of this
  # script), so a do-nothing stub placed there shadows the real soffice found later on PATH -
  # modeling "soffice is present but can't actually serve a UNO connection" (a locked-down exam VM,
  # a half-broken install, etc.), which is the same degrade path as soffice being entirely missing.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/soffice"
  chmod +x "$T/bin/soffice"
  "$MK" -a "$T/assembled5.md" --pdf smoke > "$T/assemble5.out" 2>&1
  rm -f "$T/bin/soffice"
  check "assemble --pdf, broken soffice: still produces the ODT"      bash -c "[ -s '$T/assembled5.odt' ]"
  check "assemble --pdf, broken soffice: degrades instead of failing" has "$T/assemble5.out" "ODT draft:"
  check "assemble --pdf, broken soffice: explains why there's no PDF" bash -c "grep -q 'LibreOffice' '$T/assemble5.out'"
  check "assemble --pdf, broken soffice: no PDF file left behind"     bash -c "[ ! -e '$T/assembled5.pdf' ]"

  # a template that already carries its own MkboxPageBreak (mkbox's own bundled one) shouldn't be
  # rewritten by fix_odt_heading_styles just to re-add a style that's already there
  DEFAULT_TPL="$(cd "$(dirname -- "$MK")" && pwd)/templates/mkbox-default.odt"
  if [ -f "$DEFAULT_TPL" ]; then
    check "bundled template ships inside the repo" bash -c "[ -s '$DEFAULT_TPL' ]"
  fi
else
  echo "  skip  --odt checks (pandoc not installed)"
fi

# --- in-shell "boxes" / "assemble" helpers -------------------------------------------------------
# The whole point of these two is "don't make the student leave a box's shell, retype every box
# name, and re-remember every flag just to update the combined report" - exercise them exactly as
# a student would: from inside one box's interactive shell, by name alone.
echo "in-shell boxes/assemble helpers"
printf '%s\n' 'boxes' 'exit' | "$MK" smoke > "$T/shellboxes.out" 2>&1
check "boxes: lists this box"             has "$T/shellboxes.out" "smoke"
check "boxes: lists a sibling box too"    has "$T/shellboxes.out" "ad-dc"
check "boxes: same table mkbox -l prints" has "$T/shellboxes.out" "BOX"

printf '%s\n' 'assemble' 'exit' | "$MK" smoke > "$T/shellassemble1.out" 2>&1
check "assemble (in-shell): names every sibling box, not just this one" bash -c "
  grep -q 'Assembling' '$T/shellassemble1.out' &&
  grep -q 'smoke'   '$T/shellassemble1.out' &&
  grep -q 'ad-dc'   '$T/shellassemble1.out' &&
  grep -q 'shotbox' '$T/shellassemble1.out'"
check "assemble (in-shell): writes report.md next to the boxes, not inside one" bash -c "[ -s '$T/my labs/report.md' ]"
if command -v pandoc >/dev/null 2>&1; then
check "assemble (in-shell): defaults to the fullest output (--pdf) with zero flags typed" has "$T/shellassemble1.out" "ODT draft:"
rm -f "$T/my labs/report.md" "$T/my labs/report.odt" "$T/my labs/report.pdf" "$T/my labs/.mkbox-assemble.conf"

# explicit flags, once, should be remembered - a later bare "assemble" repeats them without being
# told again, rather than silently reverting to the --pdf default
printf '%s\n' 'assemble --odt' 'exit' | "$MK" smoke > "$T/shellassemble2.out" 2>&1
check "assemble (in-shell): explicit --odt honored"               bash -c "[ -s '$T/my labs/report.odt' ]"
check "assemble (in-shell): --odt alone doesn't also produce a PDF" bash -c "[ ! -e '$T/my labs/report.pdf' ]"
rm -f "$T/my labs/report.md" "$T/my labs/report.odt"
printf '%s\n' 'assemble' 'exit' | "$MK" smoke > "$T/shellassemble3.out" 2>&1
check "assemble (in-shell): remembers last call's flags on a later bare call" bash -c "
  [ -s '$T/my labs/report.odt' ] && [ ! -e '$T/my labs/report.pdf' ]"
rm -f "$T/my labs/report.md" "$T/my labs/report.odt" "$T/my labs/report.pdf" "$T/my labs/.mkbox-assemble.conf"
else
  echo "  skip  in-shell assemble --odt/--pdf checks (pandoc not installed)"
fi

# --- install.sh: the installed tree must be complete, found through the bin/ symlink ---------------
echo "install.sh"
INST_ROOT="$(cd "$(dirname -- "$MK")" && pwd)"
INST="$T/inst"
bash "$INST_ROOT/install.sh" --prefix "$INST" > "$T/install.out" 2>&1 || sed "s/^/  install.sh: /" "$T/install.out"
check "install.sh: installs the script behind a bin/ symlink"   bash -c "[ -L '$INST/bin/mkbox' ] && [ -x '$INST/share/mkbox/mkbox' ]"
check "install.sh: ships the bundled template"                  bash -c "[ -s '$INST/share/mkbox/templates/mkbox-default.odt' ]"
check "install.sh: ships the PDF helper"                        bash -c "[ -s '$INST/share/mkbox/lib/mkbox-update-toc.py' ]"
check "install.sh: installed mkbox runs through the symlink"    bash -c "'$INST/bin/mkbox' -V | grep -Eq '^mkbox [0-9]+\.[0-9]+\.[0-9]+\$'"
if command -v pandoc >/dev/null 2>&1; then
  ( cd "$T" && rm -rf instbox && mkdir instbox && cd instbox && "$INST/bin/mkbox" -n ib 10.9.9.9 >/dev/null 2>&1 \
    && "$INST/bin/mkbox" -a r.md --odt ib > "$T/install-odt.out" 2>&1 )
  check "install.sh: installed copy can build an --odt with the default template" bash -c "[ -s '$T/instbox/r.odt' ]"
fi
bash "$INST_ROOT/install.sh" --prefix "$INST" --uninstall > /dev/null 2>&1
check "install.sh: --uninstall removes it"                      bash -c "[ ! -e '$INST/bin/mkbox' ] && [ ! -d '$INST/share/mkbox' ]"

# --- --title / --doctor ---------------------------------------------------------------------------
echo "title and doctor"
"$MK" -a "$T/titled.md" --title='Acme "Q4" Pentest' smoke > /dev/null 2>&1
check "--title: appears in the assembled draft"          has "$T/titled.md" 'Acme "Q4" Pentest - assembled draft'
"$MK" -a "$T/untitled.md" smoke > /dev/null 2>&1
check "--title: default is still OSCP Exam Report"       has "$T/untitled.md" "OSCP Exam Report - assembled draft"
MKBOX_TITLE="From Env" "$MK" -a "$T/envtitled.md" smoke > /dev/null 2>&1
check "--title: \$MKBOX_TITLE is honored"                has "$T/envtitled.md" "From Env - assembled draft"
check "--title: usage mentions the flag"                 bash -c "'$MK' -h 2>&1 | grep -q -- '--title'"
if command -v pandoc >/dev/null 2>&1; then
  "$MK" -a "$T/titled2.md" --odt --title="Custom Cover Title" smoke > /dev/null 2>&1
  rm -rf "$T/odttitle" && mkdir "$T/odttitle" && (cd "$T/odttitle" && unzip -o -q ../titled2.odt)
  check "--title: lands on the ODT cover page"           has "$T/odttitle/content.xml" "Custom Cover Title"
fi
"$MK" --doctor > "$T/doctor.out" 2>&1; DOCTOR_RC=$?
check "--doctor: reports version and install checks"     bash -c "grep -q '^Install:' '$T/doctor.out' && grep -q 'templates/mkbox-default.odt' '$T/doctor.out'"
check "--doctor: bundled files are found in the repo"    bash -c "! grep -q MISSING '$T/doctor.out'"
check "--doctor: exits 0 when nothing required is missing" bash -c "[ '$DOCTOR_RC' -eq 0 ]"
BARE="$T/bare" && mkdir -p "$BARE" && cp "$MK" "$BARE/mkbox"
"$BARE/mkbox" --doctor > "$T/doctor-bare.out" 2>&1; BARE_RC=$?
check "--doctor: flags a bare script copy (no template/lib)" bash -c "[ '$BARE_RC' -ne 0 ] && grep -q 'MISSING.*templates/mkbox-default.odt' '$T/doctor-bare.out'"

# --- report sections you write yourself: --text / reporttext -----------------------------------------
echo "report sections (--text)"
PD="$T/parts-run" && rm -rf "$PD" && mkdir -p "$PD" && cp -r "$T/my labs/smoke" "$PD/smoke" 2>/dev/null
EDSH="$T/fake-editor.sh"
printf '#!/bin/sh\nprintf "Tested two hosts.\\n\\n- two high findings\\n" >> "$1"\n' > "$EDSH" && chmod +x "$EDSH"
( cd "$PD" && "$MK" --text > "$T/parts-status1.out" 2>&1 )
check "--text: status lists all three sections as TODO"     bash -c "[ \$(grep -c 'TODO' '$T/parts-status1.out') -eq 3 ]"
( cd "$PD" && "$MK" -a report.md smoke > "$T/parts-asm1.out" 2>&1 )
check "assemble: unfilled sections produce a to-do checklist" has "$T/parts-asm1.out" "Still to write before you submit"
check "assemble: checklist names the command to run"       has "$T/parts-asm1.out" "mkbox --text summary"
check "assemble: stub still present in the draft"          has "$PD/report.md" "TODO: A short, non-technical paragraph"
( cd "$PD" && EDITOR="$EDSH" "$MK" --text summary && EDITOR="$EDSH" "$MK" --text recs )
check "--text: creates report-parts/summary.md privately"  bash -c "[ \"\$(stat -c %a '$PD/report-parts/summary.md')\" = 600 ]"
check "--text: new file carries the guidance comment"       has "$PD/report-parts/summary.md" "This comment is ignored"
( cd "$PD" && "$MK" --text > "$T/parts-status2.out" 2>&1 )
check "--text: status shows summary and recommendations done" bash -c "grep -q 'done   High-Level Summary' '$T/parts-status2.out' && grep -q 'done   Recommendations' '$T/parts-status2.out' && grep -q 'TODO   Methodology' '$T/parts-status2.out'"
( cd "$PD" && "$MK" -a report.md smoke > "$T/parts-asm2.out" 2>&1 )
check "assemble: filled text lands in the draft"           has "$PD/report.md" "Tested two hosts."
check "assemble: guidance comment is not in the draft"     bash -c "! grep -q 'This comment is ignored' '$PD/report.md'"
check "assemble: only the unwritten section is still listed" bash -c "grep -A3 'Still to write' '$T/parts-asm2.out' | grep -q Methodology && ! grep -A3 'Still to write' '$T/parts-asm2.out' | grep -q 'High-Level Summary'"
( cd "$PD" && "$MK" -a report.md smoke > /dev/null 2>&1 )
check "assemble: rerunning never overwrites your text"     has "$PD/report-parts/summary.md" "Tested two hosts."
check "--text: unknown section name is rejected"           bash -c "! (cd '$PD' && '$MK' --text bogus >/dev/null 2>&1)"
printf '%s\n' 'reporttext' 'exit' | "$MK" smoke > "$T/parts-shell.out" 2>&1
check "reporttext (in-shell) shows the same status"        has "$T/parts-shell.out" "Report sections you write yourself"

# --- re-entering vs typos -----------------------------------------------------------------------
echo "new vs existing"
printf 'exit\n' | "$MK" smoke > "$T/e1.out" 2>&1
printf 'exit\n' | "$MK" smok > "$T/e2.out" 2>&1
check "existing box: re-entering"        has "$T/e1.out" "re-entering 'smoke'"
check "typo: says creating new box"      has "$T/e2.out" "creating new box 'smok'"
check "typo: hints about setip"          has "$T/e2.out" "setip"
check "new box via shell: Happy Hacking" has "$T/e2.out" "Happy Hacking :)"
# "smok" is one char short of the existing "smoke" box - the closest-sibling-box check should
# flag it, by name, without blocking creation (the box still gets made either way)
check "typo: flags the close existing box by name"  has "$T/e2.out" "close to the existing box 'smoke'"
check "typo: still creates the box anyway"           bash -c "[ -d smok ]"
"$MK" -n unrelated-short-name 10.10.10.60 > "$T/noflag.out" 2>&1
check "no false positive: short, unrelated box name isn't flagged" bash -c "! grep -q 'close to the existing box' '$T/noflag.out'"
"$MK" -n ad-dcx 10.5.5.31 > "$T/addc.out" 2>&1
check "typo: one-char-off AD box name flagged too" has "$T/addc.out" "close to the existing box 'ad-dc'"
rm -rf smok unrelated-short-name ad-dcx
check "re-entering: no greeting"         bash -c "! grep -q 'Happy Hacking' '$T/e1.out'"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
