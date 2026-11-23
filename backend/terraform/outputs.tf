output "mqtt_service" {
  description = "In-cluster MQTT endpoint."
  value       = "emqx.${var.namespace}.svc.cluster.local:1883"
}

output "mqtt_tls_service" {
  description = "In-cluster MQTT over TLS endpoint (configure certificates before using it)."
  value       = "emqx.${var.namespace}.svc.cluster.local:8883"
}

output "dashboard_service" {
  description = "In-cluster EMQX Dashboard endpoint. Do not expose publicly without securing it."
  value       = "http://emqx.${var.namespace}.svc.cluster.local:18083"
}

output "pod_names" {
  description = "StatefulSet pod names."
  value       = ["emqx-0", "emqx-1"]
}
