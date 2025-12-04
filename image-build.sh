#!/bin/sh
POD_IMAGE="pdrive-alpine:latest"
IMG_FILE="pdrive-image-alpine-latest.tar"
podman build -f  Dockerfile --tag "$POD_IMAGE"
podman save -o "$IMG_FILE" "$POD_IMAGE"
podman image rm "$POD_IMAGE"

