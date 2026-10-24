.PHONY: run build test fmt vet

run:
	go run .

build:
	go build -o bin/golang .

test:
	go test ./...

fmt:
	gofumpt -w .

vet:
	go vet ./...
