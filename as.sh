#!/usr/bin/env bash
# ============================================================
#  remote-hashcat.sh
#  Run hashcat inside a Docker container on a remote host via SSH.
#
#  Author : <your-name>
#  License: MIT
#  Repo   : https://github.com/<your-user>/remote-hashcat
# ============================================================

set -uo pipefail

# ------------------------------------------------------------
# Config — override via ~/.config/remote-hashcat.conf
# ------------------------------------------------------------
CONFIG_FILE="${REMOTE_HASHCAT_CONFIG:-$HOME/.config/remote-hashcat.conf}"
# shellcheck disable=SC1090
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

HOST="${HOST:-user@remote-host}"
CONTAINER="${CONTAINER:-hashcat}"
REMOTE_ROOT="${REMOTE_ROOT:-/road/road}"
REMOTE_OUTPUT="${REMOTE_OUTPUT:-$REMOTE_ROOT/output}"
QUEUE_FILE="${QUEUE_FILE:-$HOME/.local/share/remote-hashcat/queue.txt}"
LOG_FILE="${LOG_FILE:-$HOME/.local/share/remote-hashcat/remote-hashcat.log}"

mkdir -p "$(dirname "$QUEUE_FILE")" "$(dirname "$LOG_FILE")"
touch "$QUEUE_FILE" "$LOG_FILE"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    NC=$'\033[0m'
else
    RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; DIM=""; NC=""
fi

# ------------------------------------------------------------
# Utils
# ------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; }
die() { printf '%s[-] %s%s\n' "$RED" "$*" "$NC" >&2; exit 1; }

strip_ansi() { sed -E 's/\x1b\[[0-9;]*m//g'; }

box_line() {
    local text="$1" width="$2"
    local visible len pad
    visible=$(printf '%s' "$text" | strip_ansi)
    len=${#visible}
    pad=$(( width - len - 2 ))
    (( pad < 0 )) && pad=0
    printf '%s|%s %b%*s %s|%s\n' \
        "$CYAN" "$NC" "$text" "$pad" "" "$CYAN" "$NC"
}

box_rule() {
    local width="$1" char="${2:-=}"
    printf '%s+%s+%s\n' \
        "$CYAN" \
        "$(printf '%*s' "$width" '' | tr ' ' "$char")" \
        "$NC"
}

# ------------------------------------------------------------
# Help
# ------------------------------------------------------------
show_help() {
    local W=96

    echo
    box_rule "$W"
    box_line "${BOLD}${YELLOW}REMOTE-HASHCAT.SH — HASHCAT IN A REMOTE DOCKER CONTAINER${NC}" "$W"
    box_rule "$W"
    box_line "" "$W"
    box_line "${GREEN}PURPOSE:${NC} run hashcat inside a Docker container on a remote host via SSH." "$W"
    box_line "" "$W"
    box_line "${GREEN}USAGE:${NC}   ./remote-hashcat.sh \"HASHCAT_PARAMS\"" "$W"
    box_line "" "$W"
    box_line "${RED}IMPORTANT:${NC} pass all hashcat args inside ONE pair of double quotes." "$W"
    box_line "" "$W"
    box_line "${GREEN}EXAMPLE:${NC}" "$W"
    box_line "   ./remote-hashcat.sh \"-m 1000 -a 0 -D 1,2 $REMOTE_ROOT/hashes/h.txt \\" "$W"
    box_line "       $REMOTE_ROOT/wordlists/rockyou.txt -r $REMOTE_ROOT/rules/best.rule \\" "$W"
    box_line "       -O -w 3 -o $REMOTE_OUTPUT/out.txt --username\"" "$W"
    box_line "" "$W"
    box_line "${GREEN}FILES:${NC}   everything lives under $REMOTE_ROOT/ (inside the container)" "$W"
    box_line "          hashes/   wordlists/   rules/   output/" "$W"
    box_line "" "$W"
    box_line "${GREEN}CHECKS:${NC}" "$W"
    box_line "   --check                       list $REMOTE_ROOT/" "$W"
    box_line "   --check rules|hashes|wordlists|output" "$W"
    box_line "" "$W"
    box_line "${GREEN}QUEUE:${NC}" "$W"
    box_line "   --queue add \"...\"             add a task" "$W"
    box_line "   --queue list                  show queue" "$W"
    box_line "   --queue rm N                  remove task N" "$W"
    box_line "   --queue clear                 clear queue" "$W"
    box_line "   --queue run                   run all tasks" "$W"
    box_line "" "$W"
    box_line "${GREEN}MISC:${NC}" "$W"
    box_line "   --restart                     restart the remote container" "$W"
    box_line "   --status                      hashcat --status inside container" "$W"
    box_line "   --kill                        pkill hashcat inside container" "$W"
    box_line "   man | --help                  this help" "$W"
    box_line "" "$W"
    box_rule "$W"
    echo
}

# ------------------------------------------------------------
# SSH + Docker helpers
# ------------------------------------------------------------
remote()          { ssh "$HOST" "$@"; }
container_exec()  { remote "docker exec -i $CONTAINER $*"; }

require_ssh() {
    command -v ssh >/dev/null 2>&1 || die "ssh not found in PATH"
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" "true" 2>/dev/null \
        || die "Cannot reach $HOST over SSH (check key/agent/config)"
    remote "docker ps --format '{{.Names}}' | grep -qx '$CONTAINER'" \
        || die "container '$CONTAINER' is not running on $HOST"
}

# ------------------------------------------------------------
# Runner
# ------------------------------------------------------------
run_hashcat() {
    local CMD="$1"
    echo "${CYAN}>>> Running:${NC} $CMD"
    log "RUN: $CMD"

    # shellcheck disable=SC2086
    ssh -t "$HOST" "docker exec -i $CONTAINER hashcat --status --status-timer=60 $CMD"
    local st=$?

    if (( st == 0 )); then
        echo "${GREEN}[+] Task completed${NC}"
    else
        echo "${RED}[-] hashcat exited with code $st${NC}"
    fi
    log "EXIT: $st — $CMD"
    return $st
}

# ------------------------------------------------------------
# Queue
# ------------------------------------------------------------
queue_add() {
    [[ -z "${1:-}" ]] && die "no command provided"
    printf '%s\n' "$*" >>"$QUEUE_FILE"
    echo "${GREEN}[+] Added:${NC} $*"
}

queue_list() {
    if [[ -s "$QUEUE_FILE" ]]; then
        echo "${YELLOW}========== QUEUE ==========${NC}"
        nl -w2 -s'. ' "$QUEUE_FILE"
    else
        echo "${YELLOW}[+] Queue is empty${NC}"
    fi
}

queue_rm() {
    local n="${1:-}"
    [[ -z "$n" ]] && die "usage: --queue rm N"
    [[ "$n" =~ ^[0-9]+$ ]] || die "N must be a number"
    local total
    total=$(wc -l <"$QUEUE_FILE")
    (( n >= 1 && n <= total )) || die "index out of range (1..$total)"
    sed -i "${n}d" "$QUEUE_FILE"
    echo "${GREEN}[+] Removed task #$n${NC}"
}

queue_clear() {
    : >"$QUEUE_FILE"
    echo "${GREEN}[+] Queue cleared${NC}"
}

queue_run() {
    [[ -s "$QUEUE_FILE" ]] || die "queue is empty"
    echo "${GREEN}[+] Running queue...${NC}"
    while IFS= read -r CMD || [[ -n "$CMD" ]]; do
        [[ -z "$CMD" ]] && continue
        run_hashcat "$CMD"
        echo "${CYAN}----------------------------------------${NC}"
    done <"$QUEUE_FILE"
    echo "${GREEN}[+] Queue finished${NC}"
}

# ------------------------------------------------------------
# Cleanup on Ctrl-C / Ctrl-Z
# ------------------------------------------------------------
cleanup() {
    echo
    echo "${YELLOW}[*] Interrupted. Restarting container on remote...${NC}"
    ssh "$HOST" "docker restart $CONTAINER" >/dev/null 2>&1 || true
    echo "${GREEN}[+] Container restarted${NC}"
    exit 130
}
trap cleanup INT TSTP TERM

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
main() {
    if (( $# == 0 )); then show_help; exit 0; fi

    case "$1" in
        man|--help|-h)
            show_help
            exit 0
            ;;

        --queue)
            require_ssh
            case "${2:-}" in
                add)   shift 2; queue_add "$@" ;;
                list)  queue_list ;;
                rm)    shift 2; queue_rm "$@" ;;
                clear) queue_clear ;;
                run)   queue_run ;;
                *)     show_help; exit 1 ;;
            esac
            exit 0
            ;;

        --check)
            require_ssh
            case "${2:-}" in
                "")        container_exec "ls -la $REMOTE_ROOT" ;;
                rules)     container_exec "ls -la $REMOTE_ROOT/rules" ;;
                hashes)    container_exec "ls -la $REMOTE_ROOT/hashes" ;;
                wordlists) container_exec "ls -la $REMOTE_ROOT/wordlists" ;;
                output)    container_exec "ls -la $REMOTE_OUTPUT" ;;
                *) die "unknown --check target: ${2:-}" ;;
            esac
            exit 0
            ;;

        --restart)
            require_ssh
            echo "${YELLOW}[*] Restarting container...${NC}"
            remote "docker restart $CONTAINER" \
                && echo "${GREEN}[+] Container restarted${NC}" \
                || die "failed to restart container"
            exit 0
            ;;

        --status)
            require_ssh
            container_exec "hashcat --status"
            exit 0
            ;;

        --kill)
            require_ssh
            echo "${YELLOW}[*] Killing hashcat inside container...${NC}"
            container_exec "pkill -f hashcat || true"
            echo "${GREEN}[+] done${NC}"
            exit 0
            ;;
    esac

    require_ssh
    run_hashcat "$*"
}

main "$@"