#!/bin/zsh

if [[ -f "init.lua" && -f "restore_spaces.lua" ]]; then
    if [[ ! -d "~/.hammerspoon" ]]; then
        mkdir -p ~/.hammerspoon
    fi
    cp init.lua restore_spaces.lua ~/.hammerspoon
else
    echo "'init.lua' and/or 'restore_spaces.lua' not found."
fi