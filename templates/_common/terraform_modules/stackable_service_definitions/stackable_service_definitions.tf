terraform {
  required_version = ">= 0.15, < 2.0.0"
}

# list of all the service definitions
locals {
  service_definitions = can(yamldecode(file("cluster.yaml"))["stackableServices"]) ? [
    for n, c in yamldecode(file("cluster.yaml"))["stackableServices"]: {
      name = n
      content = c 
    }
  ] : []
}

# service definition files
resource "local_file" "service-definition" {
  count = length(local.service_definitions)
  filename = "services/${local.service_definitions[count.index].name}.yaml"
  file_permission = "0440"
  content = local.service_definitions[count.index].content
}

