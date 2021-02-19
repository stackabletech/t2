#!/bin/bash
ssh root@${node_ip} -o ProxyCommand='ssh -o StrictHostKeyChecking=no -i ${ssh_key_private_path} -W %h:%p -q root@${nat_public_hostname}'