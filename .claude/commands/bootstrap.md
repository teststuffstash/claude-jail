# Bootstrap

Bootstraps this Claude Code jail on a new machine. First detect context, then run the appropriate phase.

## Step 1 — detect context

```bash
test -f /.dockerenv && echo inside || echo outside
```

---

## If outside the jail

1. Confirm `setup-env.sh` exists in the current directory. If not, tell the user to `cd` into the jail repo first and stop.

2. Run `./setup-env.sh`.

3. Run `docker compose build`.

4. Tell the user:
   > Host setup complete. Start the jail with:
   > ```
   > docker compose run --rm claude
   > ```
   > Then run `/bootstrap` again from inside to finish.

Stop here — do not continue to the inside steps.

---

## If inside the jail

### Git identity

Check current global git identity:

```bash
git config --global user.email
git config --global user.name
```

If either is empty, ask the user for the missing value(s) and set them:

```bash
git config --global user.email "<value>"
git config --global user.name "<value>"
```

### Shell aliases

Check whether `~/Projects/.aliases` is sourced from the host `~/.zshrc`:

```bash
grep -q "Projects/.aliases" /home/node/.zshrc && echo sourced || echo missing
```

If missing, tell the user to add this to their host `~/.zshrc`:

```bash
[ -f ~/Projects/.aliases ] && source ~/Projects/.aliases
```

### GH_TOKEN

Check whether `GH_TOKEN` is already set in `/workspace/.env`:

```bash
grep -q "^GH_TOKEN=" /workspace/.env 2>/dev/null && echo set || echo missing
```

If missing, tell the user:
> Paste your GitHub fine-grained PAT (see README — it should be scoped to the `teststuffstash` org).

Once the user provides it, append it to `.env`:

```bash
echo "GH_TOKEN=<value>" >> /workspace/.env
```

### Verify GitHub auth

```bash
gh auth status
```

Report what it says. If it fails, show the error and stop.

### Done

Tell the user the jail is ready.
