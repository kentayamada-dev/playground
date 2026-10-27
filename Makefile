open_devcontainer := .devcontainer/scripts/open-devcontainer/open-devcontainer.sh

.PHONY: dev-golang dev-node

dev-golang:
	$(open_devcontainer) golang

dev-node:
	$(open_devcontainer) node
