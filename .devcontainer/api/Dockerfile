FROM golang:1.27.2-trixie@sha256:47667934874913a449b96faa7ef4777fa285d9ec29126ee80ed61c45b7cccf0e

# 値は compose.yaml の x-dev-user から渡す
ARG USER_NAME

# GOPATH の /go は誰でも書き込めるため、このユーザーでも go install とモジュールのキャッシュを使える https://github.com/docker-library/golang/blob/8380885ec449224702b989d8792d2e1470a46e89/1.27/trixie/Dockerfile#L135
RUN useradd --create-home --user-group --shell /bin/bash "$USER_NAME"
USER $USER_NAME
