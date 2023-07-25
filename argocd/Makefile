
CHARTS = external-secrets metallb cert-manager linkerd nginx longhorn-system

.PHONY: crds
crds: 
	kubectl apply --server-side -k bootstrap/crds

.PHONY: $(CHARTS)
$(CHARTS):
	helm dependency update system/$@
	helm upgrade -i $@ system/$@ -f system/$@/values.yaml --namespace $@ --create-namespace


.PHONY: csi-external-snapshotter
csi-external-snapshotter:
	kubectl apply -k system/csi-external-snapshotter