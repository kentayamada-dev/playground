FROM golang:1.27.2-trixie@sha256:47667934874913a449b96faa7ef4777fa285d9ec29126ee80ed61c45b7cccf0e

# 値は compose.yaml の x-dev-user から渡す
ARG USER_NAME
ARG USER_UID
ARG USER_GID

# Linux のホストでは、マウントしたリポジトリに root で書くと root の所有のファイルができるため、一般ユーザーで動かす https://code.visualstudio.com/remote/advancedcontainers/add-nonroot-user
# GOPATH の /go は誰でも書き込めるため、このユーザーでも go install とモジュールのキャッシュを使える https://github.com/docker-library/golang/blob/8380885ec449224702b989d8792d2e1470a46e89/1.27/trixie/Dockerfile#L135
RUN groupadd --gid "$USER_GID" "$USER_NAME" \
  && useradd --uid "$USER_UID" --gid "$USER_GID" --create-home --shell /bin/bash "$USER_NAME"
USER $USER_NAME
