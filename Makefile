open_devcontainer := .devcontainer/scripts/open-devcontainer/open-devcontainer.sh

.PHONY: dev-api dev-web

dev-api:
	$(open_devcontainer) api

dev-web:
	$(open_devcontainer) web
