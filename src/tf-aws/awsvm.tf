module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 3.0"

  for_each = toset(["one", "two"])

  name = "instance-${each.key}"

  ami                    = "ami-0cff7528ff583bf9a"
  instance_type          = "t2.micro"
  key_name               = "sayeedcr"
  monitoring             = true
  vpc_security_group_ids = ["sg-05cfe0b6b76ec2ec9"]
  subnet_id              = "subnet-06357da6d85ba9ca2"

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}