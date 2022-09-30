[all:vars]
domain=${domain}
k8s_version=${k8s_version}
stackable_user=${stackable_user}
stackable_user_home=${stackable_user_home}

[edge]
edge ansible_host=${cluster_ip}

[edge:vars]
ansible_user=${stackable_user}
ansible_ssh_private_key_file=${ssh_key_private_path}
wireguard=${wireguard}
ansible_become=yes
internal_ip=${edge_node_internal_ip}

[orchestrators]
orchestrator ansible_host=${element(orchestrator.network[*].ip, 0)} location=${orchestrator.datacenter} public_ip=${orchestrator.ipv4_address}

[nodes]
%{ for index, node in nodes ~}
${node.labels["hostname"]} ansible_host=${element(node.network[*].ip, 0)} k8s_node=${node.labels["k8s_node"]} node_number=${index+1} location=${node.datacenter} node_size=${node.server_type}
%{ endfor ~}

[protected:children]
orchestrators
nodes

[protected:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${ssh_key_private_path} -W %h:%p -q ${stackable_user}@${cluster_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=${stackable_user}
ansible_become=yes
nameservers=['${edge_node_internal_ip}']