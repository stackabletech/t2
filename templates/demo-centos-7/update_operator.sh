#!/bin/bash

echo
echo "List of available operators"
echo
sh resources/stackable.sh orchestrator "yum clean all 1>/dev/null 2>&1"
{ 
    echo "`sh resources/stackable.sh orchestrator "yum list installed 2> /dev/null | grep 'stackable'" | grep 'operator' | sed 's/stackable-//' | sed 's/-operator.x86_64.*//'`" ;
    echo "`sh resources/stackable.sh orchestrator "yum list available 2> /dev/null | grep 'stackable'" | grep 'operator' | sed 's/stackable-//' | sed 's/-operator.x86_64.*//'`" ; 
} | sort -u
echo

read -p "Which operator do you want to update? " operator

echo
echo "Reading installed version for stackable-$operator-operator.x86_64..."
echo
sh resources/stackable.sh orchestrator "yum list installed stackable-$operator-operator.x86_64 2> /dev/null"
echo
echo "Available versions: "
sh resources/stackable.sh orchestrator "yum list available --showduplicates 2> /dev/null | grep 'stackable-$operator-operator.x86_64'" | awk '{print $2}' | sort -u
echo

read -p "Which version do you want to update to? " version

echo
echo "Running Ansible..."
echo
ansible-playbook update_operator.yml -e "operator=$operator version=$version"