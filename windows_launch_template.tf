resource "aws_iam_instance_profile" "windows-node-role" {
  name     = "windows-worker-node-Role"
  role     = "arn:aws:iam::1234567890:role/windows-worker-node-Role"
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
      "k8s.io/cluster-autoscaler/${var.cluster_name}" =	"owned"
      "k8s.io/cluster-autoscaler/enabled"             = "true"
      "eks:cluster-name"                              =	var.cluster_name
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