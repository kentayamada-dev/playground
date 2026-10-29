.PHONY: run build test fmt vet staticcheck gosec

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

gosec:
	gosec ./...
