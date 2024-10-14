#! /usr/bin/bash

set -x

odin build . 2>&1 | cm
