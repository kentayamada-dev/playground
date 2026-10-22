open_devcontainer := .devcontainer/scripts/open-devcontainer/open-devcontainer.sh

.PHONY: dev-golang dev-nodejs

dev-golang:
	$(open_devcontainer) golang

dev-nodejs:
	$(open_devcontainer) nodejs
