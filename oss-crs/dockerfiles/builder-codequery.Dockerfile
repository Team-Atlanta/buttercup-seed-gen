# Buttercup Target Builder (Codequery Index)
# Builds codequery indexes for seed-gen

ARG target_base_image
FROM ${target_base_image}

# Install codequery toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    cscope \
    exuberant-ctags \
    codequery \
    && rm -rf /var/lib/apt/lists/*

# Install libCRS
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Copy build script
COPY oss-crs/bin/builder-codequery.sh /builder-codequery.sh
RUN chmod +x /builder-codequery.sh

CMD ["/builder-codequery.sh"]
