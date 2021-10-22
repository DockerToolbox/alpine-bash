FROM alpine:3.13

LABEL org.opencontainers.image.created="2021-10-22 15:14:06+00:00"
LABEL org.opencontainers.image.authors='Wolf Software Limited <dockerhub@wolfsoftare.com>'
LABEL org.opencontainers.image.url='https://hub.docker.com/repository/docker/wolfsoftwareltd/alpine-bash-alpine'
LABEL org.opencontainers.image.documentation='https://github.com/DockerToolbox/alpine-bash'
LABEL org.opencontainers.image.source='https://github.com/DockerToolbox/alpine-bash'
LABEL org.opencontainers.image.vendor='Wolf Software Limited'
LABEL org.opencontainers.image.licenses='MIT'
LABEL org.opencontainers.image.title=''
LABEL org.opencontainers.image.description=''

RUN apk update && \
	apk add --no-cache \
		bash=5.1.0-r0 \
		&& \
	sed -i -e "s/bin\/ash/bin\/bash/" /etc/passwd && \
	rm -rf /var/cache/apk/*

WORKDIR /root

ENTRYPOINT ["/bin/bash"]
