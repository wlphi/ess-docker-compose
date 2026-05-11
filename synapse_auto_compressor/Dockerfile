FROM rust:1-slim AS builder
RUN apt-get update && apt-get install -y pkg-config libssl-dev libpq-dev && rm -rf /var/lib/apt/lists/*
RUN cargo install --git https://github.com/matrix-org/rust-synapse-compress-state synapse_auto_compressor

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y libssl3 libpq5 ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/local/cargo/bin/synapse_auto_compressor /usr/local/bin/
ENTRYPOINT ["synapse_auto_compressor"]
