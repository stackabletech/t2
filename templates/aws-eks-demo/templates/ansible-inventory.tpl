[all:vars]
ansible_user=ec2-user
ansible_become=yes
ansible_ssh_private_key_file=${ssh_key_private_path}
cluster_name=${cluster_name}

[nodes]
%{ for index, node in nodes ~}
node-${index} ansible_host=${node.public_ip} 
%{ endfor ~}

[orchestrator]
orchestrator ansible_host=${orchestrator.public_ip}

[orchestrator:vars]
stackable_user=ec2-user
