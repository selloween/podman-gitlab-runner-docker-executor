#!/bin/bash
podman run -d \
        --restart=always \
        --name dind \
        -v docker_run:/var/run \
        -v /opt/podman/dind/docker:/etc/docker \
        docker:dind