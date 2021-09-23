terraform {
  required_version = ">= 0.15, < 2.0.0"
}

# The Stackable component versions as defined in the template or cluster definition are translated into
# version strings to be used in the package manager of the target Linux distribution
# (A strange way of programming when you lack proper control structures)
locals {
  # mixes the raw values from (1) defaults as given in the template and (2) cluster definition as provided by the user
  # values from (2) are chosen prior to values from (1)
  stackable_package_versions_raw = can(yamldecode(file("default_versions.yml"))) ? [
    for p,v in yamldecode(file("default_versions.yml")): {
      name = p
      version = can(yamldecode(file("cluster.yaml"))["spec"]["versions"][p]) ? "${yamldecode(file("cluster.yaml"))["spec"]["versions"][p]}" : "${v}"
      processed = false
    }
  ] : []
  # filters the 'NIGHTLY' keyword
  stackable_package_versions_step_1 = [
    for p in local.stackable_package_versions_raw: 
      p.processed ? p :
      {
        name = p.name
        version = p.version == "NIGHTLY" || p.version == "" ? "*" : p.version
        processed = p.version == "NIGHTLY" || p.version == ""
      }
  ]
  # filters the 'RELEASE' keyword
  stackable_package_versions_step_2 = [
    for p in local.stackable_package_versions_step_1: 
      p.processed ? p :
      {
        name = p.name
        version = p.version == "RELEASE" ? "[0-9]*\\.[0-9]*\\.[0-9]" : p.version
        processed = p.version == "RELEASE"
      }
  ]
  # all Versions not treated so far are formatted according to the target package management system
  stackable_package_versions_step_3 = [
    for p in local.stackable_package_versions_step_2: 
      p.processed ? p :
      {
        name = p.name
        version = replace(p.version, "-mr", "~mr")
      }
  ]
  stackable_package_versions = [
    for v in local.stackable_package_versions_step_3: {
      name = v.name
      name_with_version = yamlencode("${v.name}=${v.version}")
    }
  ]
}

# variable file for Ansible containing packages/versions of Stackable components
resource "local_file" "ansible-variables-stackable-packages" {
  filename = "inventory/group_vars/all/stackable_package_versions.yml"
  content = templatefile("${path.module}/templates/stackable-package-versions.tpl",
    {
      stackable_package_versions = local.stackable_package_versions
    }
  )
  file_permission = "0440"
}

