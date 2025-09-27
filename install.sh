talosctl apply-config --insecure --mode=interactive --nodes 192.168.8.161

export CONTROL_PLANE_IP=192.168.8.161
export WORKER_IP=("192.168.8.162" "192.168.8.163")
export CLUSTER_NAME=pissiCluster

talosctl get disks --insecure --nodes $CONTROL_PLANE_IP
export DISK_NAME=nvme

talosctl gen config $CLUSTER_NAME https://$CONTROL_PLANE_IP:6443 --install-disk /dev/$DISK_NAME

talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file controlplane.yaml

for ip in "${WORKER_IP[@]}"; do
    echo "Applying config to worker node: $ip"
    talosctl apply-config --insecure --nodes "$ip" --file worker.yaml
done

talosctl --talosconfig=./talosconfig config endpoints $CONTROL_PLANE_IP

talosctl bootstrap --nodes $CONTROL_PLANE_IP --talosconfig=./talosconfig

talosctl kubeconfig --nodes $CONTROL_PLANE_IP --talosconfig=./talosconfig

talosctl --nodes $CONTROL_PLANE_IP --talosconfig=./talosconfig health

kubectl get nodes



