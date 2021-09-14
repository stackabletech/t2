#!/bin/bash

echo
echo "List of available operators"
echo
sh resources/stackable.sh orchestrator "apt update"
echo
sh resources/stackable.sh orchestrator "apt list stackable-* 2> /dev/null" | grep 'operator' | sed 's/stackable-//' | sed 's/-operator.*//'
echo
echo

read -p "Which operator do you want to update? " operator

echo
echo "Reading installed version for stackable-$operator-operator..."
echo
sh resources/stackable.sh orchestrator "apt list -a stackable-$operator-operator 2> /dev/null"
echo
echo "(If no version is marked as 'installed', the operator is not present in the cluster.)"

read -p "Which version do you want to update to/install? " version

echo
echo "Running Ansible..."
echo
ansible-playbook update_operator.yml -e "operator=$operator version=$version"