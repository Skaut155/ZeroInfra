variable "namespace" {
  description = "Kubernetes namespace in which to deploy EMQX."
  type        = string
  default     = "mqtt"
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file used by the Kubernetes provider."
  type        = string
  default     = "~/.kube/config"
}

variable "storage_size" {
  description = "Persistent volume size requested for each EMQX pod."
  type        = string
  default     = "10Gi"
}

variable "storage_class_name" {
  description = "StorageClass for the per-pod PVCs. Null uses the cluster's default StorageClass."
  type        = string
  default     = null
}
