#!/bin/bash
ssh -i ${ssh_key_private_path} ec2-user@${node_ip} -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q ec2-user@${cluster_ip}'