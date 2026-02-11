group "default" {
  targets = ["buttercup-runner-base"]
}

target "buttercup-runner-base" {
  context    = "."
  dockerfile = "oss-crs/dockerfiles/buttercup-runner.Dockerfile"
  target     = "base"
}
