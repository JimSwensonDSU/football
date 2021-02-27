#!/bin/sh

if [ "$1" == "" ]; then
   ./football
elif [ "$1" == "man" ]; then
   nroff -man football.6 | less
else
   ./football $1
fi
