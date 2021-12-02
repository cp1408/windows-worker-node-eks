
data "template_file" "userdata_windows" {
  template = file("./templates/userdata_windows.tpl")

  vars = {
    cluster_name          = data.aws_eks_cluster.cluster.id
    endpoint              = data.aws_eks_cluster.cluster.endpoint
    pre_userdata          = ""
    additional_userdata   = ""
    kubelet_extra_args    = "--register-with-taints='os=windows:NoSchedule'"
    region                = var.region
    cluster_name          = var.cluster_name
  }  
}

