# Windows-Worker-Node-Terraform-Automation

This repo  will help to automate windows worker nodes into existing EKS Clusters using terraform.

## Prerequisites :-

1. An EKS Cluster ≥ 1.14 running at least 1 Linux worker Node (created using Terraform preferably).
2. EKS Windows Worker Node Instance IAM Role.
3. Fetch the kubeconfig file of EKS Cluster to access the Cluster from terraform.

## Objects will be created as below :-

1. Webhook signed cert, csr, secret creation. ([create-signed-cert.tf](create-signed-cert.tf))

2. VPC Admission webhook deployment creation. ([vpc-admission-webhook-deploy.tf](vpc-admission-webhook-deploy.tf))

3. VPC Resource controller deployment creation. ([vpc-resource-controller.tf](vpc-resource-controller.tf))

4. Get windows worker nodes image id. i.e ami-id ([windows_image.tf](windows_image.tf))

5. AWS Windows Launch template with aws iam instance profile creation. ([windows_launch_template.tf](windows_launch_template.tf))

6. AWS Autoscaling group creation. ([aws_autoscaling_group.tf](aws_autoscaling_group.tf))

## Templates tested for EKS Cluster version

1. EKS Cluster Version: 1.21
2. VPC Resource Controller Version: v0.2.7
3. VPC Admission Webhook Version: v0.2.7

## Steps to Execute :-

1. Set the aws environment values in terraform.tfvars ([terraform.tfvars](terraform.tfvars)) file. e.g aws_region, subnets, security_groups, cluster_name etc.
2. Export AWS access-id, secret & token credentials
3. Append the aws-auth file to add windows_worker_node_instance_role. e.g ([aws-auth.yaml](aws-auth.yaml))
4. Terraform init
5. Terraform plan
6. Terraform apply -auto-approve

#### Note:- If you want to run terraform from cicd gitlab, place these templates in a repo gitlab project and use .gitlab-ci.yml ([.gitlab-ci.yml](.gitlab-ci.yml))



#### Step 1: Create a secret for secure communication
---

```
resource "null_resource" "create-signed-cert" {
provisioner "local-exec" {
    command = "./templates/webhook-create-signed-cert.sh"
  }
}
```

#### Step 2: Create the VPC admission controller webhook manifest for your cluster
---
```
resource "null_resource" "vpc-admission-webhook-kubectl" {
  provisioner "local-exec" {
  command = "kubectl apply -f ./.rendered/vpc-admission-webhook.yaml"
  } 
}

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
```

#### Step 3: Deploy the VPC resource controller to your cluster
---
```
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
```

#### Step 4: Get the latest Windows AMI provided by AWS from SSM agent
---
```
data "aws_ssm_parameter" "eks_worker_windows" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Core-EKS_Optimized-${var.cluster_version}/image_id"
}
```

#### Step 5: This Userdata script will be called out in launch template with rendered variable data and values to enable worker nodes to join  existing EKS Cluster with any extra ARGS
---
```
data "template_file" "userdata_windows" {
  template = file("./templates/userdata_windows.tpl")
  vars = {
    cluster_name        = data.aws_eks_cluster.cluster.id
    endpoint            = data.aws_eks_cluster.cluster.endpoint
    pre_userdata        = ""
    additional_userdata = ""
    kubelet_extra_args  = "--register-with-taints='os=windows:NoSchedule'"
    region              = var.region
    cluster_name        = var.cluster_name
  }
}
```

#### Step 6: Create AWS Launch Template for Worker Nodes with iam_instance_profile
---
```
resource "aws_iam_instance_profile" "windows-node-role" {
  name     = "windows-worker-node-role"
  role     = "arn:aws:iam::1234567890:role/windows-worker-node-role"
  path     = "/"
  lifecycle { create_before_destroy = true }
}

data "aws_iam_instance_profile" "windows-instance-profile" {
  name = "windows-worker-node-Role"
}

resource "aws_launch_template" "workers" {
name                      = "Windows_worker_nodes_launch_template-${var.cluster_name}"
image_id                  = data.aws_ssm_parameter.eks_worker_windows.id
#image_id                 = "ami-091e73687778fb295" #AmazonEKSoptimizedWindowsServer2019CoreAMI #"ami-031a195a9dcb6f78b" old one
instance_type             = var.windows_node_instance_type
vpc_security_group_ids    = var.eks_vpc_security_group_ids
key_name                  = "keypair-eks"

# Use the user_data
user_data                = base64encode(data.template_file.userdata_windows.rendered)

monitoring {
    enabled = true
  }
  block_device_mappings {
      device_name           = "/dev/sda1"
  ebs {
      volume_size           = "50"
      delete_on_termination = true
      volume_type           = "gp2"
    }
  }

  tag_specifications {
      resource_type         = "instance"
      tags = {
      Name                                            = "windows-node-${var.cluster_name}"
      "kubernetes.io/cluster/${var.cluster_name}"     = "owned"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled"             = "true"
      "eks:cluster-name"                              = var.cluster_name
    }
  }

  tag_specifications {
      resource_type         = "volume"
      tags = {
      Name                  = "windows-workernode-volume-${var.cluster_name}"
    }
  }

  iam_instance_profile {
    name = data.aws_iam_instance_profile.windows-instance-profile.name
  }
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [kubernetes_deployment.vpc_admission_webhook_deployment, kubernetes_deployment.vpc_resource_controller, kubernetes_mutating_webhook_configuration.vpc_admission_webhook_cfg, null_resource.create-signed-cert]
}
```

#### Step 7: Create Autoscaling Group
---
```
resource "aws_autoscaling_group" "workers" {
  
  name              = "windows_worker_nodes_asg-${var.cluster_name}"
  desired_capacity  = 2
  max_size          = 5
  min_size          = 2
  launch_template {
    id              = aws_launch_template.workers.id
    version         = "$Latest"
  }
  vpc_zone_identifier     = var.eks_vpc_subnet_ids
  health_check_type       = "EC2"
  tag {
    key                   = "Name"
    value                 = "windows_worker_node-${var.cluster_name}"
    propagate_at_launch   = true
  }
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity, target_group_arns]
  }
  depends_on = [aws_launch_template.workers]
}
```
