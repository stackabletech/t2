terraform {
  required_version = ">= 0.15, < 2.0.0"
}

# variable file for Ansible
resource "local_file" "ansible-variables-public-ssh-keys" {
  filename = "inventory/group_vars/all/public_ssh_keys.yml"
  content = templatefile("${path.module}/templates/ansible_variables_public_ssh_keys.tpl",
    {
      ssh_client_keys = can(yamldecode(file("cluster.yaml"))["spec"]["publicKeys"]) ? [
        for k in yamldecode(file("cluster.yaml"))["spec"]["publicKeys"]: 
          k
      ] : []
    }
  )
  file_permission = "0440"
}
