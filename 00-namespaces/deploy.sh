#!/bin/bash
set -e

echo "Creating namespaces..."
kubectl apply -f namespaces.yaml

echo "Namespaces created successfully!"
