#!/bin/sh 

print_usage() {
    echo "stackable.sh [-i <keyfile>] <hostname> [<command>]" 
}

host=""
command=""

while [ -n "$1" ]; do

    if [ "-i" = "$1" ]; then
        if [ -n "$2" ]; then
            private_key_file=$2
            shift
            shift
        else   
            print_usage
            exit 1 
        fi
    else 

        if [ -z "$host" ]; then
            host=$1
            shift
        elif [ -z "$command" ]; then
            command=$1
            shift
        else
            print_usage
            exit 1
        fi

    fi

done

if [ -z "$host" ]; then
    print_usage
    exit 1
fi

%{ for node in nodes ~}
if [ "${node.name}" = "$host" ]; then
    ip="${node.ip}"
fi

%{ endfor ~}

if [ "nodes" = "$host" ]; then
    ip="${nodes[0].ip}"
fi

if [ "orchestrator" = "$host" ]; then
    ip="${orchestrator_ip}"
fi

if [ -z "$ip" ]; then
    echo "Host '$host' unknown in this Stackable cluster."
    exit 1
fi

if [ -n "$private_key_file" ]; then
    ssh ${username}@"$ip" -i "$private_key_file" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand='ssh -i '"$private_key_file"' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p -q ${username}@${cluster_ip}' $command
else 
    ssh ${username}@"$ip" -o StrictHostKeyChecking=no -o ProxyCommand='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p -q ${username}@${cluster_ip}' $command
fi

