[nat]
${nat_public_hostname} internal_ip=${nat_internal_ip}

[nat:vars]
ansible_user=root 
ansible_ssh_private_key_file=${ssh_key_private_path}

%{ for nodetype in nodetypes ~}
[${nodetype}]
%{ for node in nodes[nodetype] ~}
${node.name} ansible_host=${node.primary_ip}
%{ endfor ~}

[${nodetype}:vars]
ansible_ssh_common_args= -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q root@${nat_public_hostname}'
ansible_ssh_private_key_file=${ssh_key_private_path}
ansible_user=root

%{ endfor ~}

[nodes:children]
nat
%{ for nodetype in nodetypes ~}
${nodetype}
%{ endfor ~}
