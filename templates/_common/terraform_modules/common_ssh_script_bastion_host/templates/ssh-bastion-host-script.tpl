#!/bin/bash
ssh -i ${ssh_key_private_path} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${user}@${ip}