.PHONY: run build test fmt vet

run:
	go run .

build:
	go build -o bin/golang .

test:
	go test ./...

# 保存時に gopls がかける整形（devcontainer.json の formatting.gofumpt）とそろえるため
fmt:
	gofumpt -w .

vet:
	go vet ./...
