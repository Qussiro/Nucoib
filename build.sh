#! /usr/bin/bash

if [ $# -eq 0 ]; then
    set -x
    odin build .
elif [ $1 = 'run' ]; then
    set -x
    odin run .
elif [ $1 = 'vet' ]; then
    set -x
    odin build . -vet-unused -vet-unused-variables -vet-unused-imports -vet-style -vet-semicolon -vet-cast
else
    echo 'Unknown option: '$1
fi
