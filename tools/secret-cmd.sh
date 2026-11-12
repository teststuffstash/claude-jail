# shellcheck shell=bash
# secret-cmd — sourced by tools/stack-jail.sh: a token in ~/Projects/.env.<stack> may be given as
# a COMMAND instead of a value, so the value can live in a wallet that is encrypted at rest.
# Taken from the work variant's tools/secret-cmd.sh (tools/work-variant.sh); here the caller
# names the variables, since they carry the stack's prefix.
#
#   ORACLE_PAT_CMD="secret-tool lookup service claude-jail stack oracle"     # instead of ORACLE_PAT=…
#
# resolve_secret_cmds <NAME>… — for each NAMED variable whose <NAME>_CMD is set: run it on the
# host (bash -c; the env file is the user's own, mode 600), put its stdout minus the trailing
# newline in <NAME>, export it, and unset <NAME>_CMD. Refuses when both <NAME> and <NAME>_CMD are
# set (which one did you mean?), and when the command fails or prints nothing: a locked wallet
# stops the launch instead of starting a jail with an empty credential. The command's stdout is
# the value and is never echoed; its stderr passes through, because that is where a wallet asks
# for a touch or a password. Errors name the variable only.
#
# Only the named variables are resolved, and the caller must `unset <NAME>_CMD` BEFORE sourcing
# the env file, so a *_CMD variable from the surrounding shell is never executed.
resolve_secret_cmds() {
  local name cmd_name cmd val
  [ $# -gt 0 ] || { echo "✖ resolve_secret_cmds: name the secrets this script needs" >&2; return 2; }
  for name in "$@"; do
    cmd_name="${name}_CMD"
    cmd="${!cmd_name:-}"
    [ -n "$cmd" ] || continue
    if [ -n "${!name:-}" ]; then
      echo "✖ $name and $cmd_name are both set in the env file — keep one" >&2; return 2
    fi
    echo "· $cmd_name: resolving (a wallet may ask for a touch or a password now)" >&2
    if ! val=$(bash -c "$cmd"); then                      # stderr passes through: that is where a wallet prompts
      echo "✖ $cmd_name failed (wallet locked, key not plugged in, entry missing?) — nothing launched" >&2; return 2
    fi
    val="${val%$'\n'}"
    if [ -z "$val" ]; then
      echo "✖ $cmd_name printed nothing — nothing launched" >&2; return 2
    fi
    printf -v "$name" '%s' "$val"
    export "${name?}"
    unset "$cmd_name"
  done
}
