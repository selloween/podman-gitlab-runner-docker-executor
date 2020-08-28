#!/bin/bash
podman run -d \
        --restart=always \
        --name gitlab-runner \
        -e DOCKER_HOST=192.168.XX.XX \
        -v /opt/podman/gitlab-runner/certs:/etc/gitlab-runner/certs:ro \
        -v /opt/podman/gitlab-runner/config.toml:/etc/gitlab-runner/config.toml \
        --volumes-from dind \
        gitlab/gitlab-runner:latest