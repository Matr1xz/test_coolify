FROM kong:3.6

USER root

# Install luarocks dependencies for HTTP calls
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    && luarocks install lua-resty-http \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER kong
