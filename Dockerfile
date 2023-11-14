FROM nginx:1.25.3 AS build-otel

WORKDIR /

# add build dependencies
RUN echo "deb-src [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian/ bullseye nginx" >> /etc/apt/sources.list \
&& apt-get update \
&& apt install -y git cmake build-essential libssl-dev zlib1g-dev libpcre3-dev pkg-config libc-ares-dev libre2-dev \
&& apt-get build-dep -y nginx \
&& rm -rf /var/lib/apt/lists/*

# prepare nginx source
RUN curl -fsSL -O https://github.com/nginx/nginx/archive/release-${NGINX_VERSION}.tar.gz \
&& tar zxf release-${NGINX_VERSION}.tar.gz \
&& cd nginx-release-${NGINX_VERSION} \
&& auto/configure --with-compat

WORKDIR /nginx-otel

COPY . .

# build the module
RUN mkdir build \
&& cd build \
&& cmake -DNGX_OTEL_NGINX_BUILD_DIR=/nginx-release-${NGINX_VERSION}/objs .. \
&& make -j$(nproc)

# remove debug symbols
RUN strip --strip-debug /nginx-otel/build/ngx_otel_module.so

# use the module in nginx
FROM nginx:1.25.3
COPY --from=build-otel /nginx-otel/build/ngx_otel_module.so /etc/nginx/modules/ngx_otel_module.so

# install runtime dependencies and test module
RUN apt update \
&& apt install -y libc-ares-dev libre2-dev \
&& rm -rf /var/lib/apt/lists/* \
&& echo "load_module modules/ngx_otel_module.so;" > /tmp/test.conf \
&& cat /etc/nginx/nginx.conf >> /tmp/test.conf \
&& nginx -t -c /tmp/test.conf \
&& rm /tmp/test.conf