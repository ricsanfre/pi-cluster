---

- name: Deploy Argo CD
  shell: |
    kubectl kustomize --enable-helm --load-restrictor=LoadRestrictionsNone \
      ../kubernetes/infrastructure/argocd/overlays/prod | kubectl apply -f -
  args:
    executable: /bin/bash

- name: Wait for CRDs to be ready
  command:
    cmd: "kubectl wait --for condition=Established crd/applications.argoproj.io crd/applicationsets.argoproj.io --timeout=600s"
  changed_when: false

- name: Bootstrap applications
  shell: |
    kubectl kustomize --enable-helm --load-restrictor=LoadRestrictionsNone \
      ../kubernetes/bootstrap/argocd/overlays/prod | kubectl apply -f -
  args:
    executable: /bin/bash
