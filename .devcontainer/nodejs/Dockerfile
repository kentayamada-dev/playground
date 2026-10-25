FROM node:26.12.0-trixie@sha256:1b84b89ada025e3b14543cbb837ffaa1c1b5273b841c5b94dd1a8f9c1d8cf7fe

LABEL org.opencontainers.image.title="nodejs" \
  org.opencontainers.image.description="nodejs の Dev Container" \
  org.opencontainers.image.source="https://github.com/kentayamada-dev/playground" \
  org.opencontainers.image.licenses="MIT"

# pnpm の版はここだけで管理し、.github/renovate.json5 の customManagers で Renovate が更新する
# .github/textlint の pnpm と同じく、Takumi Guard のレジストリから取得する
RUN npm install --global --registry=https://npm.flatt.tech/ pnpm@12.12.1

# 値は compose.yaml の nodejs の build.args から渡す
ARG USER_NAME
ARG HISTORY_DIR
ARG NODE_MODULES_DIR

# compose.yaml でマウントする空のボリュームには、Docker がこのディレクトリを所有者ごとコピーするため、sudo なしでもこのユーザーが書き込める
# https://github.com/moby/moby/blob/3f38b15147b14ce0ce7b11558a1aa9e9f14db103/daemon/container/container_unix.go#L386-L400
# bash は exit や SIGHUP では履歴を書くが、端末を開いたままコンテナを止めると書かずに終わるため、コマンドごとに書き出す
# https://github.com/kentayamada-dev/playground/pull/235
RUN useradd --create-home --user-group --shell /bin/bash "$USER_NAME" \
  && mkdir -p "$HISTORY_DIR" "$NODE_MODULES_DIR" \
  && chown "$USER_NAME:$USER_NAME" "$HISTORY_DIR" "$NODE_MODULES_DIR" \
  && echo "export PROMPT_COMMAND='history -a' HISTFILE=$HISTORY_DIR/.bash_history" >>"/home/$USER_NAME/.bashrc"
USER $USER_NAME
