#!/bin/sh

if [ "$1" == "" ]; then
   ./football
else
   ./football $1
fi
