# using --platform=linux/amd64 for building this locally
FROM --platform=linux/amd64 ghcr.io/gleam-lang/gleam:v1.1.0-erlang

# Use this when deploying on fly.op
# FROM ghcr.io/gleam-lang/gleam:v1.1.0-erlang

ENV ENVIRONMENT="production"

# Add project code
COPY .. /build/

# first build client and move the build contents
# into /server/priv/static dir
RUN rm -rf /build/client/build \
  && cd /build/client \
  && gleam run -m lustre/dev build app \
  && mv build/prod/javascript ../server/priv/static

WORKDIR /build

# cd into server and then build it, moving the contents into /app dir
RUN cd /build/server \
  && gleam export erlang-shipment \
  && mv build/erlang-shipment /app \
  && rm -r /build

# Run the server
WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]