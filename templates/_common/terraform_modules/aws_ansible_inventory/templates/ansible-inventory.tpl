[all:vars]
domain=${domain}
stackable_user=${stackable_user}
stackable_user_home=${stackable_user_home}

[bastion_host]
${cluster_ip}

[bastion_host:vars]
ansible_user=${stackable_user}
ansible_ssh_private_key_file=${ssh_key_private_path}
wireguard=${wireguard}
ansible_become=yes

[nodes]
%{ for index, node in nodes ~}
${node.tags["hostname"]} ansible_host=${node.private_ip} stackable_agent=${node.tags["has_agent"]}
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
