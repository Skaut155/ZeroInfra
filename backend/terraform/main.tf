

locals {
  labels = {
    "app.kubernetes.io/name" = "emqx"
  }

  pvc_spec = merge(
    {
      accessModes = ["ReadWriteOnce"]
      resources = {
        requests = {
          storage = var.storage_size
        }
      }
    },
    var.storage_class_name == null ? {} : {
      storageClassName = var.storage_class_name
    }
  )
}

resource "kubernetes_namespace_v1" "mqtt" {
  metadata {
    name = var.namespace
  }
}

# One cookie shared by every broker node. Keep it stable across Terraform runs.
resource "random_password" "node_cookie" {
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "emqx" {
  metadata {
    name      = "emqx-secrets"
    namespace = kubernetes_namespace_v1.mqtt.metadata[0].name
  }

  data = {
    "node-cookie" = random_password.node_cookie.result
  }

  type = "Opaque"
}

resource "kubernetes_manifest" "emqx_service_account" {
  manifest = {
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "emqx"
      namespace = kubernetes_namespace_v1.mqtt.metadata[0].name
    }
  }
}

resource "kubernetes_manifest" "emqx_role" {
  manifest = {
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = "emqx-endpoints-reader"
      namespace = kubernetes_namespace_v1.mqtt.metadata[0].name
    }
    rules = [
      {
        apiGroups = [""]
        resources = ["endpoints"]
        verbs     = ["get", "list", "watch"]
      }
    ]
  }
}

resource "kubernetes_manifest" "emqx_role_binding" {
  manifest = {
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = {
      name      = "emqx-endpoints-reader"
      namespace = kubernetes_namespace_v1.mqtt.metadata[0].name
    }
    subjects = [
      {
        kind      = "ServiceAccount"
        name      = "emqx"
        namespace = kubernetes_namespace_v1.mqtt.metadata[0].name
      }
    ]
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "Role"
      name     = "emqx-endpoints-reader"
    }
  }

  depends_on = [
    kubernetes_manifest.emqx_service_account,
    kubernetes_manifest.emqx_role,
  ]
}

# EMQX uses this headless Service both for stable StatefulSet pod DNS names
# and for Kubernetes endpoint-based cluster discovery.
resource "kubernetes_manifest" "emqx_headless_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "emqx-headless"
      namespace = kubernetes_namespace_v1.mqtt.metadata[0].name
      labels    = local.labels
    }
    spec = {
      clusterIP                  = "None"
      publishNotReadyAddresses   = true
      selector                   = local.labels
      ports = [
        {
          name       = "mqtt"
          port       = 1883
          targetPort = "mqtt"
          protocol   = "TCP"
        },
        {
          name       = "epmd"
          port       = 4370
          targetPort = "epmd"
          protocol   = "TCP"
        },
        {
          name       = "cluster-rpc"
          port       = 5369
          targetPort = "cluster-rpc"
          protocol   = "TCP"
        }
      ]
    }
  }
}

# Client-facing ClusterIP. This deliberately does not expose the internal
# Erlang distribution ports (4370/5369).
resource "kubernetes_manifest" "emqx_client_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "emqx"
      namespace = kubernetes_namespace_v1.mqtt.metadata[0].name
      labels    = local.labels
    }
    spec = {
      type     = "ClusterIP"
      selector = local.labels
      ports = [
        {
          name       = "mqtt"
          port       = 1883
          targetPort = "mqtt"
          protocol   = "TCP"
        },
        {
          name       = "mqtt-tls"
          port       = 8883
          targetPort = "mqtt-tls"
          protocol   = "TCP"
        },
        {
          name       = "websocket"
          port       = 8083
          targetPort = "websocket"
          protocol   = "TCP"
        },
        {
          name       = "websocket-tls"
          port       = 8084
          targetPort = "websocket-tls"
          protocol   = "TCP"
        },
        {
          name       = "dashboard"
          port       = 18083
          targetPort = "dashboard"
          protocol   = "TCP"
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "emqx_stateful_set" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "StatefulSet"
    metadata = {
      name      = "emqx"
      namespace = kubernetes_namespace_v1.mqtt.metadata[0].name
      labels    = local.labels
    }
    spec = {
      serviceName         = "emqx-headless"
      replicas            = 2
      podManagementPolicy = "Parallel"
      updateStrategy = {
        type = "RollingUpdate"
      }
      selector = {
        matchLabels = local.labels
      }
      template = {
        metadata = {
          labels = local.labels
        }
        spec = {
          serviceAccountName            = "emqx"
          automountServiceAccountToken  = true
          terminationGracePeriodSeconds = 60
          securityContext = {
            fsGroup             = 1000
            fsGroupChangePolicy = "OnRootMismatch"
          }
          affinity = {
            podAntiAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = [
                {
                  labelSelector = {
                    matchLabels = local.labels
                  }
                  topologyKey = "kubernetes.io/hostname"
                }
              ]
            }
          }
          containers = [
            {
              name            = "emqx"
              image           = "emqx:5.8.8"
              imagePullPolicy = "IfNotPresent"
              ports = [
                { name = "mqtt",        containerPort = 1883,  protocol = "TCP" },
                { name = "mqtt-tls",    containerPort = 8883,  protocol = "TCP" },
                { name = "websocket",   containerPort = 8083,  protocol = "TCP" },
                { name = "websocket-tls", containerPort = 8084, protocol = "TCP" },
                { name = "dashboard",   containerPort = 18083, protocol = "TCP" },
                { name = "epmd",        containerPort = 4370,  protocol = "TCP" },
                { name = "cluster-rpc", containerPort = 5369,  protocol = "TCP" }
              ]
              env = [
                { name = "EMQX_NAME", value = "emqx" },
                { name = "EMQX_CLUSTER__DISCOVERY_STRATEGY", value = "k8s" },
                { name = "EMQX_CLUSTER__K8S__APISERVER", value = "https://kubernetes.default.svc:443" },
                { name = "EMQX_CLUSTER__K8S__SERVICE_NAME", value = "emqx-headless" },
                { name = "EMQX_CLUSTER__K8S__ADDRESS_TYPE", value = "hostname" },
                { name = "EMQX_CLUSTER__K8S__NAMESPACE", value = var.namespace },
                { name = "EMQX_CLUSTER__K8S__SUFFIX", value = "svc.cluster.local" },
                {
                  name = "EMQX_NODE__COOKIE"
                  valueFrom = {
                    secretKeyRef = {
                      name = kubernetes_secret_v1.emqx.metadata[0].name
                      key  = "node-cookie"
                    }
                  }
                }
              ]
              startupProbe = {
                tcpSocket = { port = 1883 }
                periodSeconds = 10
                failureThreshold = 30
              }
              readinessProbe = {
                tcpSocket = { port = 1883 }
                periodSeconds = 5
                failureThreshold = 3
              }
              livenessProbe = {
                tcpSocket = { port = 1883 }
                periodSeconds = 10
                failureThreshold = 3
              }
              resources = {
                requests = {
                  cpu    = "500m"
                  memory = "1Gi"
                }
                limits = {
                  cpu    = "2"
                  memory = "2Gi"
                }
              }
              volumeMounts = [
                {
                  name      = "emqx-data"
                  mountPath = "/opt/emqx/data"
                }
              ]
            }
          ]
        }
      }
      volumeClaimTemplates = [
        {
          metadata = {
            name = "emqx-data"
          }
          spec = local.pvc_spec
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.emqx_role_binding,
    kubernetes_manifest.emqx_headless_service,
    kubernetes_manifest.emqx_client_service,
    kubernetes_secret_v1.emqx,
  ]
}
