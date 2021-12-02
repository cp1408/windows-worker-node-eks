# This data section will collect the existing EKS cluster CA cert data and other informaiton to be used in other section.
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

resource "kubernetes_service" "vpc_admission_webhook_svc" {
  metadata {
    name      = "vpc-admission-webhook-svc"
    namespace = "kube-system"
    labels = {
      app = "vpc-admission-webhook"
    }
  }
  spec {
    port {
      port        = 443
      target_port = "443"
    }
    selector = {
      app = "vpc-admission-webhook"
    }
  }
}

resource "kubernetes_deployment" "vpc_admission_webhook_deployment" {
  metadata {
    name      = "vpc-admission-webhook-deployment"
    namespace = "kube-system"
    labels = {
      app = "vpc-admission-webhook"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "vpc-admission-webhook"
      }
    }
    template {
      metadata {
        labels = {
          app = "vpc-admission-webhook"
        }
      }
      spec {
        volume {
          name = "webhook-certs"

          secret {
            secret_name = "vpc-admission-webhook-certs"
          }
        }
        container {
          name  = "vpc-admission-webhook"
          image = "602401143452.dkr.ecr.us-west-2.amazonaws.com/eks/vpc-admission-webhook:v0.2.7"
          args  = ["-tlsCertFile=/etc/webhook/certs/cert.pem", "-tlsKeyFile=/etc/webhook/certs/key.pem", "-OSLabelSelectorOverride=windows", "-alsologtostderr", "-v=4", "2>&1"]

          volume_mount {
            name       = "webhook-certs"
            read_only  = true
            mount_path = "/etc/webhook/certs"
          }
          image_pull_policy = "Always"
        }
        node_selector = {
          "beta.kubernetes.io/arch" = "amd64"
          "beta.kubernetes.io/os" = "linux"
        }
        host_network = true
      }
    }
    strategy {
      type = "Recreate"
    }
  }

  depends_on = [null_resource.create-signed-cert, kubernetes_deployment.vpc_resource_controller]

}

resource "kubernetes_mutating_webhook_configuration" "vpc_admission_webhook_cfg" {
  metadata {
    name = "vpc-admission-webhook-cfg"
    labels = {
      app = "vpc-admission-webhook"
    }
  }
  webhook {
    name                      = "vpc-admission-webhook.amazonaws.com"
    admission_review_versions = ["v1", "v1beta1"]
    client_config {
      service {
        namespace             = "kube-system"
        name                  = "vpc-admission-webhook-svc"
        path                  = "/mutate"
      }
      ca_bundle = data.aws_eks_cluster.cluster.certificate_authority[0].data
    }
    rule {
      operations   = ["CREATE"]
      api_groups   = [""]
      api_versions = ["v1"]
      resources    = ["pods"]
    }
    failure_policy = "Ignore"
    side_effects   = "None"
  }

  depends_on = [null_resource.create-signed-cert, kubernetes_service.vpc_admission_webhook_svc]

}
