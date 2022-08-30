#!/usr/bin/env bash

### VARIABLE DECLARATIONS ###
ignoredBackupsRegexp="namespace-infra|namespace-spl-con|namespace-velero|fullcluster|kube-.*|vclient|rr-test|consul"
backupOrder="storageclass
namespace-default
namespace-vault.*
namespace-.*"
veleroPodMemLimit=2Gi
veleroPodMemRequest=512Mi
resticPodMemLimit=5Gi
resticPodMemRequest=2Gi
# veleroGcpPluginVersion=v1.3.0
restoreMaxAttempts=1
### VARIABLE DECLARATIONS ###

### INITIALIZATION STEPS ###
CLUSTER_NAME="$1"
bucketNameForVelero="$2"
if [ $# -lt 2 ]; then
        echo -e "\033[31mPlease specify the cluster name and bucket name for Velero.\033[0m"
        echo "Example: restore.sh dev-bes-cluster velerobkpdev"
        exit 1
fi

# Append velerbkp if not there
if [[ "$bucketNameForVelero" != "velerobkp"* ]]; then
        bucketNameForVelero="velerobkp$bucketNameForVelero"
fi

# Create Cloud Bucket 
aws s3api create-bucket --bucket ${bucketNameForVelero} --region us-east-1

# Set default binaries
kc=$(which kubectl)
# gc=$(which gcloud)
vl=$(which velero)

# Initialize timeStamp
timeStamp=$(date -u +%Y%m%d%H%M%S)
epoch=$(date -u +%s)

# Create results folder
mkdir -p results

# Create isolated kubeconfig to avoid congestion
# export KUBECONFIG=./.kubeconfig_$$
# cat /dev/null >$KUBECONFIG

# Retrieve zone and cluster name from GKE API
# clusterNameAndZone=$($gc container clusters list --filter=name:"${CLUSTER_NAME}" 2>/dev/null | tail -1 | awk '{print $1" --zone "$2}')

# Retrieve credentials for cluster
# echo "Retrieving credentials for ${clusterNameAndZone}"
# eval $gc container clusters get-credentials "${clusterNameAndZone}" --project cr-test-356813 2>/dev/null

# ignorednamespaces="$($kc get namespaces --no-headers | grep -E "${ignoredBackupsRegexp}" | awk '{printf "metadata.namespace!="$1" "}' | awk -v RS='[, ]' '!a[$0]++' | paste -sd,)"
O_IFS=$IFS
IFS='
'
### INITIALIZATION STEPS ###

### FUNCTION DECLARATIONS ###

# Colorful console output
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
function getRestoreStatus() {
        restoreid=$1
        $vl restore get "${restoreid}" | tail -1 | awk '{print $3}'
}

function createRestoreJob() {
        backup=$1
        parameters=$2
        id=$(eval $vl restore create --from-backup "${backup}" "${parameters}" | awk '/Restore request/{gsub(/"/,""); print $3}')
        restoreidlist="${restoreidlist}|$id"
        echo "$id"
}

function restoreFromVeleroBackup() {
        backup=$1
        type=$2
        perBackupTimeThreshold=3600

        # Set starting timestamp
        start=$(date +%s)
        restoreattempts=1
        resourcename=
        if [ "$type" = "pv" ]; then
                info "Restoring persistentvolumes from backup ${backup}"
                parameters=" --include-resources persistentvolumeclaims,persistentvolumes"
        else
                info "Restoring backup ${backup}"
                parameters=""
        fi
        # Start restore process and store id in $restoreid
        restoreid=$(createRestoreJob "${backup}" "${parameters}")
        # echo " (RestoreID: ${restoreid})"
        status="$(getRestoreStatus "${restoreid}")"
        # check if Velero backup contains any persistentvolumes 
        expectedpv="$(getPvsInVeleroBackup "${backup}")"
        if [[ "${restoreid}" =~ "storageclass" ]]; then
                # Collect storageclass names if backup contains any
                storageclasses="$(getStorageClassesInVeleroBackup "${backup}")"
        elif [[ "${restoreid}" =~ "namespace" ]]; then
                # Collect pod names if backup is a namespace backup
                pods="$(getPodsInVeleroBackup "${backup}")"
                # Extract namespace name
                ns=$(echo "${pods}" | awk 'BEGIN{FS=" -n "}{print $2}')
                #echo "PODS: #${pods}#"
        fi
        while [[ "$status" == "New" ]] || [[ "$status" == "InProgress" ]]; do
                # Get actual status
                sleep 10s
                status="$(getRestoreStatus "${restoreid}")"
                ((seconds = $(date +%s) - start))
                elapsed=$(date -d@$seconds -u +%Hh:%Mm:%Ss)
                echo -ne "In progress: \033[33m${elapsed}\033[0m"
                # Decide if backup is storageclass or namespace
                if [[ "${restoreid}" =~ "storageclass" ]]; then
                        perBackupTimeThreshold=100
                        storageclassstatus="$(checkStorageClasses "${storageclasses}")"
                        if [ "${storageclassstatus}" != "0" ]; then
                                # If Storageclass is missing, force InProgress, regardless of Restore Status
                                status="InProgress"
                                echo -n " (Waiting for ${storageclassstatus} storageclasses...)"
                        fi
                elif [[ "${restoreid}" =~ "namespace" ]] && [[ "$type" != "pv" ]]; then
                        if [[ "${status}" == "Completed" ]]; then
                                if [[ "${ns}" == "default" ]]; then
                                        podstatus="$(checkPodsInNamespace "${pods}")"
                                        if [ "${podstatus}" != "0" ]; then
                                                if [ $podstatus -lt 4 ]; then
                                                        failingpodsinnamespace="$(listFailingPodsInNamespace "${pods}")"
                                                        echo -n " (Waiting for ${podstatus} pod(s): ${failingpodsinnamespace})"
                                                        if [[ "${failingpodsinnamespace}" =~ "ssp-identity-manager" ]] || [[ "${failingpodsinnamespace}" =~ "fcm-fcm-bes" ]]; then
                                                                echo -n " (Is the database running?)"
                                                        fi
                                                else
                                                        echo -n " (Waiting for ${podstatus} pod(s)...)"
                                                fi
                                                status="InProgress"
                                        fi
                                fi
                        else
                                echo -n " (Waiting for restore to be finished...)"
                        fi
                fi
                echo
                # Check if PV restores are successful
                pvstatus="$(checkPvStatus "$expectedpv")"
                if [ "$seconds" -gt ${perBackupTimeThreshold} ] || [ "$pvstatus" != "0" ]; then
                        # If restore process runs longer than threshold, or Persistent volumes are not restored correctly, delete namespace and restart restore
                        if [ $restoreattempts -gt $restoreMaxAttempts ]; then
                                # If restore attempts exceeds maximum attempts, kill whole restore process
                                #echo -e "\033[31mRestore process restoreattempts exceeded perBackupTimeThreshold (${restoreid}). Exiting.\033[0m"
                                err "Restore process attempts exceeded maximum attempts (${restoreid}). Exiting."
                                $vl restore get "${restoreid}"
                                if [[ "${restoreid}" =~ "namespace" ]] && [[ "$type" != "pv" ]]; then
                                        warn "Restoring of namespaces ${ns} failed."
                                        $kc get pods -n "${ns}"
                                elif [[ "${restoreid}" =~ "storageclass" ]]; then
                                        warn "Restoring of storageclasses failed."
                                        $kc get storageclass
                                fi
                                exit 1
                        fi
                        echo
                        #echo -en "\033[31mRestore process takes too long. Restarting process...\033[0m"
                        err "Restore process takes too long to finish or persistentvolumes failed to restore. Restarting restore..."
                        restartVelero
                        #echo -e "\033[33mDeleting stuck restore process (${restoreid})...\033[0m"
                        warn "Deleting stuck restore process (${restoreid})..."
                        $vl restore delete "${restoreid}" --confirm
                        if [[ "${restoreid}" =~ "namespace" ]]; then
                                deleteNamespace "$(getNamespacesInVeleroBackup "$backup")"
                        fi
                        start=$(date +%s)
                        ((restoreattempts = restoreattempts + 1))
                        restoreid=$(createRestoreJob "${backup}" "${parameters}")
                        #echo -e "\033[33mRestore process restarted (${restoreid}).\033[0m"
                        warn "Restore process restarted (${restoreid})."
                else
                        sleep 10s
                fi
        done
        echo "........................................................................................................"

        $vl restore get "${restoreid}" | awk -F "BACKUP" '/BACKUP/{split($2,a,"CREATED"); spt=length($1); lgt=length(a[1])}{print substr($0,spt+1,lgt+2)}' | awk '{gsub("Completed","\033[32mCompleted\033[0m");gsub("Failed","\033[31mFailed\033[0m")}1'
        echo "........................................................................................................"
}

function patchAllPvToRetain() {
        # Collect all persistent volumes that has a "Delete" reclaimpolicy
        pvs="$($kc get pv | awk '$4~/Delete/{printf $1 " "}')"
        P_IFS="$IFS"
        IFS=' '
        $kc get pv
        pvnum=$(echo "$pvs" | wc -w)
        if [ "$pvnum" -gt 0 ]; then
                echo
                # Patch PV with "Retain" reclaimpolicy
                echo "Patching $(echo "$pvs" | wc -w) persistentVolumes with ReclaimPolicy: Retain"
                IFS=' '
                for pv in ${pvs[@]}; do
                        $kc patch pv "$pv" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
                done
        fi
        IFS="$P_IFS"
}

function getPodsInVeleroBackup() {
# Extract pod names from Velero backup
        backup=$1
        $vl describe backup "${backup}" --details | awk '$1~/v1\//||$0==""{prt=0}prt==1{split($2,a,"/"); namespace=a[1]; printf a[2]" "}$1~/^v1\/Pod:/{prt=1}END{printf " -n "namespace}'
}

function getNamespacesInVeleroBackup() {
# Extract namespace name from Velero backup
        backup=$1
        $vl describe backup "${backup}" --details | awk '$1~/v1\//||$0==""{prt=0}prt==1{printf $2" "}$1~/^v1\/Namespace:/{prt=1}'
}

function getStorageClassesInVeleroBackup() {
# Extract storage class names from Velero backup
        backup=$1
        $vl describe backup "${backup}" --details | awk '$1~/v1\//||$0==""{prt=0}prt==1{printf $2" "}$1~/v1\/StorageClass:/{prt=1}'
}

function checkPodsInNamespace() {
# Check number of pods that are not ready or healthy in the namespace
        input=$1
        pods=$(echo "${input}" | awk 'BEGIN{FS=" -n "}{print $1}')
        ns=$(echo "${input}" | awk 'BEGIN{FS=" -n "}{print $2}')
        if [ "$pods" = "" ]; then
                echo "0"
        else

                podsinns=$($kc get pods --no-headers -n "${ns}" 2>/dev/null)
                errors=0
                P_IFS=$IFS
                IFS=" "
                for pod in ${pods[@]}; do
                        if [ "$(echo "${podsinns}" | grep "^${pod}" | awk 'BEGIN{state=1}{split($2,a,"/"); if (a[1]==a[2])state=0}END{print state}')" != "0" ]; then
                                ((errors = errors + 1))
                        fi
                done
                IFS="$P_IFS"
                echo ${errors}
        fi
}

function listFailingPodsInNamespace() {
# List all pod names that are not ready or healthy in the namespace
        input=$1
        pods=$(echo "${input}" | awk 'BEGIN{FS=" -n "}{print $1}')
        ns=$(echo "${input}" | awk 'BEGIN{FS=" -n "}{print $2}')
        if [ "$pods" = "" ]; then
                echo "0"
        else
                podsinns=$($kc get pods --no-headers -n "${ns}" 2>/dev/null)
                poderrors=""
                P_IFS=$IFS
                IFS=" "
                for pod in ${pods[@]}; do
                        if [ "$(echo "${podsinns}" | grep "^${pod}" | awk 'BEGIN{state=1}{split($2,a,"/"); if (a[1]==a[2])state=0}END{print state}')" != "0" ]; then
                                poderrors="${poderrors} ${pod}"
                        fi
                done
                IFS="$P_IFS"
                echo ${poderrors}
        fi
}


function checkStorageClasses() {
# Check if storageclass exists in cluster
        scs="$1"
        scsinks="$($kc get storageclass --no-headers)"
        errors=0
        P_IFS=$IFS
        IFS=" "
        for sc in ${scs[0]}; do
                if [ "$sc" != "" ] && [ "$(echo "${scsinks}" | awk -v sc="${sc}" 'BEGIN{state=1}$0~"^"sc" "{state=0}END{print state}')" != "0" ]; then
                        ((errors = errors + 1))
                fi
        done
        IFS="$P_IFS"
        echo ${errors}
}

function printResultOverview() {
# Print a summary about restores and results
        echo
        echo "Restore status:"
        $vl restore get | awk -F "BACKUP" '/BACKUP/{split($2,a,"CREATED"); spt=length($1); lgt=length(a[1])}{print substr($0,spt+1,lgt+2)}'
        echo
        echo "Current namespaces:"
        $kc get namespaces
        echo
        echo "Pods and Services:"
        $kc get pods,services --all-namespaces # -A --field-selector ${ignorednamespaces}
        echo
        echo "Available PVs and PVCs:"
        $kc get pv,pvc --all-namespaces # -A --field-selector ${ignorednamespaces}
        echo
        echo "Available StorageClasses:"
        $kc get storageclasses #  -A --field-selector ${ignorednamespaces}

}

function getPvsInVeleroBackup() {
# Extract PV names from Velero backup        
        backup=$1
        #velero describe backup $backup --details | awk 'check==1{if($1!="-")check=0; else print $2}/v1\/PersistentVolumeClaim:/{check=1}'
        $kc -n velero get podvolumebackups -oyaml | grep -B7 "velero.io/backup-name: ${backup}" | awk '/velero.io\/pvc-name/{print $2}'
}

function checkPvStatus() {
# Check all pvc's statuses, if they aren't in Terminating. If they are, give back 500, if everything is OK, return 0
        pvcs=$1

        status="0"
        if [[ "$pvcs" != "" ]]; then
                for pvc in "${pvcs[@]}"; do
                        sleep 6s
                        pv="$($kc get pv 2>/dev/null | grep "$pvc")"
                        if [[ "$(echo "$pv" | awk '/Terminating/{split($6,a,"/");print a[1]}')" != "" ]]; then
                                status="500"
                        fi
                done
        fi
        echo $status
}

function deleteNamespace() {
        namespace=$(echo $1 | awk '{$1=$1};1')
        #echo -e "\033[33mDeleting namespace ${namespace}...\033[0m"
        warn "Deleting namespace ${namespace}..."
        # First delete only the pods
        $kc delete pods --all -n "${namespace}"
        if [ "${namespace}" != "default" ]; then
                # If namespace is not "default", delete it
                eval $kc delete namespace "${namespace}"
        fi
}

# function checkNameSpace() {
#         ns=$1
#         eval $kc get deployments,statefulset,daemonset --no-headers -n"${ns}" | awk 'BEGIN{state=0}{split($2,a,"/"); if (a[1]!=a[2])state=1}END{print state}'
# }
#
# function checkFailingPv() {
#         kubectl get pv | awk '/Terminating/{split($6,a,"/");print a[1]}' | sort -u
# }
#
# function createSchedule() {
#         ns=$1
#         echo "Creating backup schedule..."
#         velero create schedule "${CLUSTER_NAME}"-fullcluster --schedule="@every 24h" --ttl 5760m
# }
#
# function restoreFull() {
#         backup="$(velero backup get | grep "^${CLUSTER_NAME}" | awk '/Completed/{print $1}' | grep "\-fullcluster" | sort | tail -1)"
#         if [ "$backup" == "" ]; then
#                 echo "No backups found. Skipping..."
#         else
#                 echo "Restoring backup $backup"
#                 restoreFromVeleroBackup "${backup}"
#                 failingPv="$(checkFailingPv)"
#                 while [ "$failingPv" != "" ]; do
#                         ns=$(kubectl get pv | awk '/Terminating/{split($6,a,"/");print a[1]}' | sort -u | head -1)
#                         echo "Restore of persistentvolumes failed. Deleting namespace $ns"
#                         deleteNamespace "$ns"
#                         echo "Restarting Velero..."
#                         restartVelero
#                         echo "Restoring namespace $ns"
#                         restoreFromVeleroBackup "${backup}"
#                         failingPv="$(checkFailingPv)"
#                 done
#         fi
# }

function getBackups() {
# Get a sorted list of latest Completed backups based on the order regexp
        backupNotOrdered="$(velero backup get | awk -v cluster="${CLUSTER_NAME}" '/Completed/&&/cluster/{print $1}' | grep -vE "${ignoredBackupsRegexp}" | sort -r | awk -F- '$NF~/20[0-9]{12}/{n=split($0,a,"-");for (i=1;i<n;i++) b=b"-"a[i]; if(b!=prev)print $0; prev=b; b=""}' | sort)"
        if [ "$backupNotOrdered" = "" ]; then
                echo "No backups found. Skipping..."
        else
                O_IFS=$IFS
                IFS='
'
                for search in ${backupOrder[@]}; do
                        while [[ "$(echo "$backupNotOrdered" | grep "$search")" != "" ]]; do
                                backup="$(echo "$backupNotOrdered" | grep "$search" | head -1)"
                                backupOrdered="${backupOrdered}
${backup}"
                                backupNotOrdered=$(echo "$backupNotOrdered" | grep -v "$backup")
                        done
                done
        fi
        echo "$backupOrdered"
}

function startRestoreProcess() {
        backups="$(getBackups)"
        numofbackups=$(echo "$backups" | wc -l)
        if [ "$backups" = "No backups found. Skipping..." ]; then
                #echo -e "\033[31mNo backups found. Restore process failed.\033[0m"
                err "No backups found. Restore process failed."
                exit 1
        else
                echo "Starting restore process... The following ${numofbackups} backups will be restored:"
                echo "$backups"
                O_IFS=$IFS
                IFS='
'
                for search in ${backupOrder[@]}; do
                        while [[ "$(echo "$backups" | grep "$search")" != "" ]]; do
                                backup=$(echo "$backups" | grep "$search" | head -1)
                                echo -e "\033[34m========================================================================================================\033[0m"
                                # Check if there are any persistentvolumes in the Velero Backup
                                expectedpv="$(getPvsInVeleroBackup "$backup")"
                                if [ "$expectedpv" != "" ]; then
                                        # echo -e "Volumes in backup:\n${expectedpv}"
                                        # If PV exists, first restore only the PV
                                        restoreFromVeleroBackup "${backup}" pv
                                        # Check persistentvolume status
                                        pvstatus="$(checkPvStatus "$expectedpv")"
                                        # echo "PV status code: ${pvstatus}"
                                        while [ "${pvstatus}" != "0" ]; do
                                                # If PV is stuck in Terminating status, delete namespace and restart process
                                                ns=$(getNamespacesInVeleroBackup "$backup")
                                                err "Restore of persistentvolumes failed.\033[0m Deleting namespace $ns"
                                                deleteNamespace "$ns"
                                                warn "Restarting Velero..."
                                                restartVelero
                                                info "Restoring namespace $ns"
                                                restoreFromVeleroBackup "${backup}" pv
                                                pvstatus="$(checkPvStatus "$expectedpv")"
                                                info "PV status code: ${pvstatus}"
                                        done
                                fi
                                # Restore Velero backup without filtering anything
                                restoreFromVeleroBackup "${backup}"
                                # Remove actual backup element from list
                                backups=$(echo "$backups" | grep -v "$backup")
                        done
                done
                IFS=$O_IFS
        fi
        echo -e "Restoring backups has finished."
        echo
}

### MAIN SCRIPT ###
if [ "$($kc get namespace velero 2>/dev/null)" = "" ]; then
        #echo -e "\033[33mVelero namespace not found. Installing Velero in cluster...\033[0m"
        warn "Velero namespace not found. Installing Velero in cluster..."
        installVeleroOnCluster
fi
echo "........................................................................................................"
startRestoreProcess
echo -e "\033[33mWaiting 60s for persistentvolumes...\033[0m"
#warn "Waiting 60s for persistentvolumes..."
sleep 60
patchAllPvToRetain
printResultOverview | tee results/results-"${timeStamp}".txt
succ "Restore process has finished."
# rm -f $KUBECONFIG
