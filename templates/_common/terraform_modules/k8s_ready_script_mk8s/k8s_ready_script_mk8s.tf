terraform {
  required_version = ">= 0.15, < 2.0.0"
}

variable "node_count" {
  description = "number of K8s nodes that the readiness test should expect" 
}

variable "timeout" {
  description = "timeout in seconds" 
}

variable "kubeconfig_path" {
  type = string
  description = "Path to kubeconfig file relative to script location"
}

# K8s readiness check script
resource "local_file" "k8s_ready" {
  filename = "wait_for_k8s_nodes_to_be_ready.sh"
  content = templatefile("${path.module}/templates/k8s_ready_script_mk8s.tpl",
    {
      j2_node_count = var.node_count
      j2_timeout = var.timeout
      j2_kubeconfig_path = var.kubeconfig_path
    }
  )
  file_permission = "0770"
} 

