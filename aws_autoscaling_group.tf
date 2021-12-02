
resource "aws_autoscaling_group" "workers" {
  
  name              = "windows_worker_nodes_asg-${var.cluster_name}"
  desired_capacity  = 2
  max_size          = 5
  min_size          = 2

  launch_template {
    id      = aws_launch_template.workers.id
    version = "$Latest"
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