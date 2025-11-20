# Custom Kibana with Pre-configured Security Dashboards
FROM docker.elastic.co/kibana/kibana:8.11.0

USER root

# Install additional tools
RUN apt-get update && \
    apt-get install -y curl jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy configuration files
COPY kibana.yml /usr/share/kibana/config/kibana.yml
COPY saved_objects.ndjson /usr/share/kibana/config/saved_objects.ndjson

# Copy initialization script
COPY init-kibana-entrypoint.sh /usr/local/bin/init-kibana-entrypoint.sh
RUN chmod +x /usr/local/bin/init-kibana-entrypoint.sh

# Switch back to kibana user
USER kibana

# Use custom entrypoint that sets up dashboards
ENTRYPOINT ["/usr/local/bin/init-kibana-entrypoint.sh"]