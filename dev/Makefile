.EXPORT_ALL_VARIABLES:
K3D_FIX_MOUNTS=1


.PHONY: create-k3d
create-k3d:
	k3d cluster create mycluster -c k3d-cluster.yaml

.PHONY: delete-k3d
delete-k3d:
	k3d cluster delete mycluster

.PHONY: crds-install
crds-install:
	kubectl kustomize --enable-helm --load-restrictor=LoadRestrictionsNone \
	   ../kubernetes/infrastructure/crds/overlays/dev | kubectl apply --server-side -f - 

.PHONY: cilium-install
cilium-install:
	kubectl kustomize --enable-helm --load-restrictor=LoadRestrictionsNone \
	   ../kubernetes/infrastructure/cilium/overlays/dev | kubectl apply -f -

.PHONY: cilium-config
cilium-cofig:
	kubectl kustomize --enable-helm --load-restrictor=LoadRestrictionsNone \
	   ../kubernetes/infrastructure/cilium-config/overlays/dev | kubectl apply -f -

.PHONY: cluster-bootstrap
cluster-bootstrap:
	kubectl kustomize --enable-helm --load-restrictor=LoadRestrictionsNone \
	   ../kubernetes/infrastructure/argocd/overlays/dev | kubectl apply -f -
	kubectl kustomize --enable-helm --load-restrictor=LoadRestrictionsNone \
	   ../kubernetes/bootstrap/argocd/overlays/dev | kubectl apply -f -

.PHONY: argocd-port-forward
argocd-port-forward:
	kubectl port-forward svc/argocd-server 8080:80 -n argocd

.PHONY: get-argocd-passwd
get-argocd-passwd:
	kubectl get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' -n argocd | base64 -d;echo

