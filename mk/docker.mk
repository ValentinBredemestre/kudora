DOCKER_IMAGE := kudora/kudorad:localnet

.PHONY: docker-build docker-smoke-test docker-version

docker-build:
	@DOCKER_BUILDKIT=1 docker buildx build --load --tag $(DOCKER_IMAGE) --file Dockerfile .

docker-smoke-test: docker-build
	@docker run --rm $(DOCKER_IMAGE) version --long >/dev/null
	@docker run --rm $(DOCKER_IMAGE) --help >/dev/null
	@user="$$(docker image inspect $(DOCKER_IMAGE) --format '{{.Config.User}}')"; \
		test -n "$$user" && test "$$user" != "0" && test "$$user" != "root"
	@ports="$$(docker image inspect $(DOCKER_IMAGE) --format '{{json .Config.ExposedPorts}}')"; \
		for port in 1317 8545 8546 9090 26656 26657; do \
			case "$$ports" in *"\"$$port/tcp\""*) ;; *) exit 1 ;; esac; \
		done

docker-version: docker-build
	@docker run --rm $(DOCKER_IMAGE)
