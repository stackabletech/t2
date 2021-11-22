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
public_network_interface_name=eth0
private_network_interface_name=eth0

[nodes]
%{ for index, node in nodes ~}
${node.tags["hostname"]} ansible_host=${node.private_ip} k8s_node=${node.tags["k8s_node"]}
%{ endfor ~}

[nodes:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${ssh_key_private_path} -W %h:%p -q ${stackable_user}@${cluster_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=${stackable_user}
ansible_become=yes

[orchestrators]
orchestrator ansible_host=${orchestrator.private_ip}

[orchestrators:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${ssh_key_private_path} -W %h:%p -q ${stackable_user}@${cluster_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=${stackable_user}
ansible_become=yes

[protected:children]
nodes
orchestrators
