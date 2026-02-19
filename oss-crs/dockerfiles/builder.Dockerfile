# Buttercup Target Builder (ASan/Fuzzer Build)
# Compiles the target project with OSS-Fuzz tooling and uploads artifacts via libCRS

ARG target_base_image
FROM ${target_base_image}

# Install libCRS
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Copy build script
COPY oss-crs/bin/builder-default.sh /builder-default.sh
RUN chmod +x /builder-default.sh

CMD ["/builder-default.sh"]
