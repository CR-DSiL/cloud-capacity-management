## Please read variable descriptions for explanation of their purpose.
variable "gcp_credentials" {
   type        = string
   description = "Location of the credential keyfile"
 }

variable "gcp_project_id" {
  type        = string
  description = "GCP Project id"
}

variable "gcp_region" {
  type        = string
  description = "GCP region"
}

variable "environment" {
  type        = string
  description = "Short name for environment"
}

variable "gcp_zones" {
  type        = list(string)
  description = "GCP zones list"
}

variable "gcp_network" {
  type        = string
  description = "GCP network name"
}

variable "gcp_subnetwork" {
  type        = string
  description = "GCP Subnetwork name"
}

variable "gcp_nodepool_name" {
  type        = string
  description = "GCP node pool name"
}

variable "gcp_machine_type" {
  type        = string
  description = "GCP Machine type"
}

variable "gcp_disk_type" {
  type        = string
  description = "GCP Disk Type"
}

variable "gcp_service_account" {
  type        = string
  description = "GCP Service account name"
}

variable "gcp_nodepool_min" {
  type = string
  description = "Node Pool minimum count"
}

variable "gcp_nodepool_max" {
  type = string
  description = "Node Pool maximum count"  
}

variable "gcp_nodepool_ssd" {
  type = string
  description = "Node Pool SSD"  
}

variable "gcp_nodepool_disk_size" {
  type = string
  description = "Node Pool Disk Size"  
}

variable "gcp_nodepool_initial_node_count" {
  type = string
  description = "Initial Node Count"  
}