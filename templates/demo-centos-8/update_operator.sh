#!/bin/bash

echo
echo "List of available operators"
echo
{ 
    echo "`sh resources/stackable.sh orchestrator "yum list installed | grep 'stackable'" | grep 'operator-server' | sed 's/stackable-//' | sed 's/-operator-server.x86_64.*//'`" ;
    echo "`sh resources/stackable.sh orchestrator "yum list available | grep 'stackable'" | grep 'operator-server' | sed 's/stackable-//' | sed 's/-operator-server.x86_64.*//'`" ; 
} | sort -u
echo

read -p "Which operator do you want to update? " operator

echo
echo "Reading installed version for stackable-$operator-operator-server.x86_64..."
echo
sh resources/stackable.sh orchestrator "yum list installed stackable-$operator-operator-server.x86_64"
echo
echo "Available versions: "
sh resources/stackable.sh orchestrator "yum list available --showduplicates | grep 'stackable-$operator-operator-server.x86_64'" | awk '{print $2}' | sort -u
echo

read -p "Which version do you want to update to? " version

echo
echo "Running Ansible..."
echo
ansible-playbook update_operator.yml -e "operator=$operator version=$version"