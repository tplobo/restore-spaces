#!/bin/zsh

MODULE_FILES=(
    "init.lua"
    "_restore_spaces.lua"
    "restore_spaces.lua"
    )
DESTINATION=~/.hammerspoon

if [[ ! -d $DESTINATION ]]; then
    mkdir -p $DESTINATION
fi
for FILE in "${MODULE_FILES[@]}"; do
    if [[ -f $FILE ]]; then
        cp "$FILE" "$DESTINATION"
    else
        echo "File not found: $FILE"
    fi
done