[all:vars]
domain=${domain}
stackable_user=ec2-user

[bastion_host]
${cluster_ip}

[bastion_host:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=${ssh_key_private_path}
wireguard=${wireguard}
ansible_become=yes

[nodes]
%{ for index, node in nodes ~}
${node.tags["hostname"]} ansible_host=${node.private_ip} stackable_agent=${node.tags["has_agent"]}
%{ endfor ~}

[nodes:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q ec2-user@${cluster_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=ec2-user
ansible_become=yes

[orchestrators]
orchestrator ansible_host=${orchestrator.private_ip}

[orchestrators:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q ec2-user@${cluster_ip}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=ec2-user
ansible_become=yes

[protected:children]
nodes
orchestrators
