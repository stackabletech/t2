terraform {
  required_version = ">= 0.15, < 2.0.0"
}

# The Stackable component versions as defined in the cluster definition are translated into
# version strings to be used to find the matching helm charts
# (A strange way of programming, but that happens when you lack proper control structures)
locals {
  # "raw" dictionary with the values from the cluster definition
  stackable_component_versions_raw = can(yamldecode(file("cluster.yaml"))["spec"]["stackableVersions"]) ? [
    for p,v in yamldecode(file("cluster.yaml"))["spec"]["stackableVersions"]: {
      name = p
      version = yamldecode(file("cluster.yaml"))["spec"]["stackableVersions"][p]
      processed = false
    }
  ] : []
  # filters the 'NIGHTLY' keyword
  stackable_component_versions_step_1 = [
    for p in local.stackable_component_versions_raw: 
      p.processed ? p :
      {
        name = p.name
        version = p.version == "NIGHTLY" || p.version == "" ? ">0.0.0-0" : p.version
        processed = p.version == "NIGHTLY" || p.version == ""
      }
  ]
  # filters the 'RELEASE' keyword
  stackable_component_versions_step_2 = [
    for p in local.stackable_component_versions_step_1: 
      p.processed ? p :
      {
        name = p.name
        version = p.version == "RELEASE" ? "" : p.version
        processed = p.version == "RELEASE"
      }
  ]
  # set repository according to version number string
  stackable_component_versions_step_3 = [
    for p in local.stackable_component_versions_step_2: 
      {
        name = p.name
        version = p.version
        repository = replace(p.version, "-", "") == p.version ? "stable" : replace(p.version, "-pr", "") == p.version ? "dev" : "test"
      }
  ]
  stackable_component_versions = [
    for c in local.stackable_component_versions_step_3: {
      name = c.name
      repository = c.repository
      version = yamlencode("${c.version}")
    }
  ]
}

# variable file for Ansible containing versions of Stackable components
resource "local_file" "ansible-variables-stackable-components" {
  filename = "inventory/group_vars/all/stackable_component_versions.yml"
  content = templatefile("${path.module}/templates/stackable-component-versions.tpl",
    {
      stackable_component_versions = local.stackable_component_versions
    }
  )
  file_permission = "0440"
}

