#!/bin/bash
ssh -i ${ssh_key_private_path} ${stackable_user}@${node_ip} -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q ${stackable_user}@${cluster_ip}'