
resource "kubernetes_cluster_role" "vpc_resource_controller" {
  metadata {
    name = "vpc-resource-controller"
  }
  rule {
    verbs      = ["update", "get", "list", "watch", "patch", "create"]
    api_groups = [""]
    resources  = ["nodes", "nodes/status", "pods", "configmaps"]
  }
}

resource "kubernetes_cluster_role_binding" "vpc_resource_controller" {
  metadata {
    name = "vpc-resource-controller"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "vpc-resource-controller"
    namespace = "kube-system"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "vpc-resource-controller"
  }
}

##** Note:- Not Required, as it is already created as part of EKS Cluster Creation, Cross-check once. **##
#resource "kubernetes_service_account" "vpc_resource_controller" {
#  metadata {
#    name      = "vpc-resource-controller"
#    namespace = "kube-system"
#  }
#}

resource "kubernetes_config_map" "amazon-vpc-cni_vpc_resource_controller" {
  metadata {
    name = "amazon-vpc-cni"
    namespace = "kube-system"
  }
  data = {
    enable-windows-ipam  = "true"
  }
}

resource "kubernetes_deployment" "vpc_resource_controller" {
  metadata {
    name      = "vpc-resource-controller"
    namespace = "kube-system"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "vpc-resource-controller"
        tier = "backend"
        track = "stable"
      }
    }
    template {
      metadata {
        labels = {
          app = "vpc-resource-controller"
          tier = "backend"
          track = "stable"
        }
      }
      spec {
        container {
          name    = "vpc-resource-controller"
          image   = "602401143452.dkr.ecr.us-west-2.amazonaws.com/eks/windows-vpc-resource-controller:v0.2.7"
          command = ["/vpc-resource-controller"]
          args    = ["-stderrthreshold=info"]
          liveness_probe {
            http_get {
              path   = "/healthz"
              port   = "61779"
              host   = "127.0.0.1"
              scheme = "HTTP"
            }
            initial_delay_seconds = 30
            timeout_seconds       = 5
            period_seconds        = 30
            failure_threshold     = 5
          }
          image_pull_policy = "Always"
          security_context {
            privileged = true
          }
        }
        node_selector = {
          "beta.kubernetes.io/arch" = "amd64"
          "beta.kubernetes.io/os" = "linux"
        }
        host_network = true
      }
    }
  }
  depends_on = [null_resource.create-signed-cert]
}
