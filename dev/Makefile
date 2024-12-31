
.EXPORT_ALL_VARIABLES:

.PHONY: load-kernel-modules
load-kernel-modules:
	sudo modprobe -v iptable_filter
	sudo modprobe -v ip_tables
	sudo modprobe -v iptable_mangle
	sudo modprobe -v iptable_raw
	sudo modprobe -v iptable_nat
	sudo modprobe -v xt_socket

.PHONY: create-k3d
create-k3d:
	./create_cluster.sh

.PHONY: delete-k3d
delete-k3d:
	k3d cluster delete picluster

.PHONY: helm-setup
helm-setup:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add cilium https://helm.cilium.io/
	helm repo add coredns https://coredns.github.io/helm
	helm repo add istio https://istio-release.storage.googleapis.com/charts
	helm repo update

.PHONY: cluster-setup
cluster-setup:
	helmfile --quiet --file helmfile.yaml apply --skip-diff-on-install --suppress-diff
	kubectl kustomize ../kubernetes/platform/cilium/config/overlays/dev | kubectl apply -f -

.PHONY: cluster-bootstrap
cluster-bootstrap:
	kubectl kustomize  \
      ../kubernetes/clusters/bootstrap/flux | kubectl apply -f -
	kubectl kustomize  \
      ../kubernetes/clusters/dev/config | kubectl apply -f -
