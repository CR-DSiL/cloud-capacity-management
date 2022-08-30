## Please provide the variable values for terraform to create GKE cluster with default network.

gcp_credentials     = "/absolute/path/to/account.json"
gcp_project_id      = "project id"
gcp_region          = "region of the cluster"
gcp_zones           = ["List of zones of the cluster"]
gcp_network         = "default"
gcp_subnetwork      = "default"
gcp_machine_type    = "machine type of the node"
gcp_nodepool_name   = "name of the node pool"
gcp_disk_type       = "disk type of the nodes"
gcp_service_account = "service account name@project id.iam.gserviceaccount.com"
gcp_nodepool_min = "nodepool minimum number of node required"
gcp_nodepool_max = "nodepool maximum number of node required"
gcp_nodepool_ssd = "node ssd"
gcp_nodepool_disk_size = "node disk size"
gcp_nodepool_initial_node_count = "initial node count"