FROM node:26.12.0-trixie@sha256:1b84b89ada025e3b14543cbb837ffaa1c1b5273b841c5b94dd1a8f9c1d8cf7fe

# pnpm の版はここだけで管理し、.github/renovate.json5 の customManagers で Renovate が更新する
# .github/textlint の pnpm と同じく、Takumi Guard のレジストリから取得する
RUN npm install --global --registry=https://npm.flatt.tech/ pnpm@12.10.1

# 値は compose.yaml の x-dev-user から渡す
ARG USER_NAME
ARG USER_UID
ARG USER_GID

# Linux のホストでは、マウントしたリポジトリに root で書くと root の所有のファイルができるため、一般ユーザーで動かす https://code.visualstudio.com/remote/advancedcontainers/add-nonroot-user
# イメージの node が UID・GID 1000 を使っていて、同じ ID のユーザーを作れないため消す https://github.com/nodejs/docker-node/blob/f27125230b3c367dcf63043ea3fe286fb3d0914c/26/trixie/Dockerfile#L3-L4
RUN userdel --remove node \
  && groupadd --gid "$USER_GID" "$USER_NAME" \
  && useradd --uid "$USER_UID" --gid "$USER_GID" --create-home --shell /bin/bash "$USER_NAME"
USER $USER_NAME
