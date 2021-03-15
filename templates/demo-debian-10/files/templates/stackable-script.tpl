#!/bin/sh 

if [ -z "$1" ]; then
    echo "Please supply node name."
    exit 1
fi

host=$1

%{ for nodetype in nodetypes ~}
%{ for node in nodes[nodetype] ~}
if [ "${node.name}" = "$host" ]; then
    ip="${node.primary_ip}"
fi

%{ endfor ~}
%{ endfor ~}

if [ "orchestrator" = "$host" ]; then
    ip="${orchestrator.primary_ip}"
fi

if [ -z "$ip" ]; then
    echo "Node unknown."
    exit 1
fi

if [ -z "$2" ]; then
    echo "Please supply private key file."
    exit 1
fi

private_key_file=$2

ssh root@"$ip" -i "$private_key_file" -o StrictHostKeyChecking=no -o ProxyCommand='ssh -i '"$private_key_file"' -o StrictHostKeyChecking=no -W %h:%p -q root@${nat_public_hostname}' $3
