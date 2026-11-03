.PHONY: run build test fmt tidy vet staticcheck gosec

run:
	go run .

build:
	go build -o bin/golang .

test:
	go test ./...

fmt:
	gofumpt -w .

tidy:
	go mod tidy

vet:
	go vet ./...

staticcheck:
	staticcheck ./...

gosec:
	gosec -tests ./...
