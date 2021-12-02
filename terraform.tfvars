################################### EKS Cluster Generic instance values#################################
region                               = "us-west-2"
cluster_name                         = "poc-eks-dev"
cluster_version                      = "1.21"
windows_node_instance_type           = "c4.large"
eks_vpc_subnet_ids                   = ["subnet-subnet-id-1", "subnet-subnet-id-2", "subnet-subnet-id-3"]
eks_vpc_security_group_ids           = ["security-group-id-1", "security-group-id-2"]
