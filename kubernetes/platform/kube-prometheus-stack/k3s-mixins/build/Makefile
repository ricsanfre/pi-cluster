
.PHONY: k3s-mixins

k3s-mixins:
	docker build --no-cache --target mixins --output out/ .
	mv out/*-rules.yaml ../base/rules/.
	mv out/*.yaml ../base/dashboards/.
