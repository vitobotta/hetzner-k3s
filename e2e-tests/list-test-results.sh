#!/bin/sh
for T in test-*; do
  printf "%s\t%s\t%s\t%s\t%s\n" \
    "$(cat $T/config)" \
    "$(cat $T/args)" \
    "$(cat $T/result)" \
    "$(cat $T/status)" \
    "$T"
done | sort | column -t -s "	"
