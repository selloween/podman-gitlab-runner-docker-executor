# Run GitLab Runner Podman Container using Runners with Docker Executors
## Preface
Currently there isn't an official GitLab Runner Executor for Podman. Due to RedHat Enterprise Linux 8 replacing Docker with Podman I had to find a simple solution for getting my Runners with Docker Executors running on RHEL8 without installing Docker natively or having to write a custom executor from scratch. The trick is to run a Podman Container running Docker inside and sharing it's Docker Socket as a volume between containers!

## Creating directory structure
I prefer to create a podman directory in `/opt` for all container bind mounts.
```
mkdir -p /opt/podman/gitlab-runner
mkdir -p /opt/podman/gitlab-runner/certs
mkdir -p /opt/podman/dind/docker
touch /opt/podman/gitlab-runner/config.toml
```

## Docker in Podman Container
First create a Podman container using the offical `dind` ("Docker in Docker") Image from Dockerhub. For this I created a simple bash script located in the `/dind` directory.
It's important that the "Docker in Podman" container is started before starting the GitLab Runner container.

#### Mounting and sharing Docker Socket
It's important to mount `/var/run` as a volume so that the GitLab Runner container can access the Docker Socket.
Also you will wnat to bind mount `/etc/docker` so that you can easily modify configuration files later on. (see bash script beneath)
```bash
#!/bin/bash
podman run -d \
        --restart=always \
        --name dind \
        -v docker_run:/var/run \
        -v /opt/podman/dind/docker:/etc/docker \
        docker:dind
```
**Create the container:**
```bash
chmod +x ./dind/podman.sh
./dind/podman.sh
``` 

## GitLab Runner Container
### Docker Host
It's important to set the `DOCKER_HOST` environment variable to the IP of your Podman host. As both containers should be running on the same host this would be the server's public IP or `127.0.0.1`
### Docker Socket
By "importing" the `/var/run` volume from the "Docker in Podman" container (`--volumes-from dind`), the GitLab Runner can connect to the Docker Socket and is capable of using the Docker Executor.

### TLS
You will be needing to add your TLS certificates (key, cert and CA cert) to `/opt/podman/gitlab-runner/certs` to successfully connect your Runner to the GitLab Server.
```
├── certs
│   ├── ca.crt
│   ├── your_host.crt
│   ├── your_host.key
│   └── your_host.pem
```
In case you are using internal certificates set `tls_verify` to false (see TLS section below)

### Starting the GitLab Runner Container
```bash
#!/bin/bash
podman run -d \
        --restart=always \
        --name gitlab-runner \
        -e DOCKER_HOST=127.0.0.1 \
        -v /opt/podman/gitlab-runner/certs:/etc/gitlab-runner/certs:ro \
        -v /opt/podman/gitlab-runner/config.toml:/etc/gitlab-runner/config.toml \
        --volumes-from dind \
        gitlab/gitlab-runner:latest
```
**Create and start the container:**
```bash
chmod +x ./gitlab-runner/podman.sh
./gitlab-runner/podman.sh
```

### Create and register Runnner
After starting the container, make sure to first create and register a Runner to your GitLab Server by using the GitLab Runner command line interface and following prompt wizard.
Make sure to select the `Docker Executor` and set the default image to `docker:stable` when prompted.
```bash
podman exec -it gitlab-runner gitlab-runner 
```
### Edit Runner Config
After registering your Runner edit the updated runner configuration: `/opt/podman/gitlab-runner/config.toml`
It's important to add `/var/run/docker.sock:/var/run/docker.sock` to the volumes array `volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]`
and setting the `NO_PROXY` environment variables: `environment = ["NO_PROXY=docker:2375,docker:2376", "no_proxy=docker:2375,docker:2376"]`. This will pass the docker.socket to the Docker container that get's spawned during a Build Process. Your now running Docker in Podman running Docker - Container Inception! ;-)
#### config.toml
Your `config.toml` should look like this:
```toml
concurrent = 1
check_interval = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "docker"
  url = "https://my-gitlab-server/"
  token = "XXXXXXXXXXXXXXXX"
  executor = "docker"
  [runners.custom_build_dir]
  [runners.cache]
    [runners.cache.s3]
    [runners.cache.gcs]
  [runners.docker]
    # in case you are using internal certificates set tls_verify to false
    tls_verify = false
    image = "docker:stable"
    privileged = true
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]
    environment = ["NO_PROXY=docker:2375,docker:2376", "no_proxy=docker:2375,docker:2376"]
    dns = []
    extra_hosts = []
    shm_size = 0
```