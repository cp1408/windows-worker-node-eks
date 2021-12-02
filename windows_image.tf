
data "aws_ssm_parameter" "eks_worker_windows" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Core-EKS_Optimized-${var.cluster_version}/image_id"
}