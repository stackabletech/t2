#!/bin/bash

echo
echo "Reading installed version for stackable-agent..."
echo
sh resources/stackable.sh nodes "apt list -a stackable-agent 2> /dev/null" | grep stackable
echo
read -p "Which version do you want to update to? " version

echo
echo "Running Ansible..."
echo
ansible-playbook update_agent.yml -e "version=$version"
