FROM golang:1.27.2-trixie@sha256:47667934874913a449b96faa7ef4777fa285d9ec29126ee80ed61c45b7cccf0e

LABEL org.opencontainers.image.title="golang" \
  org.opencontainers.image.description="golang の Dev Container" \
  org.opencontainers.image.source="https://github.com/kentayamada-dev/playground" \
  org.opencontainers.image.licenses="MIT"

# 値は compose.yaml の golang の build.args から渡す
ARG USER_NAME
ARG HISTORY_DIR
ARG GO_CACHE_DIR

ENV GOMODCACHE="$GO_CACHE_DIR/mod" GOCACHE="$GO_CACHE_DIR/build"

# 公式イメージは GOTOOLCHAIN=local で go.mod の toolchain 行を無視するため、イメージより新しい版が書かれていればその版を使わせる
# https://github.com/docker-library/golang/blob/8380885ec449224702b989d8792d2e1470a46e89/1.27/trixie/Dockerfile#L129 https://go.dev/doc/toolchain#select
ENV GOTOOLCHAIN=auto

# compose.yaml でマウントする空のボリュームには、Docker がこのディレクトリを所有者ごとコピーするため、sudo なしでもこのユーザーが書き込める
# https://github.com/moby/moby/blob/3f38b15147b14ce0ce7b11558a1aa9e9f14db103/daemon/container/container_unix.go#L386-L400
# bash は exit や SIGHUP では履歴を書くが、端末を開いたままコンテナを止めると書かずに終わるため、コマンドごとに書き出す
# https://github.com/kentayamada-dev/playground/pull/235
RUN useradd --create-home --user-group --shell /bin/bash "$USER_NAME" \
  && mkdir "$HISTORY_DIR" "$GO_CACHE_DIR" \
  && chown "$USER_NAME:$USER_NAME" "$HISTORY_DIR" "$GO_CACHE_DIR" \
  && echo "export PROMPT_COMMAND='history -a' HISTFILE=$HISTORY_DIR/.bash_history" >>"/home/$USER_NAME/.bashrc"
USER $USER_NAME

# gopls と gofumpt の版は tools のツールごとの go.mod で管理し、Renovate の gomod マネージャーが更新する
# gopls は golang.org/x/tools の内部パッケージを使い、自身の go.mod と違う版の x/tools ではビルドできないことがあるため、go.mod を分け、依存だけを上げずに gopls ごと上げる
# 例: gopls v0.23.0 が使う packagepath.IsStdPackage は、gopls v0.24.0 の時点の x/tools にない https://github.com/golang/tools/blob/gopls/v0.23.0/gopls/internal/analysis/unusedfunc/unusedfunc.go#L22-L77
COPY tools /tmp/tools
# GOPATH の /go は誰でも書き込めるため、このユーザーでも go install を使える https://github.com/docker-library/golang/blob/8380885ec449224702b989d8792d2e1470a46e89/1.27/trixie/Dockerfile#L135
# root で入れると go install が作る $GOPATH/pkg/sumdb が root のものになり、このユーザーがツールチェーンのダウンロードを検証できなくなる
# https://github.com/golang/go/blob/go1.27.3/src/cmd/go/internal/modfetch/sumdb.go#L250-L261
RUN go install -C /tmp/tools/gopls tool \
  && go install -C /tmp/tools/gofumpt tool \
  && go clean -cache -modcache
