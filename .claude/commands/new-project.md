# New Project

Set up a new project directory, GitHub repo, and shell alias in one shot.

## Step 1 — gather inputs

Ask the user two questions (can ask together):
1. **Project name** — lowercase, hyphens allowed, no spaces (e.g. `my-app`)
2. **GitHub visibility** — public or private?

## Step 2 — create the directory and git repo

```bash
mkdir -p /workspace/<name>
cd /workspace/<name>
git init
```

## Step 3 — create CLAUDE.md

Write `/workspace/<name>/CLAUDE.md` with this exact content:

```
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This project is in its early stages. Update this file as the architecture and tooling become established.

## Environment

Running inside a Docker jail — see `/workspace/CLAUDE.md` for container setup, permissions, and available tools.
```

## Step 4 — create GitHub repo

```bash
gh repo create teststuffstash/<name> --<public|private>
```

## Step 5 — set authenticated remote and push

```bash
git remote add origin "https://x-access-token:${GH_TOKEN}@github.com/teststuffstash/<name>.git"
git add CLAUDE.md
git commit -m "Initial commit"
git branch -M master
git push -u origin master
```

## Step 6 — add to jail .gitignore

Append the project name to `/workspace/.gitignore` under the cloned projects section:

```bash
echo "<name>/" >> /workspace/.gitignore
```

Then commit the change inside the jail repo:

```bash
git -C /workspace add .gitignore && git -C /workspace commit -m "Ignore <name>/"
git -C /workspace push
```

## Step 7 — add shell alias

Append to `/workspace/.aliases` (creates the file if missing):

```bash
echo "alias <name>='docker compose -f ~/Projects/docker-compose.yml run --rm claude zsh -c \"cd /workspace/<name> && exec claude\"'" >> /workspace/.aliases
```

Then tell the user:

> Alias written to `~/Projects/.aliases`. To activate it now and on future shells, add this to your host `~/.zshrc` if not already there:
> ```bash
> source ~/Projects/.aliases
> ```
> Then reload: `source ~/.zshrc`

## Step 8 — done

Confirm what was created: repo URL, local path, and alias name.
