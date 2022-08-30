module "eks" {
    source  = "terraform-aws-modules/eks/aws"
    version = "~> 18.0"
  
    cluster_name    = "${var.aws_cluster_name}-microservices-cluster"
    cluster_version = var.aws_cluster_version
  
    cluster_endpoint_private_access = true
    cluster_endpoint_public_access  = true
  
    cluster_addons = {
      coredns = {
        resolve_conflicts = "OVERWRITE"
      }
      kube-proxy = {}
      vpc-cni = {
        resolve_conflicts = "OVERWRITE"
      }
    }
  
    vpc_id     = var.aws_vpc_id
    subnet_ids = var.aws_subnet_ids
  
    eks_managed_node_groups = {
        green = {
        min_size     = 1
        max_size     = 2
        desired_size = 1
  
        instance_types = var.aws_instance_types
        capacity_type  = "SPOT"
      }
    }
  
    tags = {
      Environment = "dev"
      Terraform   = "true"
    }
  }