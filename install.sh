#!/usr/bin/env bash
# install.sh - install mkbox with everything it needs next to it.
#
# mkbox finds its bundled template (templates/mkbox-default.odt) and its PDF helper
# (lib/mkbox-update-toc.py) relative to the real location of the script, so copying the bare
# `mkbox` file onto your PATH leaves --odt and --pdf without them. This installs the whole tree to
#   <prefix>/share/mkbox/   (mkbox, lib/, templates/)
# and symlinks <prefix>/bin/mkbox to it.
#
#   ./install.sh                  # /usr/local if you can write there, else ~/.local
#   sudo ./install.sh             # system-wide
#   ./install.sh --prefix DIR     # somewhere else
#   ./install.sh --uninstall      # remove what this installed (same --prefix rules)
#   ./install.sh --check          # only report which dependencies are present
set -euo pipefail

src="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
prefix="" action=install

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)    prefix="${2:?--prefix needs a directory}"; shift 2 ;;
    --prefix=*)  prefix="${1#--prefix=}"; shift ;;
    --uninstall) action=uninstall; shift ;;
    --check)     action=check; shift ;;
    -h|--help)   sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option: $1" >&2; exit 2 ;;
  esac
done

check_deps() { bash "$src/mkbox" --doctor; }

if [[ "$action" == check ]]; then check_deps; exit $?; fi

if [[ -z "$prefix" ]]; then
  if [[ -w /usr/local/bin && -w /usr/local ]] || [[ $EUID -eq 0 ]]; then prefix=/usr/local
  else prefix="$HOME/.local"; fi
fi
share="$prefix/share/mkbox"
link="$prefix/bin/mkbox"

if [[ "$action" == uninstall ]]; then
  [[ -L "$link" ]] && rm -f -- "$link"
  [[ -d "$share" ]] && rm -rf -- "$share"
  echo "Removed $link and $share"
  exit 0
fi

for f in mkbox lib/mkbox-update-toc.py templates/mkbox-default.odt; do
  [[ -f "$src/$f" ]] || { echo "install.sh: $src/$f is missing - run this from a complete checkout of the repo" >&2; exit 1; }
done

mkdir -p -- "$share/lib" "$share/templates" "$prefix/bin" 2>/dev/null || {
  echo "install.sh: can't write to $prefix - re-run with sudo, or use --prefix DIR" >&2; exit 1; }

install -m 755 "$src/mkbox"                          "$share/mkbox"
install -m 644 "$src/lib/mkbox-update-toc.py"        "$share/lib/mkbox-update-toc.py"
install -m 644 "$src/templates/mkbox-default.odt"    "$share/templates/mkbox-default.odt"
ln -sf -- "$share/mkbox" "$link"

# verify the way mkbox itself will find things: through the symlink
resolved="$(dirname -- "$(readlink -f -- "$link")")"
[[ -f "$resolved/templates/mkbox-default.odt" && -f "$resolved/lib/mkbox-update-toc.py" ]] \
  || { echo "install.sh: installed tree is incomplete under $resolved" >&2; exit 1; }
echo "Installed: $("$link" -V) -> $link"
echo "  files:   $share"
case ":$PATH:" in *":$prefix/bin:"*) ;; *) echo "  note:    $prefix/bin is not on your PATH - add it to your shell profile" ;; esac
echo
check_deps || true
