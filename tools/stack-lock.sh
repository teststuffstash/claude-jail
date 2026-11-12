# shellcheck shell=bash
# stack-lock — sourced by tools/stack-jail.sh: one launch per stack and runtime at a time.
# Taken from the work variant's tools/host-tools.sh (tools/work-variant.sh).
#
# The lock is a directory (mkdir is atomic) holding "owner": "<pid> <process start time>". The
# start time is what tells a lock left by a holder that never ran its exit trap (a reboot, a
# closed terminal, SIGKILL) from a live one, pid reuse included: such a lock is taken over with a
# warning instead of blocking every later launch. A lock with no owner is younger than a minute
# (a holder between its mkdir and its write) or broken: stale after that minute.
proc_start() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null; }   # <pid> → empty when there is no such process
lock_take() { # <lock dir> → 0 held by this shell; 1 held by a live process (its owner line on stdout)
  local lock="$1" me owner aside n
  me="$$ $(proc_start $$)"
  for n in 1 2 3; do
    if mkdir "$lock" 2>/dev/null; then printf '%s\n' "$me" > "$lock/owner"; return 0; fi
    owner=$(cat "$lock/owner" 2>/dev/null || true)
    if [ -n "$owner" ]; then
      [ "$(proc_start "${owner%% *}")" != "${owner#* }" ] || { printf '%s\n' "$owner"; return 1; }
    elif [ -z "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      printf '(starting)\n'; return 1
    fi
    # Stale: move it aside, then make sure what moved is the lock judged stale — a concurrent taker
    # may have replaced it in between; then it goes back and that taker holds it.
    aside="$lock.stale.$$.$n"
    mv "$lock" "$aside" 2>/dev/null || continue
    if [ "$(cat "$aside/owner" 2>/dev/null || true)" = "$owner" ]; then
      echo "⚠ took over $lock from a holder that is gone (${owner:-no owner recorded})" >&2; rm -rf "$aside"
    else
      mv "$aside" "$lock" 2>/dev/null || rm -rf "$aside"
    fi
  done
  printf '(contended)\n'; return 1
}
lock_release() { # <lock dir>: only a lock this shell holds
  [ "$(cat "$1/owner" 2>/dev/null)" = "$$ $(proc_start $$)" ] || return 0
  rm -f "$1/owner"; rmdir "$1" 2>/dev/null || true
}
