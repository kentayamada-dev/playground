FROM golang:1.27.2-trixie@sha256:47667934874913a449b96faa7ef4777fa285d9ec29126ee80ed61c45b7cccf0e

LABEL org.opencontainers.image.title="golang" \
  org.opencontainers.image.description="golang の Dev Container" \
  org.opencontainers.image.source="https://github.com/kentayamada-dev/playground" \
  org.opencontainers.image.licenses="MIT"

# gopls と gofumpt の版はここだけで管理し、.github/renovate.json5 の customManagers で Renovate が更新する
# go install は版を付けると 1 つのモジュールのパッケージしか受け付けないため、モジュールごとに分ける https://go.dev/ref/mod#go-install
RUN go install golang.org/x/tools/gopls@v0.23.0 \
  && go install mvdan.cc/gofumpt@v0.12.0 \
  && go clean -cache -modcache

# 値は compose.yaml の golang の build.args から渡す
ARG USER_NAME
ARG HISTORY_DIR
ARG GO_CACHE_DIR

ENV GOMODCACHE="$GO_CACHE_DIR/mod" GOCACHE="$GO_CACHE_DIR/build"

# 公式イメージは GOTOOLCHAIN=local で go.mod の toolchain 行を無視するため、イメージより新しい版が書かれていればその版を使わせる
# https://github.com/docker-library/golang/blob/8380885ec449224702b989d8792d2e1470a46e89/1.27/trixie/Dockerfile#L129 https://go.dev/doc/toolchain#select
ENV GOTOOLCHAIN=auto

# GOPATH の /go は誰でも書き込めるため、このユーザーでも go install を使える https://github.com/docker-library/golang/blob/8380885ec449224702b989d8792d2e1470a46e89/1.27/trixie/Dockerfile#L135
# compose.yaml でマウントする空のボリュームには、Docker がこのディレクトリを所有者ごとコピーするため、sudo なしでもこのユーザーが書き込める
# https://github.com/moby/moby/blob/3f38b15147b14ce0ce7b11558a1aa9e9f14db103/daemon/container/container_unix.go#L386-L400
# bash は exit や SIGHUP では履歴を書くが、端末を開いたままコンテナを止めると書かずに終わるため、コマンドごとに書き出す
# https://github.com/kentayamada-dev/playground/pull/235
RUN useradd --create-home --user-group --shell /bin/bash "$USER_NAME" \
  && mkdir "$HISTORY_DIR" "$GO_CACHE_DIR" \
  && chown "$USER_NAME:$USER_NAME" "$HISTORY_DIR" "$GO_CACHE_DIR" \
  && echo "export PROMPT_COMMAND='history -a' HISTFILE=$HISTORY_DIR/.bash_history" >>"/home/$USER_NAME/.bashrc"
USER $USER_NAME
