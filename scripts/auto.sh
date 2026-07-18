#!/usr/bin/env bash
#
# Spustí monitorovací úlohy:
#   - picocom na kufr.lan v SAMOSTATNÉM terminálovém okně (ne v tmuxu),
#     pošle znak 'n' hned po připojení a znovu po 5s, pak lze psát normálně
#   - zbylé úlohy v tmux session, ke které se připojí další terminálové okno:
#       2) start.sh na parallella-vlf.lan
#       3) lightning_detector.sh na parallella-vlf.lan
#       4) efmplot.py lokálně, s log souborem daným parametrem skriptu
#       5) snapvizu lokálně
#
# Použití: ./start_monitoring.sh <nazev_mista>
#   -> log soubor bude ulozen jako <RRRRMMDD>_<HHMMSS>_<nazev_mista>.log
#      napr. ./start_monitoring.sh sobeslav -> 20260718_143205_sobeslav.log
#
# Vyžaduje: tmux, expect, ssh, a nějaký terminálový emulátor
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ $# -lt 1 ]; then
    echo "Použití: $0 <nazev_mista>"
    exit 1
fi
LOGNAME="$(date +%Y%m%d_%H%M%S)_$1"
SESSION="monitoring"
for cmd in tmux expect ssh; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Chybí program '$cmd', nainstaluj ho prosím." >&2
        exit 1
    fi
done
wait_key() {
    read -r -p "$1 [Enter pro pokračování] " _
}

open_terminal() {
    # $1 = příkaz, který se má v novém okně terminálu spustit
    if command -v x-terminal-emulator >/dev/null 2>&1; then
        x-terminal-emulator -e bash -c "$1" &
    elif command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal -- bash -c "$1" &
    elif command -v xterm >/dev/null 2>&1; then
        xterm -e bash -c "$1" &
    else
        echo "Nepodařilo se najít terminálový emulátor pro příkaz: $1" >&2
        return 1
    fi
}

# --- Samostatné okno: picocom na kufr.lan, pošle 'n' 2x, pak interaktivní ---
PICOCOM_CMD='expect -c '\''
set timeout -1
spawn ssh root@kufr.lan picocom /dev/ttyUSB0
sleep 2
send "n"
sleep 5
send "n"
interact
'\'''
open_terminal "$PICOCOM_CMD"
echo "Okno s picocomem spuštěno, posílám znak 'n' na kufr.lan..."
sleep 8
wait_key "Znak 'n' by měl být odeslán 2x. Pokračovat spuštěním start.sh na parallella-vlf.lan?"

# --- Založ tmux session pro zbylé úlohy ----------------------------------
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -n start

# --- Otevři nové okno terminálu připojené k tmux session ----------------
open_terminal "tmux attach -t $SESSION"
sleep 1

# --- Okno start: start.sh na parallella-vlf.lan --------------------------
tmux send-keys -t "${SESSION}:start" \
    "ssh root@parallella-vlf.lan 'cd /root/repos/station-supervisor && ./start.sh'" C-m
sleep 2
wait_key "Okno 'start' běží. Pokračovat spuštěním lightning_detector.sh na parallella-vlf.lan?"

# --- Okno lightning: lightning_detector.sh na parallella-vlf.lan --------
tmux new-window -t "$SESSION" -n lightning
tmux send-keys -t "${SESSION}:lightning" \
    "ssh root@parallella-vlf.lan 'cd /root/repos/station-supervisor && ./lightning_detector.sh'" C-m
sleep 2
wait_key "Okno 'lightning' běží. Pokračovat spuštěním efmplot.py?"

# --- Okno efmplot: efmplot.py lokálně ------------------------------------
tmux new-window -t "$SESSION" -n efmplot
tmux send-keys -t "${SESSION}:efmplot" \
    "cd /home/kakl/git/EFM_plotter/efmplot/ && python3 efmplot.py --port /dev/ttyUSB0 --baudrate 115200 --gui --log_file ${LOGNAME}.log" C-m
sleep 2
wait_key "Efmplot spuštěn. Pokračovat spuštěním snapvizu?"

# --- Okno snapvizu: snapvizu lokálně -------------------------------------
tmux new-window -t "$SESSION" -n snapvizu
tmux send-keys -t "${SESSION}:snapvizu" \
    "cd /home/kakl/git/station-supervisor && ./snapvizu.sh" C-m

echo "Všechny úlohy spuštěny. Log soubor: ${LOGNAME}.log"
echo "V novém okně terminálu je připojená tmux session (Ctrl+b 0-3 pro přepínání mezi start/lightning/efmplot/snapvizu)."
echo "Picocom běží v samostatném okně terminálu a je plně interaktivní."
