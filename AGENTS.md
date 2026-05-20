# Safety Rules for Codex on macOS

## Scope

- Work only inside this repository.
- Treat the current repository root as the allowed workspace.
- Do not modify files outside this repository unless I explicitly ask.
- Before large edits, run `git status` and summarize the current state.
- After meaningful changes, summarize changed files and suggest a commit message.

## macOS System Safety

- Do not use `sudo`.
- Do not modify system paths such as:
  - `/System`
  - `/Library`
  - `/usr`
  - `/bin`
  - `/sbin`
  - `/private`
  - `/etc`
  - `/var`
  - `/opt`
- Do not change macOS security, privacy, permissions, Gatekeeper, SIP, firewall, login items, launch agents, or keychain settings.
- Do not run commands that alter system services, such as:
  - `launchctl`
  - `dscl`
  - `spctl`
  - `csrutil`
  - `diskutil`
  - `pmset`
  - `softwareupdate`
  - `defaults write` outside this app’s repository context

## User Account Safety

- Do not modify personal configuration files unless I explicitly ask:
  - `~/.ssh`
  - `~/.gnupg`
  - `~/.aws`
  - `~/.config`
  - `~/.codex`
  - `~/.claude`
  - `~/.zshrc`
  - `~/.zprofile`
  - `~/.bashrc`
  - `~/.gitconfig`
  - macOS Keychain
- Do not read, print, copy, or edit credentials, tokens, private keys, certificates, or passwords.
- Do not access unrelated folders such as Desktop, Documents, Downloads, iCloud Drive, or other project folders unless I explicitly ask.

## Git Safety

- Do not run destructive Git commands without explicit confirmation:
  - `git reset --hard`
  - `git clean -fdx`
  - `git push --force`
  - `git rebase -i`
  - deleting branches
- Before committing, show a short summary of changed files.
- Do not commit secrets, build artifacts, or local config files.
- Prefer normal commits over force pushes.

## File Deletion Safety

- Do not run destructive delete commands without explicit confirmation:
  - `rm -rf`
  - mass deletion
  - deleting project directories
  - deleting generated files unless they are clearly safe build artifacts
- Before deleting files, explain exactly what will be deleted and why.

## Xcode / Swift / macOS App Safety

- Do not modify Apple Developer certificates, provisioning profiles, signing identities, or Keychain items.
- Do not change bundle identifiers, signing teams, entitlements, sandbox settings, or app capabilities without asking first.
- Do not delete `.xcodeproj`, `.xcworkspace`, `Package.swift`, `Package.resolved`, source files, assets, or plist files without asking.
- Build artifacts such as `.build/`, `DerivedData/`, and `xcuserdata/` may be ignored or removed from Git tracking, but do not delete them from disk unless I ask.

## Package / Dependency Safety

- Do not install or update Homebrew packages, npm global packages, Ruby gems, Python packages, or system dependencies without asking first.
- Do not modify global tool settings.
- Local project dependency changes are allowed only after explaining why they are needed.

## Network / External Actions

- Do not upload files, send data to external services, or publish releases without asking.
- Do not create GitHub releases, tags, packages, or deployments without asking.
- Do not open pull requests or merge branches unless I ask.

## Operating Mode

- This project may run Codex in Full Access / YOLO mode.
- Even in YOLO mode, follow these rules strictly.
- If a task requires breaking one of these rules, stop and ask for confirmation first.
