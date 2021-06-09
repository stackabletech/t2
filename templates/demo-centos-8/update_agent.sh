#!/bin/bash

echo
echo "Reading installed version for stackable-agent.x86_64..."
echo
sh resources/stackable.sh nodes "yum list installed 2> /dev/null | grep 'stackable-agent.x86_64'"
echo
echo "Available versions: "
sh resources/stackable.sh nodes "yum list available --showduplicates 2> /dev/null | grep 'stackable-agent.x86_64'" | awk '{print $2}' | sort -u
echo

read -p "Which version do you want to update to? " version

echo
echo "Running Ansible..."
echo
ansible-playbook update_agent.yml -e "version=$version"