#!/bin/bash
ssh -i ${ssh_key_private_path} ${user}@${node_ip} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q ${user}@${cluster_ip}'
