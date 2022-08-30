# terraform module for K8s cluster with default network
module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google"
  version                    = "22.0.0"
  project_id                 = var.gcp_project_id
  name                       = "${var.environment}-microservices-cluster"
  region                     = var.gcp_region
  ip_range_pods              = ""
  ip_range_services          = ""
  zones                      = var.gcp_zones
  network                    = var.gcp_network
  subnetwork                 = var.gcp_subnetwork
  http_load_balancing        = false
  network_policy             = false
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = false

  node_pools = [
    {
      name               = var.gcp_nodepool_name
      machine_type       = var.gcp_machine_type
      min_count          = var.gcp_nodepool_min
      max_count          = var.gcp_nodepool_max
      local_ssd_count    = var.gcp_nodepool_ssd
      disk_size_gb       = var.gcp_nodepool_disk_size
      disk_type          = var.gcp_disk_type
      image_type         = "COS_CONTAINERD"
      enable_gcfs        = false
      auto_repair        = true
      autoscaling        = true
      auto_upgrade       = true
      service_account    = var.gcp_service_account
      preemptible        = false
      initial_node_count = var.gcp_nodepool_initial_node_count
    },
  ]

  node_pools_oauth_scopes = {
    all = []

    default-node-pool = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  node_pools_labels = {
    all = {}

    default-node-pool = {
      default-node-pool = false
    }
  }

  node_pools_metadata = {
    all = {}

    default-node-pool = {
      node-pool-metadata-custom-value = "my-node-pool"
    }
  }

  node_pools_taints = {
    all = []

    default-node-pool = [
      {
        key    = "default-node-pool"
        value  = false
        effect = "PREFER_NO_SCHEDULE"
      },
    ]
  }

  node_pools_tags = {
    all = []

    default-node-pool = [
      "default-node-pool",
    ]
  }
}
