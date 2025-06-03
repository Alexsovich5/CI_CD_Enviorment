#!/bin/bash
# Service cleanup script for DevOps stack

set -e

read -p "This will stop and remove all containers, networks, and volumes for this project. Are you sure? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo "Stopping and removing all containers..."
docker-compose down -v

echo "Pruning unused Docker resources (system prune)..."
docker system prune -f

echo "Cleanup completed!"
