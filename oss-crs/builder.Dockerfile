# Builder Dockerfile for Buttercup Bug-Finding CRS
# This inherits from the OSS-Fuzz project builder image
# The actual compilation is done by OSS-Fuzz's build system

ARG parent_image
FROM $parent_image
