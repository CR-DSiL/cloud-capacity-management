terraform {
    backend "s3" {
      bucket                  = "terraform--backend"
      key                     = "my-terraform-project"
      dynamodb_table          = "terraform-state-lock-dynamo"
      region                  = "us-east-1"
      shared_credentials_file = "/home/ashokdas_test1/.aws/credentials"
    }
  }
  
  provider "aws" {
    region                  = "us-east-1"
    shared_credentials_file = "/home/ashokdas_test1/.aws/credentials"
  }