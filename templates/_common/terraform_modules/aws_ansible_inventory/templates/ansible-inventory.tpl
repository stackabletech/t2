[all:vars]
domain=${domain}
k8s_requested_version=${k8s_requested_version}
stackable_user=${stackable_user}
stackable_user_home=${stackable_user_home}

[edge]
edge ansible_host=${cluster_ip}

[edge:vars]
ansible_user=${stackable_user}
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_become=yes
public_network_interface_name=eth0
private_network_interface_name=eth0

[nodes]
%{ for index, node in nodes ~}
${node.tags["hostname"]} ansible_host=${node.private_ip} node_number=${index+1}
%{ endfor ~}

[orchestrators]
orchestrator ansible_host=${orchestrator.private_ip}

[protected:children]
nodes
orchestrators

[protected:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${ssh_key_private_path} -W %h:%p -q ${stackable_user}@${cluster_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=${stackable_user}
ansible_become=yes
private_network_interface_name=eth0
