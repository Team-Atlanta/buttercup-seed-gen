ARG parent_image
FROM $parent_image

# Parent image already has built fuzzers via OSS-Fuzz compile command
# Nothing additional needed for the builder phase
