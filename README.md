<div align="center">

# 🩸 hashcat-toolkit

### **Run hashcat locally or on a remote host — clean, queued, and logged.**
![demo](screenshot.png)
<img src="https://img.shields.io/badge/bash-%3E%3D%204.0-8B0000?style=for-the-badge&logo=gnu-bash&logoColor=white" />
<img src="https://img.shields.io/badge/ssh-remote%20ready-8B0000?style=for-the-badge&logo=openssh&logoColor=white" />
<img src="https://img.shields.io/badge/docker-container%20mode-8B0000?style=for-the-badge&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/license-MIT-8B0000?style=for-the-badge" />
<img src="https://img.shields.io/badge/platform-linux-8B0000?style=for-the-badge&logo=linux&logoColor=white" />

<br />

**A small toolkit of shell scripts that wraps [hashcat](https://hashcat.net/hashcat/) and makes it pleasant to run — locally or on a remote host over SSH, inside a Docker container or directly on the host.**

</div>

---

## 📖 Table of Contents

- [Why](#-why)
- [Features](#-features)
- [Scripts](#-scripts)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Usage](#-usage)
  - [Local mode](#local-mode)
  - [Remote Docker mode](#remote-docker-mode)
- [Task Queue](#-task-queue)
- [Directory Checks](#-directory-checks)
- [Process Control](#-process-control)
- [Directory Layout](#-directory-layout)
- [Logs and State](#-logs-and-state)
- [Exit Codes](#-exit-codes)
- [Troubleshooting](#-troubleshooting)
- [FAQ](#-faq)
- [Security Notes](#-security-notes)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🩸 Why

Hashcat is fantastic. The command line around it — less so:

- Long `-m … -a … -o … --username …` lines that you keep retyping.
- No built-in way to fire off a batch of attacks and walk away.
- Running it on a beefy remote GPU box means either a mess of `ssh` commands
  or copying everything around.

**hashcat-toolkit** fixes all three with **one small, readable Bash script per
scenario**, plus a shared queue, logging, and consistent CLI. Nothing to
compile. No Python. Just `git clone && chmod +x`.

---

## 🔥 Features

- 📋 **Task queue** — add, list, remove, clear, run.
- 🔍 **`--check`** — quickly inspect hash / wordlist / rules / output dirs.
- 🎛️ **Process control** — `--status`, `--kill`, `--benchmark`, `--restart`.
- 🎨 **Colored output** with properly aligned boxes.
  Colors **auto-disable** when output is piped to a file.
- 📝 **Logging** of every run (command + exit code) to `~/.local/share/`.
- 🛡️ **Safe Ctrl-C handling** — the Docker mode restarts the remote container
  on interrupt, so you never leave a zombie behind.
- 🔐 **Configs in `~/.config/*.conf`** — no secrets ever land in the repo.
- 🧩 **Consistent interface** — the local and Docker scripts share the same
  flags, so muscle memory carries over.

---

## 📜 Scripts

| Script | Runs where | Requires |
|---|---|---|
| **`hashcat-local.sh`**  | On this machine              | `hashcat` in `PATH`             |
| **`remote-hashcat.sh`** | Inside a Docker container on a remote host over SSH | `ssh` + `docker` on the remote |

Both scripts expose the same subcommands (`--queue`, `--check`, `--status`, …),
so you can switch between them without relearning anything.

---

## ⚙️ Requirements

- **bash** ≥ 4.0 (any modern Linux distro has it — Kali, Ubuntu, Debian, Arch…)
- **ssh** client (for the remote script)
- **docker** on the remote host (for the remote script)
- **hashcat** in `PATH` (for the local script) — or set `HASHCAT_BIN` in the
  config to an absolute path.

Optional but recommended:

- `shellcheck` — for linting the scripts.
- A modern terminal with UTF-8 support (for aligned boxes).

---

## 🚀 Installation

### 1. Clone

```bash
git clone https://github.com/lexapypsik10/hashcat-toolkit.git
cd hashcat-toolkit
```

### 2. Make executable

```bash
chmod +x *.sh
```

### 3. (Optional) Put them on your `PATH`

```bash
sudo ln -s "$PWD/hashcat-local.sh" /usr/local/bin/hcl
sudo ln -s "$PWD/remote-hashcat.sh" /usr/local/bin/rhc
```

Now you can call `hcl …` and `rhc …` from anywhere.

### 4. (Optional) Verify install

```bash
hcl --help
rhc --help
```

You should see a blood-red box with usage instructions. 🩸

---

## 🧠 Configuration

The scripts read configuration from `~/.config/*.conf` if the file exists.
If it doesn't, sane defaults are used.

> **Never commit your real config to Git.** They live in `~/.config/`, not in
> the repo. The bundled `.gitignore` already excludes `*.conf`.

### Local mode — `~/.config/hashcat-local.conf`

```bash
# Path to the hashcat binary (name in PATH or absolute path)
HASHCAT_BIN="hashcat"

# Working root for local hashes/wordlists/rules/output
LOCAL_ROOT="$HOME/hashcat"

# Optional overrides
# QUEUE_FILE="$HOME/.local/share/hashcat-local/queue.txt"
# LOG_FILE="$HOME/.local/share/hashcat-local/hashcat-local.log"
```

### Remote Docker mode — `~/.config/remote-hashcat.conf`

```bash
# SSH target — hostname or ~/.ssh/config alias
HOST="user@my-server.com"

# Name of the running hashcat container
CONTAINER="hashcat"

# Paths **inside the container**
REMOTE_ROOT="/road/road"
REMOTE_OUTPUT="/road/road/output"

# Optional overrides
# QUEUE_FILE="$HOME/.local/share/remote-hashcat/queue.txt"
# LOG_FILE="$HOME/.local/share/remote-hashcat/remote-hashcat.log"
```

Tighten permissions:

```bash
chmod 600 ~/.config/hashcat-local.conf ~/.config/remote-hashcat.conf
```

### Remote host prerequisites

For `remote-hashcat.sh` to work, **on the remote host**:

1. SSH key access is set up (no password prompt):

   ```bash
   ssh-copy-id user@my-server.com
   ssh user@my-server.com "echo ok"
   ```

2. A container with hashcat is running:

   ```bash
   ssh user@my-server.com "docker ps"
   # CONTAINER ID   IMAGE            ...   NAMES
   # abc123...      hashcat/hashcat  ...   hashcat
   ```

3. Inside the container the working tree exists:

   ```bash
   ssh user@my-server.com "docker exec -i hashcat mkdir -p /road/road/{hashes,wordlists,rules,output}"
   ```

---

## 🕹️ Usage

> **Golden rule:** every hashcat argument is passed as **one quoted string**.
> The scripts pass that string straight through to hashcat, preserving order.

### Local mode

```bash
./hashcat-local.sh --help
./hashcat-local.sh --check
./hashcat-local.sh --check wordlists

./hashcat-local.sh "-m 0 -a 0 \
    $HOME/hashcat/hashes/md5.txt \
    $HOME/hashcat/wordlists/rockyou.txt \
    -O -w 3 \
    -o $HOME/hashcat/output/md5.cracked"
```

### Remote Docker mode

```bash
./remote-hashcat.sh --help
./remote-hashcat.sh --check
./remote-hashcat.sh --check output

./remote-hashcat.sh "-m 1000 -a 0 \
    /road/road/hashes/ntlm.txt \
    /road/road/wordlists/rockyou.txt \
    -O -w 3 \
    -o /road/road/output/ntlm.cracked \
    --username"
```

> Note the paths inside the Docker mode are **container paths**
> (`/road/road/...`), not host paths.

---

## 📋 Task Queue

Works identically in both scripts. Example with `hashcat-local.sh`
— swap the binary name for `remote-hashcat.sh` in the Docker case.

```bash
# Add a task
./hashcat-local.sh --queue add "-m 0 -a 0 ~/hashcat/hashes/md5.txt ~/hashcat/wordlists/rockyou.txt -O -w 3"

# Add another one
./hashcat-local.sh --queue add "-m 1000 -a 0 ~/hashcat/hashes/ntlm.txt ~/hashcat/wordlists/rockyou.txt -O -w 3"

# Inspect
./hashcat-local.sh --queue list
# ========== QUEUE ==========
#  1. -m 0    -a 0 ...
#  2. -m 1000 -a 0 ...

# Remove the 2nd task
./hashcat-local.sh --queue rm 2

# Run everything one after another
./hashcat-local.sh --queue run

# Clear
./hashcat-local.sh --queue clear
```

The queue is stored as plain text (one command per line) in:

- Local mode → `~/.local/share/hashcat-local/queue.txt`
- Docker mode → `~/.local/share/remote-hashcat/queue.txt`

You can edit it by hand if you want.

---

## 🔍 Directory Checks

Quickly list the contents of the working tree, without remembering paths:

```bash
./hashcat-local.sh --check            # the whole root
./hashcat-local.sh --check hashes
./hashcat-local.sh --check wordlists
./hashcat-local.sh --check rules
./hashcat-local.sh --check output
```

For remote mode, the same flags run `ls` **inside the container**:

```bash
./remote-hashcat.sh --check
./remote-hashcat.sh --check wordlists
```

---

## 🎛️ Process Control

### Local mode

```bash
./hashcat-local.sh --status       # hashcat --status
./hashcat-local.sh --kill         # pkill hashcat
./hashcat-local.sh --benchmark    # hashcat -b
```

### Remote Docker mode

```bash
./remote-hashcat.sh --status      # hashcat --status inside the container
./remote-hashcat.sh --kill        # pkill hashcat inside the container
./remote-hashcat.sh --restart     # docker restart the container
```

---

## 🗂️ Directory Layout

Both modes expect (and, in the local case, create) this layout:

```
<root>/
├── hashes/          # your hash files
├── wordlists/       # wordlists (rockyou.txt, etc.)
├── rules/           # hashcat rule files
└── output/          # cracked results (-o ...)
```

Where `<root>` is:

- local  → `$LOCAL_ROOT`   (default `~/hashcat`)
- remote → `$REMOTE_ROOT`  (default `/road/road`, **inside the container**)

---

## 📝 Logs and State

| What | Path |
|---|---|
| Local log         | `~/.local/share/hashcat-local/hashcat-local.log` |
| Local queue       | `~/.local/share/hashcat-local/queue.txt` |
| Remote log        | `~/.local/share/remote-hashcat/remote-hashcat.log` |
| Remote queue      | `~/.local/share/remote-hashcat/queue.txt` |

Each log line is timestamped:

```
[2025-01-15 21:04:12] RUN: -m 0 -a 0 ...
[2025-01-15 21:07:55] EXIT: 0 — -m 0 -a 0 ...
```

---

## 🚦 Exit Codes

| Code | Meaning |
|---|---|
| `0`   | Success |
| `1`   | Bad arguments, missing config, unreachable host |
| `130` | Interrupted by user (Ctrl-C) — cleanup already ran |
| other | Passed through from hashcat |

---

## 🧯 Troubleshooting

<details>
<summary><b>“Cannot reach user@host over SSH”</b></summary>

- Check the `HOST` value in `~/.config/remote-hashcat.conf`.
- Run `ssh user@host "echo ok"` manually.
- Make sure your SSH key is loaded (`ssh-add -l`) and copied with `ssh-copy-id`.

</details>

<details>
<summary><b>“container 'hashcat' is not running”</b></summary>

```bash
ssh user@host "docker ps -a | grep hashcat"
ssh user@host "docker start hashcat"
```

Or change `CONTAINER` in the config to the actual container name.

</details>

<details>
<summary><b>Boxes look misaligned</b></summary>

Your locale is not UTF-8. Fix:

```bash
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8
# re-login, or:
export LANG=en_US.UTF-8
```

Also make sure your terminal font is monospace.

</details>

<details>
<summary><b>Colors show up as `\033[0;36m`</b></summary>

You are using an old version of the script that used `cat <<EOF`.
Update to the latest version from this repo — it uses `printf` with `$'\033…'`.

</details>

<details>
<summary><b>hashcat not found</b></summary>

```bash
which hashcat
# if empty, install it:
sudo apt install hashcat        # Debian/Kali/Ubuntu
```

Or set an absolute path:

```bash
HASHCAT_BIN="/opt/hashcat/hashcat"   # in ~/.config/hashcat-local.conf
```

</details>

---

## ❓ FAQ

<details>
<summary><b>Can I run several hashcat jobs at once?</b></summary>

Yes — put them in the queue and run `--queue run` in the background with `&`
plus `nohup`, or use `tmux`/`screen` on the machine where the script runs.

</details>

<details>
<summary><b>Does this work on macOS?</b></summary>

The `hashcat-local.sh` script should work if you have `bash` ≥ 4.0
(`brew install bash`) and hashcat in `PATH`. The remote script works over SSH
regardless of your OS.

</details>

<details>
<summary><b>Why do I need to wrap arguments in quotes?</b></summary>

Because hashcat options contain spaces and characters that the shell would
otherwise split. Passing one quoted string preserves the exact order and
lets the script forward them unchanged.

</details>

<details>
<summary><b>Can I use a different container name?</b></summary>

Yes — set `CONTAINER="whatever"` in `~/.config/remote-hashcat.conf`.

</details>

---

## 🔒 Security Notes

- **Never commit your `~/.config/*.conf` files.** They may contain hostnames,
  usernames, and internal paths. The bundled `.gitignore` already excludes
  `*.conf`.
- Use **SSH keys**, not passwords.
- If you publish screenshots or logs, redact `HOST=` and internal paths.
- This tool runs hashcat with your privileges. It doesn't add or bypass any
  authorization — **only use hashcat on data you are legally allowed to test**.

---

## 🤝 Contributing

Pull requests are welcome.

1. Fork the repo.
2. Create a branch: `git checkout -b feature/my-change`.
3. Run `shellcheck *.sh` before committing.
4. Keep the coding style: 4-space indentation, `set -uo pipefail`,
   ANSI colors via `$'\033[…'`, helpers named `box_line` / `box_rule` / `die`.
5. Open a PR with a clear description.

---

## 📄 License

MIT — see [LICENSE](LICENSE).

<div align="center">

**🩸 Stay in the red. Crack responsibly. 🩸**

</div>
