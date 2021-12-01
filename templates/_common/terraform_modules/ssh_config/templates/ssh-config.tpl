LogLevel ERROR
User ${username}
StrictHostKeyChecking no
UserKnownHostsFile /dev/null    

Host orchestrator   
    HostName ${orchestrator_ip}
    ProxyCommand ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p -q ${username}@${cluster_ip}

%{ for node in nodes ~}
Host ${node.name}
    HostName ${node.ip}
    ProxyCommand ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p -q ${username}@${cluster_ip}

%{ endfor ~}
