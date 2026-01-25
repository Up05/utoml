#!/bin/sh
odin build . -debug -o:none -linker:lld && ./utoml
# if [ -f utoml ]; then rm utoml; fi
