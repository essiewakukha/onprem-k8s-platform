SHELL := /bin/bash
ANSIBLE_DIR := ansible
CHART := charts/notes-api
K8S_SCHEMA_VERSION ?= 1.36.0

.PHONY: help
help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ------------------------------------------------------------------ cluster
.PHONY: deps
deps: ## Install Ansible and collections on this machine
	python3 -m pip install -r $(ANSIBLE_DIR)/requirements.txt
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml

.PHONY: ping
ping: ## Check SSH + sudo to every node
	cd $(ANSIBLE_DIR) && ansible k8s_cluster -m ansible.builtin.ping -b

.PHONY: cluster
cluster: ## Build or converge the whole cluster (idempotent)
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml

.PHONY: verify
verify: ## Health-check the cluster
	KUBECONFIG=artifacts/admin.conf ./scripts/verify-cluster.sh

.PHONY: versions
versions: ## Record exact running versions to VERSIONS.lock.md
	KUBECONFIG=artifacts/admin.conf ./scripts/record-versions.sh > VERSIONS.lock.md

.PHONY: ci-kubeconfig
ci-kubeconfig: ## Create the namespace-scoped kubeconfig for GitHub Actions
	KUBECONFIG=artifacts/admin.conf ./scripts/create-deployer-kubeconfig.sh

.PHONY: reset
reset: ## DESTROY the cluster on all nodes
	cd $(ANSIBLE_DIR) && ansible-playbook reset.yml -e confirm_reset=yes

# --------------------------------------------------------------------- app
.PHONY: test
test: ## Run app unit tests
	cd app && npm test

.PHONY: deploy
deploy: ## Deploy IMAGE_TAG=<tag> with Helm (rollback on failure)
	./scripts/deploy.sh

# -------------------------------------------------------------------- lint
.PHONY: lint
lint: ## Lint chart, manifests, Ansible and shell scripts
	helm lint $(CHART) --strict -f $(CHART)/values-production.yaml
	helm template notes-api $(CHART) -f $(CHART)/values-production.yaml --set image.tag=ci \
	  | kubeconform -strict -summary -kubernetes-version $(K8S_SCHEMA_VERSION)
	kubeconform -strict -summary -kubernetes-version $(K8S_SCHEMA_VERSION) platform/
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --syntax-check && ansible-lint site.yml reset.yml
	shellcheck scripts/*.sh lab/*.sh