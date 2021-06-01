[all:vars]
domain=${domain}

[nat]
${nat_public_ip} internal_ip=${nat_internal_ip}

[nat:vars]
ansible_user=root 
ansible_ssh_private_key_file=${ssh_key_private_path}

[nodes]
%{ for index, node in nodes ~}
${node.name} ansible_host=${node.primary_ip} stackable_agent=${nodes_has_agent[index]}
%{ endfor ~}

[nodes:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q root@${nat_public_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=root

[orchestrators]
orchestrator ansible_host=${orchestrator.primary_ip}

[orchestrators:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q root@${nat_public_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=root

[protected:children]
nodes
orchestrators
