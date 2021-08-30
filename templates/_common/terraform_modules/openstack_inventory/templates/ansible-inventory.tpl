[all:vars]
domain=${domain}
stackable_user=${stackable_user}
stackable_user_home=${stackable_user_home}

[bastion_host]
bastion_host ansible_host=${cluster_ip}

[bastion_host:vars]
ansible_user=${stackable_user}
ansible_ssh_private_key_file=${ssh_key_private_path}
wireguard=${wireguard}
ansible_become=yes
internal_ip=${bastion_host_internal_ip}

[orchestrators]
orchestrator ansible_host=${orchestrator.access_ip_v4}

[orchestrators:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q ${stackable_user}@${cluster_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=${stackable_user}
ansible_become=yes

[nodes]
%{ for index, node in nodes ~}
${node.metadata["hostname"]} ansible_host=${node.access_ip_v4} stackable_agent=${node.metadata["has_agent"]}
%{ endfor ~}

[nodes:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q ${stackable_user}@${cluster_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=${stackable_user}
ansible_become=yes

[protected:children]
orchestrators
nodes