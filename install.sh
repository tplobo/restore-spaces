#!/bin/zsh
# Install the `restore_spaces` module into `~/.hammerspoon`.
#
#   zsh install.sh           update the module and `init.lua`, keeping the saved
#                            states (`tmp/`) that are already installed
#   zsh install.sh --dev     the same, but install `init-dev.lua` (the
#                            development configuration) as `init.lua`
#   zsh install.sh --clean   overwrite everything, saved states included; the
#                            installed ones are backed up first (use it when a
#                            release changes the format of the saved states)
#
# The options can be combined, _e.g._ `zsh install.sh --dev --clean`.

SOURCE_DIR="${0:A:h}"
HAMMERSPOON_DIR="$HOME/.hammerspoon"
MODULE_DIR="$HAMMERSPOON_DIR/hs/restore_spaces"
BACKUP_DIR="$HAMMERSPOON_DIR/restore_spaces_backups/$(date +%Y%m%d-%H%M%S)"

function usage() {
    echo "Usage: zsh install.sh [--dev] [--clean]"
    echo "  (no option)  update the module, keeping the saved states"
    echo "  --dev        install the development configuration (init-dev.lua)"
    echo "  --clean      overwrite everything, saved states included (backed up first)"
}

function backup_states() {
    local states=("$MODULE_DIR"/tmp/data_*.json(N))
    if (( ${#states} )); then
        mkdir -p "$BACKUP_DIR"
        cp "${states[@]}" "$BACKUP_DIR/"
        echo "Backed up the saved states to $BACKUP_DIR"
    fi
}

function install_restore_spaces() {
    local clean=$1
    local init_file=$2
    local keep=(--exclude='/tmp/')

    echo "Installing 'restore_spaces' module..."
    mkdir -p "$MODULE_DIR/tmp"
    if [[ $clean == true ]]; then
        backup_states
        keep=()
    fi
    cp "$SOURCE_DIR/$init_file" "$HAMMERSPOON_DIR/init.lua"
    rsync -a --delete "${keep[@]}" "$SOURCE_DIR/restore_spaces/" "$MODULE_DIR/"
    mkdir -p "$MODULE_DIR/tmp"
    if [[ $clean == true ]]; then
        echo "Installed 'restore_spaces' module with $init_file (everything overwritten)."
    else
        echo "Installed 'restore_spaces' module with $init_file (saved states kept)."
    fi
}

CLEAN=false
INIT_FILE="init.lua"
for arg in "$@"; do
    case "$arg" in
        -c|--clean) CLEAN=true ;;
        -d|--dev) INIT_FILE="init-dev.lua" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
    esac
done

if ! command -v rsync >/dev/null; then
    echo "rsync is required but was not found." >&2
    exit 1
fi

install_restore_spaces $CLEAN $INIT_FILE