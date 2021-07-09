terraform {
  required_version = ">= 0.15, < 2.0.0"
}

# variable file for Ansible containing packages/versions of Stackable components
resource "local_file" "ansible-variables-stackable-packages" {
  filename = "inventory/group_vars/all/stackable_package_versions.yml"
  content = templatefile("${path.module}/templates/stackable-package-versions.tpl",
    {
      stackable_package_versions = can(yamldecode(file("default_versions.yml"))) ? [
        for k,v in yamldecode(file("default_versions.yml")): {
          name = k
          name_with_version = can(yamldecode(file("cluster.yaml"))["spec"]["versions"][k]) ? yamlencode("${k}=${yamldecode(file("cluster.yaml"))["spec"]["versions"][k]}") : yamlencode("${k}=${v}")
        }
       ] : []
    }
  )
  file_permission = "0440"
}

