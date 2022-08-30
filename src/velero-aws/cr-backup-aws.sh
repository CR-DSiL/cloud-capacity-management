#!/bin/bash

### VARIABLE DECLARATIONS ###
ignorebackup="infra|spl-con|velero|kube-.*"
veleroPodMemLimit=2Gi
veleroPodMemRequest=512Mi
resticPodMemLimit=5Gi
resticPodMemRequest=2Gi
# veleroGcpPluginVersion=v1.3.0
### VARIABLE DECLARATIONS ###

### INITIALIZATION STEPS ###
CLUSTER_NAME="$1"

# Set default Time To Live value for backup. By default, a backup will be automatically deleted after 60days (1440h)
TTL=${3:-1440h}

bucketNameForVelero="$2"
if [ $# -lt 2 ]; then
        echo -e "\033[31mPlease specify the cluster name and bucket name for Velero.\033[0m"
        echo "Example: backup.sh dev-bes-cluster velerobkpdev"
        exit 1
fi

# Append velerbkp if not there
if [[ "$bucketNameForVelero" != "velerobkp"* ]]; then
        bucketNameForVelero="velerobkp$bucketNameForVelero"
fi

# Create Cloud Bucket 
aws s3api create-bucket --bucket ${bucketNameForVelero} --region us-east-1

# Initialize timeStamp
timestamp=$(date -u +%Y%m%d%H%M%S)

# Set default binaries
kc=$(which kubectl)
# gc=$(which gcloud)
vl=$(which velero)

# Create isolated kubeconfig to avoid congestion
# export KUBECONFIG=./${CLUSTER_NAME}_$$

# # Retrieve zone and cluster name from GKE API
# clusterNameAndZone=$($gc container clusters list --filter=name:"${CLUSTER_NAME}" 2>/dev/null | tail -1 | awk '{print $1" --zone "$2}')

# # Retrieve credentials for cluster
# echo "Retrieving credentials for ${clusterNameAndZone}"
# eval $gc container clusters get-credentials "${clusterNameAndZone}" --project cr-test-356813 2>/dev/null

# Generate a comma separated list of the ignored namespaces based on the regexp
ignorednamespaces="$($kc get namespaces --no-headers | grep -E "${ignorebackup}" | awk '{printf $1" "}' | awk -v RS='[, ]' '!a[$0]++' | paste -sd,)"

# Collect namespaces that will be backed up
namespaces="$($kc get namespaces --no-headers| grep -vE "${ignorebackup}" | awk '{print $1}')"

### FUNCTION DECLARATIONS ###
function warn() { echo -e "\033[33m${@}\033[0m"; }
function info() { echo -e "${@}"; }
function err()  { echo -e "\033[31m${@}\033[0m"; }
function succ() { echo -e "\033[32m${@}\033[0m"; }

function installVeleroOnCluster() {
        $vl uninstall --force
        installer=$($vl install --provider aws --plugins velero/velero-plugin-for-aws:v1.0.1 --use-restic --default-volumes-to-restic --use-volume-snapshots=false --bucket "${bucketNameForVelero}" --velero-pod-mem-limit "${veleroPodMemLimit}" --velero-pod-mem-request "${veleroPodMemRequest}" --secret-file /home/ashokdas_test1/.aws/credentials)
        echo "$installer" | tail -1
        # echo -e "\033[33mPausing for 2 minutes for bucket synchronization...\033[0m"
        warn "Pausing for 2 minutes for bucket synchronization..."
        sleep 120s
}

function restartVelero() {
        $kc get pods -nvelero -owide
        #echo -e "\033[33mRestarting Velero...\033[0m"
        warn "Restarting Velero..."
        $kc delete pods --all -nvelero
        sleep 15
}

function waitUntilBackupsRunning() {
	num=$(velero backup get | grep -cE 'InProgress|New')
	count=0
	while [ "${num}" != "0" ]
	do
		if [ "$count" -gt 60 ]; then
			echo "Other backups are running too long. Exiting backup process..."
			exit 1
		fi
		echo "${num} backups are still running. Waiting..."
		sleep 10
		num=$(velero backup get | grep -cE 'InProgress|New')
		(( count = count + 1 ))
	done
}

function backupAll() {
	# Create backup job for storageclasses
	$vl backup create ${CLUSTER_NAME}-storageclass-${timestamp} --include-resources storageclasses --ttl ${TTL}
	checks="${CLUSTER_NAME}-storageclass-${timestamp}"
	
	# Loop through all namespaces and create a backup job for each of them
	for namespace in ${namespaces}; do
		$vl backup create ${CLUSTER_NAME}-namespace-${namespace}-${timestamp} --include-namespaces $namespace --ttl ${TTL}
		checks="${checks}|${CLUSTER_NAME}-namespace-${namespace}-${timestamp}"
	done

	# Create a full cluster backup for troubleshooting
	$vl backup create ${CLUSTER_NAME}-fullcluster-${timestamp} --exclude-namespaces ${ignorednamespaces} --ttl ${TTL}
	chechs="${checks}|${CLUSTER_NAME}-fullcluster-${timestamp}"
	
	echo "Waiting for backups to complete..."
	
	$vl backup get | grep -E "${checks}" > prev
	cat prev
	while [ $($vl backup get | grep -E "${checks}" | grep -cE "New|InProgress") -ne 0 ]; do
		# Wait until all backup jobs has completed successfully
		$vl backup get | grep -E "${checks}" > curr
		# echo -e "Backups are still in progress..."
		sleep 5
		# Check what has changed in the velero backup command's output
		difference=$(diff -d --suppress-common-lines --color prev curr | grep "^>" | sed 's/^..//')
		if [[ "$difference" != "" ]]; then
			echo -e "\033[0G$difference"
		fi
		cat curr > prev
	done
	echo
}

#  function cleanUp() {
#  	rm -f $KUBECONFIG curr prev
#  }

function exitScript() {
	cleanUp
	[[ "$1" == "0" ]] && ( echo "Backup process successful."; exit 0) || ( echo "Backup process failed. $1 "; exit $1 )
}

function checkAll() {
	results=$($vl backup get | grep -E "${checks}")
	echo "${results}"
	if [[ "$(echo "${results}" | grep -vc "Completed")" -ne 0 ]]; then
		exitScript 1
	else
		exitScript 0
	fi
}
### FUNCTION DECLARATIONS ###

### MAIN SCRIPT ###
if [ "$($kc get namespace velero 2>/dev/null)" = "" ]; then
        #echo -e "\033[33mVelero namespace not found. Installing Velero in cluster...\033[0m"
        warn "Velero namespace not found. Installing Velero in cluster..."
        installVeleroOnCluster
fi
waitUntilBackupsRunning
backupAll
checkAll
