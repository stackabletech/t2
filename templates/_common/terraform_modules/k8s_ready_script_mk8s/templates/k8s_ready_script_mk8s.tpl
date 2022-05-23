#! /bin/bash

target_node_count=${j2_node_count}
timeout=${j2_timeout}

start_time=$(date +%s)

echo "Waiting max. $timeout seconds for $target_node_count nodes to be ready..."
while
    current_time=$(date +%s)
    node_count=$(kubectl --kubeconfig ${j2_kubeconfig_path} get nodes -o yaml | yq '.items | map( select(.status.conditions[] | (.type=="Ready" and .status=="True") ) ) | length')
    echo "$node_count nodes ready after $(( current_time - start_time )) seconds..."
    if (( node_count == target_node_count )); then
        exit 0
    fi
    sleep 5
    (( current_time - start_time < timeout ))
do true; done
echo "Only $node_count nodes ready after $timeout seconds"
exit 1
