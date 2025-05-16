#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# CONFIG & GLOBAL VARIABLES
###############################################################################
CONFIG_FILE="$HOME/.jupyterlab-controller.conf"

# Default options
DEFAULT_VENV_DIR="$HOME/jupyterlab_venv"
DEFAULT_PORT="8888"
DEFAULT_SSL="n"
DEFAULT_LSP="n"

# Files
LOG_FILE="$HOME/jupyterlab.log"
PID_FILE="$HOME/jupyterlab.pid"
CERT_FILE="$HOME/jupyter.crt"
KEY_FILE="$HOME/jupyter.key"

# Variables set by wizard or loaded from config
VENV_DIR=""
PORT=""
USE_SSL=""
USE_LSP=""

###############################################################################
# HELPER FUNCTIONS
###############################################################################
log()  { printf '\033[1;34m[INFO]\033[0m %s\n'  "$1"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; }
fail() { err "$1"; exit 1; }
check_cmd(){ command -v "$1" &>/dev/null || fail "Required '$1' not found."; }

spinner() {
  # Minimal spinner to keep terminal clean
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  tput civis  # hide cursor
  while kill -0 "$pid" 2>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  tput cnorm  # show cursor
}

run_silent() {
  # Usage: run_silent "Step description" command ...
  local desc=$1
  shift
  echo -n " $desc..."
  ("$@" &>/dev/null) &
  local pid=$!
  spinner $pid
  wait $pid || fail "Error in: $desc"
  echo " Done."
}

load_config() {
  # Load existing config if any
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
}

save_config() {
  # Save current config to file
  cat <<EOF > "$CONFIG_FILE"
VENV_DIR="$VENV_DIR"
PORT="$PORT"
USE_SSL="$USE_SSL"
USE_LSP="$USE_LSP"
EOF
}

installed(){
  [[ -d "$VENV_DIR" ]]
}

running(){
  [[ -f "$PID_FILE" ]] && kill -0 "$( <"$PID_FILE")" &>/dev/null
}

###############################################################################
# WIZARD: GATHER USER CONFIG
###############################################################################
wizard() {
  echo
  echo " ┌───────────────────────────────────────────────┐"
  echo " │       JupyterLab Installation Wizard        │"
  echo " └───────────────────────────────────────────────┘"
  echo

  # Pre-fill from existing config or defaults
  local _venv="${VENV_DIR:-$DEFAULT_VENV_DIR}"
  local _port="${PORT:-$DEFAULT_PORT}"
  local _ssl="${USE_SSL:-$DEFAULT_SSL}"
  local _lsp="${USE_LSP:-$DEFAULT_LSP}"

  # 1) VENV Dir
  read -rp " 1) Virtual environment path [$_venv]: " input
  VENV_DIR="${input:-$_venv}"

  # 2) Port
  read -rp " 2) JupyterLab port [$_port]: " input
  PORT="${input:-$_port}"

  # 3) SSL
  read -rp " 3) Generate self-signed SSL certificate? (y/n) [$_ssl]: " input
  USE_SSL="${input:-$_ssl}"

  # 4) LSP
  read -rp " 4) Install JupyterLab LSP extension? (y/n) [$_lsp]: " input
  USE_LSP="${input:-$_lsp}"

  echo
  echo " Summary of your choices:"
  echo " ──────────────────────────────────────────────"
  echo "   VENV Directory:  $VENV_DIR"
  echo "   Port:            $PORT"
  echo "   SSL Certificate: $USE_SSL"
  echo "   LSP Extension:   $USE_LSP"
  echo " ──────────────────────────────────────────────"
  read -rp " Proceed with these options? (y/n) [y]: " confirm
  confirm="${confirm:-y}"
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

  # Save to config for future runs
  save_config
}

###############################################################################
# INSTALL JUPYTERLAB
###############################################################################
install_jupyterlab(){
  load_config  # ensure we have the latest config values

  if installed; then
    log "JupyterLab is already installed at $VENV_DIR."
    return
  fi

  check_cmd sudo
  check_cmd curl
  check_cmd python3

  # 1) System dependencies
  run_silent "Updating system" sudo apt-get update -qq
  run_silent "Installing system deps" sudo apt-get install -y -qq \
    python3 python3-venv python3-pip \
    openssl software-properties-common \
    curl

  # 2) Create & activate Python venv
  run_silent "Creating virtual environment" python3 -m venv "$VENV_DIR"
  # shellcheck disable=SC1090
  source "$VENV_DIR/bin/activate"

  run_silent "Upgrading pip/wheel" pip install --upgrade pip wheel
  run_silent "Installing JupyterLab core" pip install jupyterlab ipykernel

  # 3) Optional: LSP extension
  if [[ "$USE_LSP" =~ ^[Yy]$ ]]; then
    run_silent "Installing JupyterLab LSP" pip install jupyterlab-lsp
  fi

  # 4) Optional: SSL certificate
  if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
    run_silent "Generating self-signed SSL cert" \
      openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=$(hostname)"
    chmod 600 "$KEY_FILE"
  else
    [[ -f "$KEY_FILE" ]] && rm -f "$KEY_FILE"
    [[ -f "$CERT_FILE" ]] && rm -f "$CERT_FILE"
  fi

  # 5) (Optional) Additional language servers
  if [[ "$USE_LSP" =~ ^[Yy]$ ]]; then
    echo
    echo "Would you like to install some common language servers?"
    echo "This step may require node/npm for many servers."
    read -rp "Install language servers? (y/n) [n]: " LSP_INSTALL
    LSP_INSTALL="${LSP_INSTALL:-n}"
    if [[ "$LSP_INSTALL" =~ ^[Yy]$ ]]; then
      run_silent "Ensuring node/npm" sudo apt-get install -y -qq nodejs npm

      echo
      read -rp "   - Bash/Shell (y/n) [n]? " L_BASH
      L_BASH="${L_BASH:-n}"
      read -rp "   - Dockerfile (y/n) [n]? " L_DOCKER
      L_DOCKER="${L_DOCKER:-n}"
      read -rp "   - JS/TS (y/n) [n]? " L_JS
      L_JS="${L_JS:-n}"
      read -rp "   - HTML/CSS/JSON/YAML (y/n) [n]? " L_WEB
      L_WEB="${L_WEB:-n}"
      read -rp "   - Python (y/n) [n]? " L_PY
      L_PY="${L_PY:-n}"

      [[ "$L_BASH" =~ ^[Yy]$ ]] && run_silent "Installing Bash LSP" \
         sudo npm install -g bash-language-server
      [[ "$L_DOCKER" =~ ^[Yy]$ ]] && run_silent "Installing Dockerfile LSP" \
         sudo npm install -g dockerfile-language-server-nodejs
      [[ "$L_JS" =~ ^[Yy]$ ]] && run_silent "Installing JS/TS LSP" \
         sudo npm install -g typescript typescript-language-server

      if [[ "$L_WEB" =~ ^[Yy]$ ]]; then
        run_silent "Installing HTML/CSS/JSON/YAML LSP" \
          sudo npm install -g vscode-html-languageserver-bin \
                            vscode-css-languageserver-bin \
                            vscode-json-languageserver-bin \
                            yaml-language-server
      fi

      [[ "$L_PY" =~ ^[Yy]$ ]] && run_silent "Installing Python LSP" \
         pip install 'python-lsp-server[all]'
    fi
  fi

  echo
  log "Installation complete."
}

###############################################################################
# START JUPYTERLAB
###############################################################################
start_jupyterlab(){
  load_config  # ensures we know the correct VENV_DIR, etc.

  installed || fail "Not installed. Please run 'Install JupyterLab' first."

  if running; then
    log "Already running (PID $(<"$PID_FILE"))."
    return
  fi

  # Activate venv
  # shellcheck disable=SC1090
  source "$VENV_DIR/bin/activate"

  CMD="jupyter lab --ip=0.0.0.0 --port=$PORT --no-browser"
  if [[ -f "$CERT_FILE" && -f "$KEY_FILE" ]]; then
    CMD+=" --certfile=$CERT_FILE --keyfile=$KEY_FILE"
  fi
  (( EUID==0 )) && CMD+=" --allow-root"

  log "Starting JupyterLab..."
  nohup $CMD >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  sleep 3

  URL=$(grep -o -m1 'https\?://[^ ]*token=[0-9a-f]\+' "$LOG_FILE" || true)
  if running; then
    log "JupyterLab is running (PID $(<"$PID_FILE"))."
    if [[ -n "$URL" ]]; then
      echo "Local Access URL: $URL"
    else
      echo "Check $LOG_FILE for the token URL."
    fi

    # Try to fetch public IPv4 & IPv6 with a short timeout (5 seconds)
    PUBLIC_IPV4=$(curl --max-time 5 -s4 https://ifconfig.co/ip || true)
    PUBLIC_IPV6=$(curl --max-time 5 -s6 https://ifconfig.co/ip || true)

    if [[ -n "$PUBLIC_IPV4" ]]; then
      echo "Public IPv4: $PUBLIC_IPV4"
      echo "If allowed by firewall, access: https://$PUBLIC_IPV4:$PORT"
    fi

    # If IPv6 is different and non-empty, display it
    if [[ -n "$PUBLIC_IPV6" && "$PUBLIC_IPV6" != "$PUBLIC_IPV4" ]]; then
      echo "Public IPv6: $PUBLIC_IPV6"
      echo "If allowed by firewall, access: https://[$PUBLIC_IPV6]:$PORT"
    fi
  else
    err "Failed to start; see $LOG_FILE"
    rm -f "$PID_FILE"
    return
  fi

  # Wait for user so it doesn't look like it "hangs"
  echo
  read -rp "Press ENTER to return to the main menu..."
}

###############################################################################
# STOP JUPYTERLAB
###############################################################################
stop_jupyterlab(){
  load_config
  if running; then
    PID=$(<"$PID_FILE")
    log "Stopping JupyterLab (PID $PID)..."
    kill "$PID" || err "Failed to kill $PID"
    rm -f "$PID_FILE"
    log "Stopped."
  else
    log "JupyterLab is not running."
  fi
}

###############################################################################
# UNINSTALL JUPYTERLAB
###############################################################################
uninstall_jupyterlab(){
  load_config
  if ! installed; then
    log "Nothing to uninstall."
    return
  fi
  read -rp "Are you sure you want to uninstall JupyterLab and remove all files? (y/n) [n]: " confirm
  confirm="${confirm:-n}"
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    stop_jupyterlab || true
    rm -rf "$VENV_DIR" "$CERT_FILE" "$KEY_FILE" "$LOG_FILE" "$PID_FILE"
    log "Uninstalled completely."
  else
    log "Uninstall aborted."
  fi
}

###############################################################################
# MAIN MENU
###############################################################################
main_menu(){
  while true; do
    echo
    echo " JupyterLab Controller"
    echo " ────────────────────"
    echo " 1) Install JupyterLab"
    echo " 2) Start server"
    echo " 3) Stop server"
    echo " 4) Uninstall"
    echo " 5) Exit"
    echo

    read -rp "Choose [1-5]: " opt
    case "$opt" in
      1)
        wizard
        install_jupyterlab
        ;;
      2)
        start_jupyterlab
        ;;
      3)
        stop_jupyterlab
        ;;
      4)
        uninstall_jupyterlab
        ;;
      5)
        exit 0
        ;;
      *)
        err "Invalid option."
        ;;
    esac
  done
}

###############################################################################
# ENTRY POINT
###############################################################################
main_menu
