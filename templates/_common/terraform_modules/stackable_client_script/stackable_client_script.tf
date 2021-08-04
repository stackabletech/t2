terraform {
  required_version = ">= 0.15, < 2.0.0"
}

variable "nodes" {
  type = list(object({ name=string, ip=string }))
}

variable "orchestrator_ip" {
  type = string
}

variable "cluster_ip" {
  type = string
}

variable "ssh-username" {
  type = string
}

# stackable client script
resource "local_file" "stackable-client" {
  filename = "resources/stackable.sh"
  content = templatefile("${path.module}/templates/stackable-client-script.tpl",
    {
      nodes = var.nodes
      orchestrator_ip = var.orchestrator_ip
      cluster_ip = var.cluster_ip
      username = var.ssh-username
    }
  )
  file_permission = "0550"
} 


