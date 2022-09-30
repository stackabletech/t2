[all:vars]
domain=${domain}
k8s_version=${k8s_version}
stackable_user=${stackable_user}
stackable_user_home=${stackable_user_home}

[edge]
edge ansible_host=${cluster_ip} internal_ip=${edge_node_internal_ip}

[edge:vars]
ansible_user=${stackable_user}
ansible_ssh_private_key_file=${ssh_key_private_path}
wireguard=${wireguard}
ansible_become=yes

[nodes]
%{ for index, node in nodes ~}
${node.name} ansible_host=${node.primary_ip} k8s_node=${node_configuration[node.name]["k8s_node"]} node_number=${index+1} location=${location} node_size="${node_configuration[node.name]['numberOfCores']} vCPU, ${node_configuration[node.name]['memoryMb']} MB RAM, ${node_configuration[node.name]['diskSizeGb']} GB ${node_configuration[node.name]['diskType']}"
%{ endfor ~}

[orchestrators]
orchestrator ansible_host=${orchestrator.primary_ip} location=${location}

[protected:children]
nodes
orchestrators

[protected:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${ssh_key_private_path} -W %h:%p -q ${stackable_user}@${cluster_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=${stackable_user}
gateway_ip=${nat_gateway_ip}
nameservers=['${edge_node_internal_ip}']
