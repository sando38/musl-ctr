ARG ALPINE_VSN='3.17'
FROM alpine:${ALPINE_VSN} as musl

RUN apk add --no-cache build-base gnupg
# download musl source code, checksum test and fingerprint validation
ARG MUSL_VSN='1.2.3'
ARG GPG_FINGERPRINT='8364 8929 0BB6 B70F 99FF  DA05 56BC DB59 3020 450F'
ARG SHA512_SUM='9332f713d3eb7de4369bc0327d99252275ee52abf523ee34b894b24a387f67579787f7c72a46cf652e090cffdb0bc3719a4e7b84dca66890b6a37f12e8ad089c'
RUN wget https://musl.libc.org/releases/musl-$MUSL_VSN.tar.gz
RUN CHECKSUM_STATE=$(echo -n $(echo "${SHA512_SUM}  musl-$MUSL_VSN.tar.gz" | sha512sum -c) | tail -c 2) \
    && if [ "${CHECKSUM_STATE}" != "OK" ]; then echo "Error: checksum does not match" && exit 1; fi
RUN echo -e "1.1.6 \n$MUSL_VSN" > vsn_gpg \
    && if [ "$(sort -V -r vsn_gpg | head -n1)" = "$MUSL_VSN" ]; \
       then \
            wget https://musl.libc.org/musl.pub && \
            wget https://musl.libc.org/releases/musl-$MUSL_VSN.tar.gz.asc && \
            gpg --import -q musl.pub && \
            FINGERPRINT="$(LANG=C gpg --verify musl-$MUSL_VSN.tar.gz.asc musl-$MUSL_VSN.tar.gz 2>&1 \
                | sed -n "s#Primary key fingerprint: \(.*\)#\1#p")" && \
            if [ -z "${FINGERPRINT}" ]; then echo "Error: invalid GPG signature!" && exit 1; fi && \
            if [ "${FINGERPRINT}" != "${GPG_FINGERPRINT}" ]; then echo "Error: wrong GPG fingerprint" && exit 1; fi \
       fi \
    && rm vsn_gpg
RUN tar -xzf musl-$MUSL_VSN.tar.gz

# build musl libc
WORKDIR /musl-$MUSL_VSN
RUN ./configure \
        --prefix=/rootfs \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --syslibdir=/lib \
    && make -j "$(nproc)"
RUN make install
# prepare rootfs
RUN mkdir /rootfs/bin \
    && ln /rootfs/lib/libc.so /rootfs/lib/ld-musl-$(uname -m).so.1 \
    && echo -e \
        "#!/bin/sh \
        \nexec /lib/ld-musl-$(uname -m).so.1 --list \"\$@\"" > /rootfs/bin/ldd \
    && chmod +x /rootfs/bin/ldd

# use a static busybox - so no compatibility with musl-libc is required
FROM alpine:${ALPINE_VSN} AS busybox
COPY --from=musl /rootfs /rootfs
COPY --from=busybox:musl /bin/getconf /rootfs/bin

RUN apk add --no-cache coreutils curl tzdata

RUN mkdir -p /rootfs/bin /rootfs/etc \
    && ln -v /bin/busybox /rootfs/bin/busybox \
    && chroot rootfs /bin/getconf _NPROCESSORS_ONLN \
    && chroot rootfs /bin/busybox --install /bin

# install a few extra files from buildroot (/etc/passwd, etc)
RUN set -eux; \
	buildrootVersion='2022.11'; \
	for file in \
		system/device_table.txt \
		system/skeleton/etc/group \
		system/skeleton/etc/passwd \
		system/skeleton/etc/shadow \
	; do \
		dir="$(dirname "$file")"; \
		mkdir -p "../buildroot/$dir"; \
		curl -fL -o "../buildroot/$file" "https://git.busybox.net/buildroot/plain/$file?id=$buildrootVersion"; \
		[ -s "../buildroot/$file" ]; \
	done; \
	\
	mkdir -p /rootfs/etc; \
	ln -vL \
		../buildroot/system/skeleton/etc/group \
		../buildroot/system/skeleton/etc/passwd \
		../buildroot/system/skeleton/etc/shadow \
		/rootfs/etc/ \
	; \
# CVE-2019-5021, https://github.com/docker-library/official-images/pull/5880#issuecomment-490681907
	grep -E '^root::' /rootfs/etc/shadow; \
	sed -ri -e 's/^root::/root:*:/' /rootfs/etc/shadow; \
	grep -E '^root:[*]:' /rootfs/etc/shadow; \
# set expected permissions, etc too (https://git.busybox.net/buildroot/tree/system/device_table.txt)
	awk ' \
		!/^#/ { \
			if ($2 != "d" && $2 != "f") { \
				printf "error: unknown type \"%s\" encountered in line %d: %s\n", $2, NR, $0 > "/dev/stderr"; \
				exit 1; \
			} \
			sub(/^\/?/, "/rootfs/", $1); \
			if ($2 == "d") { \
				printf "mkdir -p %s\n", $1; \
			} \
			printf "chmod %s %s\n", $3, $1; \
		} \
	' ../buildroot/system/device_table.txt | sh -eux

# create missing home directories and ensure /usr/bin/env exists
RUN set -eux; \
	cd /rootfs; \
	for userHome in $(awk -F ':' '{ print $3 ":" $4 "=" $6 }' etc/passwd); do \
		user="${userHome%%=*}"; \
		home="${userHome#*=}"; \
		home="./${home#/}"; \
		if [ ! -d "$home" ]; then \
			mkdir -p "$home"; \
			chown "$user" "$home"; \
			chmod 755 "$home"; \
		fi; \
	done; \
	if [ ! -s usr/bin/env ] && [ -s bin/env ]; then \
		mkdir -p usr/bin; \
		ln -s ../../bin/env usr/bin/; \
	fi

# test and make sure it works
RUN chroot rootfs /usr/bin/env sh -xec 'true'

# ensure correct timezone (UTC)
RUN set -eux; \
	ln -vL /usr/share/zoneinfo/UTC /rootfs/etc/localtime; \
	[ "$(chroot rootfs date +%Z)" = 'UTC' ]

# test and make sure DNS works too
RUN cp -L /etc/resolv.conf /rootfs/etc/; \
	chroot rootfs /bin/sh -xec 'nslookup google.com'; \
	rm /rootfs/etc/resolv.conf


# build together the test image
FROM scratch
COPY --from=busybox /rootfs /

LABEL   org.opencontainers.image.title='musl-ctr' \
        org.opencontainers.image.description='Simple container with musl-libc and busybox' \
        org.opencontainers.image.url='https://github.com/sando38/musl-ctr' \
        org.opencontainers.image.source='https://github.com/sando38/musl-ctr' \
        org.opencontainers.image.version="$MUSL_VSN" \
        org.opencontainers.image.licenses='Apache-2.0'
