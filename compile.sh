#!/bin/sh
odin run . -debug -o:none -linker:lld
if [ -f utoml ]; then rm utoml; fi
