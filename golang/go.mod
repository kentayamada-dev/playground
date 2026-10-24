module github.com/kentayamada-dev/playground/golang

go 1.26.0

// Renovate は go の行ではなく toolchain の版でだけ、stdlib の脆弱性を照会して修正版への PR を作るため
// https://github.com/renovatebot/renovate/blob/44.151.1/lib/workers/repository/process/vulnerabilities.ts#L180-L187
toolchain go1.27.3
