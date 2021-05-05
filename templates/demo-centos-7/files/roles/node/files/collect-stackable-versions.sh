#!/bin/bash

printf "Node $HOSTNAME\n\n" > /tmp/stackable-versions.txt

printf "Python version: " >> /tmp/stackable-versions.txt
python --version &>> /tmp/stackable-versions.txt

printf "Python3 version: " >> /tmp/stackable-versions.txt
python3 --version &>> /tmp/stackable-versions.txt

printf "\n\n" >> /tmp/stackable-versions.txt