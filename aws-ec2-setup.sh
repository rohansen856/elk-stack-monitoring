#!/bin/bash

# AWS EC2 Setup Script for ELK Stack Monitoring
# Run this after git clone on a fresh EC2 instance

set -e

echo "=== ELK Stack Monitoring - AWS EC2 Setup ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get EC2 public IP automatically using IMDSv2 (Instance Metadata Service v2)
echo "Detecting EC2 public IP..."

# Get IMDSv2 token (required for modern EC2 instances)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)

if [ -n "$TOKEN" ]; then
    # Use IMDSv2 with token
    EC2_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
else
    # Fallback to IMDSv1 (for older instances)
    EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
fi

if [ -z "$EC2_IP" ]; then
    echo -e "${RED}ERROR: Could not detect EC2 public IP${NC}"
    echo "Please enter your EC2 public IP manually:"
    read -p "EC2 Public IP: " EC2_IP
fi

echo -e "${GREEN}Detected EC2 Public IP: $EC2_IP${NC}"
echo ""

# Step 1: Copy environment files
echo -e "${YELLOW}Step 1: Setting up environment files...${NC}"

if [ ! -f .env ]; then
    cp .env.example .env
    echo "✓ Created .env from .env.example"
else
    echo "✓ .env already exists"
fi

if [ ! -f website/.env ]; then
    cp website/.env.example website/.env
    echo "✓ Created website/.env from website/.env.example"
else
    echo "✓ website/.env already exists"
fi

# Step 2: Update frontend URL with EC2 IP
echo ""
echo -e "${YELLOW}Step 2: Configuring for AWS EC2...${NC}"

# Update NEXT_PUBLIC_APP_URL in website/.env
if grep -q "localhost" website/.env; then
    sed -i "s|http://localhost/frontend|http://$EC2_IP/frontend|g" website/.env
    echo "✓ Updated NEXT_PUBLIC_APP_URL to http://$EC2_IP/frontend"
else
    echo "✓ NEXT_PUBLIC_APP_URL already configured"
fi

# Step 3: Build and start services
echo ""
echo -e "${YELLOW}Step 3: Building and starting Docker containers...${NC}"
echo "This may take 5-10 minutes on first run..."
echo ""

docker compose build --no-cache
echo ""
echo -e "${GREEN}✓ Build complete${NC}"
echo ""

docker compose up -d
echo ""
echo -e "${GREEN}✓ Services started${NC}"
echo ""

# Step 4: Wait for services to be ready
echo -e "${YELLOW}Step 4: Waiting for services to initialize...${NC}"
echo "Waiting 90 seconds for Kibana to start..."
sleep 90

# Step 5: Reset Kibana system password
echo ""
echo -e "${YELLOW}Step 5: Resetting Kibana system password...${NC}"

# Reset kibana_system password using the correct container name
KIBANA_PASSWORD=$(docker compose exec -T elasticsearch bin/elasticsearch-reset-password -u kibana_system -b -a 2>&1 | grep "New value:" | awk '{print $NF}')

if [ -z "$KIBANA_PASSWORD" ]; then
    echo -e "${RED}✗ Failed to reset Kibana password${NC}"
    echo "Trying alternative method..."
    KIBANA_PASSWORD=$(docker exec -it elk-stack-monitoring-elasticsearch-1 bin/elasticsearch-reset-password -u kibana_system -b -a 2>&1 | tail -1)
fi

echo -e "${GREEN}✓ Kibana system password reset${NC}"
echo "Updating kibana.yml with new password..."

# Update kibana.yml with new password
sed -i "s|elasticsearch.password:.*|elasticsearch.password: \"$KIBANA_PASSWORD\"|g" kibana/kibana.yml

# Restart Kibana to apply new password
docker compose restart kibana
echo -e "${GREEN}✓ Kibana restarted with new credentials${NC}"

# Step 6: Verify services
echo ""
echo -e "${YELLOW}Step 6: Verifying services...${NC}"
echo ""

# Check backend
if curl -sf http://localhost/backend/health > /dev/null; then
    echo -e "${GREEN}✓ Backend API is healthy${NC}"
else
    echo -e "${RED}✗ Backend API is not responding${NC}"
fi

# Check Kibana
if curl -sf http://localhost/monitoring/api/status > /dev/null; then
    echo -e "${GREEN}✓ Kibana is healthy${NC}"
else
    echo -e "${RED}✗ Kibana is not responding (may still be initializing)${NC}"
fi

# Check nginx
if curl -sf http://localhost/nginx-health > /dev/null; then
    echo -e "${GREEN}✓ Nginx is healthy${NC}"
else
    echo -e "${RED}✗ Nginx is not responding${NC}"
fi

# Step 7: Display access information
echo ""
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo ""
echo "Access your application at:"
echo -e "${GREEN}Frontend:${NC}  http://$EC2_IP/frontend"
echo -e "${GREEN}Backend:${NC}   http://$EC2_IP/backend/docs"
echo -e "${GREEN}Kibana:${NC}    http://$EC2_IP/monitoring"
echo ""
echo "Default credentials:"
echo -e "${GREEN}Elasticsearch:${NC} elastic / elastic123"
echo -e "${GREEN}Kibana:${NC}        elastic / elastic123"
echo ""
echo "To view logs:"
echo "  docker compose logs -f"
echo ""
echo "To stop services:"
echo "  docker compose down"
echo ""
echo "To restart services:"
echo "  docker compose restart"
echo ""
echo -e "${YELLOW}Note: Make sure your EC2 Security Group allows inbound traffic on port 80${NC}"
echo ""
