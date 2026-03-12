# Buttercup Target Builder (Coverage Build)
# Compiles the target project with coverage instrumentation

ARG target_base_image
FROM ${target_base_image}

# Install libCRS
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Install JaCoCo for Java coverage
ARG JACOCO_VERSION=0.8.11
RUN apt-get update && apt-get install -y --no-install-recommends unzip curl && \
    curl -fsSL "https://repo1.maven.org/maven2/org/jacoco/jacoco/${JACOCO_VERSION}/jacoco-${JACOCO_VERSION}.zip" -o /tmp/jacoco.zip && \
    unzip -j /tmp/jacoco.zip "lib/jacocoagent.jar" -d /opt/ && \
    unzip -j /tmp/jacoco.zip "lib/jacococli.jar" -d /opt/ && \
    mv /opt/jacocoagent.jar /opt/jacoco-agent.jar && \
    mv /opt/jacococli.jar /opt/jacoco-cli.jar && \
    rm /tmp/jacoco.zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy build script
COPY oss-crs/bin/builder-coverage.sh /builder-coverage.sh
RUN chmod +x /builder-coverage.sh

CMD ["/builder-coverage.sh"]
