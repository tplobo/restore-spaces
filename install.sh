#!/bin/zsh

MODULE_FILES=(
    "init.lua"
    "restore_spaces"
)

DESTINATIONS=(
    "~/.hammerspoon"
    "~/.hammerspoon/hs"
)

function install_restore_spaces() {
    local -n ALL_FILES=$1
    local -n ALL_DESTINATIONS=$2

    for (( i=0; i<${#ALL_FILES[@]}; i++ )); do
        DESTINATION=${ALL_DESTINATIONS[$i]}
        FILE=${ALL_FILES[$i]}

        if [[ ! -d $DESTINATION ]]; then
            mkdir -p $DESTINATION
        fi

        if [[ -f $FILE ]]; then
            cp "$FILE" "$DESTINATION"
        else
            echo "File not found: $FILE"
        fi
    done
}

install_restore_spaces MODULE_FILES DESTINATIONS