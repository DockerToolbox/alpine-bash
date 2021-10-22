FROM ${CONTAINER_OS_NAME}:${CONTAINER_OS_VERSION_ALT}

LABEL org.opencontainers.image.created="$(date --rfc-3339=seconds --utc)"
LABEL org.opencontainers.image.authors='${LABEL_AUTHORS}'
LABEL org.opencontainers.image.url='${LABEL_URL}'
LABEL org.opencontainers.image.documentation='${LABEL_DOCUMENTATION}'
LABEL org.opencontainers.image.source='${LABEL_SOURCE}'
LABEL org.opencontainers.image.vendor='${LABEL_VENDOR}'
LABEL org.opencontainers.image.licenses='${LABEL_LICENSE}'
LABEL org.opencontainers.image.title='${LABEL_TITLE}'
LABEL org.opencontainers.image.description='${LABEL_DESCRIPTION}'

${PACKAGES}
	sed -i -e "s/bin\/ash/bin\/bash/" /etc/passwd && \
	rm -rf /var/cache/apk/*

WORKDIR /root

ENTRYPOINT ["/bin/bash"]
