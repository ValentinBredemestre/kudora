BINARY := kudorad
BUILD_DIR := build

.PHONY: build install lint tidy

build:
	@mkdir -p $(BUILD_DIR)
	@go build -o $(BUILD_DIR)/$(BINARY) ./cmd/$(BINARY)

install:
	@go install ./cmd/$(BINARY)

lint:
	@go vet ./...

tidy:
	@go mod tidy
