FROM golang:1.27.2-trixie@sha256:47667934874913a449b96faa7ef4777fa285d9ec29126ee80ed61c45b7cccf0e

LABEL org.opencontainers.image.title="golang" \
  org.opencontainers.image.description="golang の Dev Container" \
  org.opencontainers.image.source="https://github.com/kentayamada-dev/playground" \
  org.opencontainers.image.licenses="MIT"

# 値は compose.yaml の x-build-args から渡す
ARG USER_NAME
ARG HISTORY_DIR

# GOPATH の /go は誰でも書き込めるため、このユーザーでも go install とモジュールのキャッシュを使える https://github.com/docker-library/golang/blob/8380885ec449224702b989d8792d2e1470a46e89/1.27/trixie/Dockerfile#L135
# compose.yaml でマウントする空のボリュームには、Docker がこのディレクトリを所有者ごとコピーするため、sudo なしでもこのユーザーが書き込める
# https://github.com/moby/moby/blob/3f38b15147b14ce0ce7b11558a1aa9e9f14db103/daemon/container/container_unix.go#L386-L400
# bash は exit や SIGHUP では履歴を書くが、端末を開いたままコンテナを止めると書かずに終わるため、コマンドごとに書き出す
# https://github.com/kentayamada-dev/playground/pull/235
RUN useradd --create-home --user-group --shell /bin/bash "$USER_NAME" \
  && mkdir "$HISTORY_DIR" \
  && chown "$USER_NAME:$USER_NAME" "$HISTORY_DIR" \
  && echo "export PROMPT_COMMAND='history -a' HISTFILE=$HISTORY_DIR/.bash_history" >>"/home/$USER_NAME/.bashrc"
USER $USER_NAME
