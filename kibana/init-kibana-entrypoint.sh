#!/bin/bash

# Custom Kibana entrypoint with automatic dashboard setup
set -e

SAVED_OBJECTS_FILE="/usr/share/kibana/config/saved_objects.ndjson"
KIBANA_URL="http://localhost:5601"
ELASTICSEARCH_URL="${ELASTICSEARCH_HOSTS:-http://elasticsearch:9200}"

echo "🚀 Starting Kibana with automated dashboard setup..."

# Function to wait for Elasticsearch
wait_for_elasticsearch() {
    echo "⏳ Waiting for Elasticsearch..."
    for i in {1..30}; do
        if curl -s "$ELASTICSEARCH_URL/_cluster/health" >/dev/null 2>&1; then
            echo "✅ Elasticsearch is ready!"
            return 0
        fi
        echo "  Attempt $i/30: Elasticsearch not ready yet..."
        sleep 5
    done
    echo "❌ Elasticsearch timeout"
    return 1
}

# Function to import dashboards after Kibana starts
import_dashboards_background() {
    echo "📊 Starting background dashboard import process..."

    # Wait for Kibana to be fully ready
    for i in {1..60}; do
        if curl -s "$KIBANA_URL/api/status" | grep -q '"level":"available"' 2>/dev/null; then
            echo "✅ Kibana is ready for dashboard import!"
            break
        fi
        sleep 5
        echo "  Waiting for Kibana... ($i/60)"
    done

    # Import saved objects
    if [ -f "$SAVED_OBJECTS_FILE" ]; then
        echo "📊 Importing APT Security Dashboards..."

        # Try the bulk import first
        response=$(curl -s -X POST "$KIBANA_URL/api/saved_objects/_import?overwrite=true" \
            -H "kbn-xsrf: true" \
            --form file=@"$SAVED_OBJECTS_FILE" 2>/dev/null || echo "failed")

        if echo "$response" | grep -q "success" 2>/dev/null; then
            echo "✅ Dashboards imported successfully!"
        else
            echo "🔄 Trying line-by-line import..."
            # Import each object individually
            while IFS= read -r line; do
                if [ -n "$line" ] && echo "$line" | jq . >/dev/null 2>&1; then
                    object_type=$(echo "$line" | jq -r 'if .objects then .objects[0].type else .type end' 2>/dev/null)
                    object_id=$(echo "$line" | jq -r 'if .objects then .objects[0].id else .id end' 2>/dev/null)

                    if [ "$object_type" != "null" ] && [ "$object_id" != "null" ]; then
                        echo "  Importing $object_type: $object_id"
                        curl -s -X POST "$KIBANA_URL/api/saved_objects/$object_type/$object_id?overwrite=true" \
                            -H "Content-Type: application/json" \
                            -H "kbn-xsrf: true" \
                            -d "$line" >/dev/null 2>&1
                    fi
                fi
            done < "$SAVED_OBJECTS_FILE"
            echo "✅ Individual import completed!"
        fi

        echo "🎉 APT Security Dashboards are ready!"
        echo "🌐 Access at: $KIBANA_URL/app/dashboards"
    else
        echo "⚠️  No saved objects file found at $SAVED_OBJECTS_FILE"
    fi
}

# Main execution
main() {
    # Wait for Elasticsearch first
    wait_for_elasticsearch || exit 1

    # Start dashboard import in background
    import_dashboards_background &

    # Start Kibana with original entrypoint
    echo "🚀 Starting Kibana server..."
    exec /usr/local/bin/kibana-docker
}

main "$@"