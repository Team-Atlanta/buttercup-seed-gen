# Buttercup Target Builder (Coverage Build)
# Compiles the target project with coverage instrumentation

ARG target_base_image
FROM ${target_base_image}

# Install libCRS
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Copy build script
COPY oss-crs/bin/builder-coverage.sh /builder-coverage.sh
RUN chmod +x /builder-coverage.sh

CMD ["/builder-coverage.sh"]
