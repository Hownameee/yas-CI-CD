# 1. BẮT BUỘC dùng nền tảng của Strimzi để có file /opt/kafka/kafka_connect_run.sh
FROM quay.io/strimzi/kafka:latest-kafka-3.7.0

USER root:root

# 2. Tải plugin Debezium PostgreSQL từ trang chủ của Maven/Debezium
# (Đây là phiên bản ví dụ, hãy dùng phiên bản phù hợp với dự án)
RUN mkdir -p /opt/kafka/plugins/debezium \
    && curl -O https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.5.0.Final/debezium-connector-postgres-2.5.0.Final-plugin.tar.gz \
    && tar -xzf debezium-connector-postgres-2.5.0.Final-plugin.tar.gz -C /opt/kafka/plugins/debezium/ \
    && rm debezium-connector-postgres-2.5.0.Final-plugin.tar.gz

USER 1001