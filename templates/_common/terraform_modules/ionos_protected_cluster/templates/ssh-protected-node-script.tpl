#!/bin/bash
ssh -i ${ssh_key_private_path} root@${node_ip} -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q root@${nat_public_ip}'