#!/bin/zsh

MODULE_FILES=(
    "init.lua"
    "restore_spaces"
)

DESTINATIONS=(
    "$HOME/.hammerspoon"
    "$HOME/.hammerspoon/hs"
)

function install_restore_spaces() {
    local ALL_FILES=("${(@P)1}")
    local ALL_DESTINATIONS=("${(@P)2}")
    #echo "$ALL_FILES"
    #echo "$ALL_DESTINATIONS"

    echo "Installing 'restore_spaces' module..."
    for (( i=1; i<=${#ALL_FILES[@]}; i++ )); do
        DESTINATION=${ALL_DESTINATIONS[$i]}
        FILE=${ALL_FILES[$i]}
        
        echo "Copying $FILE to $DESTINATION"
        if [[ ! -d $DESTINATION ]]; then
            mkdir -p $DESTINATION
        fi

        if [[ -e $FILE ]]; then
            cp -r "$FILE" "$DESTINATION"
        else
            echo "File not found: $FILE"
        fi
    done
    echo "Installed 'restore_spaces' module."
}

install_restore_spaces MODULE_FILES DESTINATIONS