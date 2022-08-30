# terraform backend to store terraform state file in gcp cloud biucket
terraform {
  backend "gcs" {
    credentials = "/absolute/path/to/account.json"
    bucket      = "gcp cloud bucket name"
    prefix      = "prefix to the file"
  }
}