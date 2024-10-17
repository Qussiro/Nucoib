#! /usr/bin/bash

set -x

./build.sh $1 2>&1 | cm
