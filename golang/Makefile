.PHONY: run build test fmt vet staticcheck

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

staticcheck:
	staticcheck ./...
