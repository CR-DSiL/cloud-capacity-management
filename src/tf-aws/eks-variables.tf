variable "aws_cluster_name" {
    type = string
    description = "AWS Cluster Name"  
}

variable "aws_cluster_version" {
    type = string
    description = "AWS Cluster Version"
}

variable "aws_vpc_id" {
    type = string
    description = "AWS VPC ID"  
}

variable "aws_subnet_ids" {
  type        = list(string)
  description = "AWS subnets list"
}

variable "aws_instance_types" {
  type        = list(string)
  description = "AWS instacnes type list"
}