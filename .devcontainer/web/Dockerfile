FROM node:26.12.0-trixie@sha256:1b84b89ada025e3b14543cbb837ffaa1c1b5273b841c5b94dd1a8f9c1d8cf7fe

# pnpm の版はここだけで管理し、.github/renovate.json5 の customManagers で Renovate が更新する
# .github/textlint の pnpm と同じく、Takumi Guard のレジストリから取得する
RUN npm install --global --registry=https://npm.flatt.tech/ pnpm@12.10.1

# 値は compose.yaml の x-dev-user から渡す
ARG USER_NAME

RUN useradd --create-home --user-group --shell /bin/bash "$USER_NAME"
USER $USER_NAME
