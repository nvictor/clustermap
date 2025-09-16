#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Check for GOOGLE_CLOUD_PROJECT environment variable
if [ -z "${GOOGLE_CLOUD_PROJECT}" ]; then
    # Prompt for the Project ID if the environment variable is not set
    read -p "Enter your Google Cloud Project ID: " GCLOUD_PROJECT
else
    GCLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT}"
    echo "Using project from GOOGLE_CLOUD_PROJECT: ${GCLOUD_PROJECT}"
fi

if [ -z "${GCLOUD_PROJECT}" ]; then
    echo "Project ID cannot be empty."
    exit 1
fi

echo "Setting project to ${GCLOUD_PROJECT}..."
gcloud config set project "${GCLOUD_PROJECT}"

# Define cluster details
CLUSTER_NAME="clustermap-test-cluster"
ZONE="us-central1-c"

echo "Deleting GKE cluster '${CLUSTER_NAME}' in '${ZONE}'..."
gcloud container clusters delete "${CLUSTER_NAME}" --zone "${ZONE}" --quiet

echo ""
echo "✅ GKE cluster teardown complete!"
