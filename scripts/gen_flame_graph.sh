#!/bin/bash
# cd "$( dirname "${BASH_SOURCE[0]}" )"
$( dirname "${BASH_SOURCE[0]}" )/flamegraph.pl $1 > $2
