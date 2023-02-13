# Simple [musl-libc](https://musl.libc.org/) based container image

The container images are built for `linux/amd64` and `linux/arm64`. The images
are vary basic and only contain `musl-libc` and `busybox` from [Alpine
Linux](https://pkgs.alpinelinux.org/packages?name=busybox). The build
variables can be found in the [Dockerfile](https://github.com/sando38/musl-ctr/blob/main/Dockerfile).

## Image name

The image names are `ghcr.io/sando38/musl-ctr` and `docker.io/sando38/musl-ctr`.

## Tags

Image tags are the respective `musl-libc` versions. Images are available from
version `1.1.7` onwards.

## Purpose of the image

The image could be used for example to test your applications against various
`musl-libc` versions and see if they are compatible. The image does not aim to
be complete.

E.g. use in new Dockerfile like

```
ARG MUSL_VSN='1.2.3'
FROM docker.io/sando38/musl-ctr:${MUSL_VSN}
COPY /app /app
...
```
