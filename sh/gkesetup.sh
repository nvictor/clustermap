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

echo "Setting project to ${GCLOUD_PROJECT}"...
gcloud config set project "${GCLOUD_PROJECT}"

# Enable necessary APIs
echo "Enabling required Google Cloud APIs..."
gcloud services enable container.googleapis.com compute.googleapis.com

# Create the GKE cluster
CLUSTER_NAME="clustermap-test-cluster"
ZONE="us-central1-c"

echo "Creating GKE cluster '${CLUSTER_NAME}' in '${ZONE}'..."
gcloud container clusters create "${CLUSTER_NAME}" \
    --zone "${ZONE}" \
    --num-nodes "1" \
    --machine-type "e2-small" \
    --scopes "https://www.googleapis.com/auth/cloud-platform"

# Get credentials for the new cluster
echo "Fetching cluster credentials..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone "${ZONE}"

echo ""
echo "✅ GKE cluster setup complete!"
echo ""
echo "Your kubectl is now configured to connect to the '${CLUSTER_NAME}' cluster."
echo "You can now run the Clustermap application to test against this new cluster."
echo "To clean up the resources later, you can run the following command:"
echo "gcloud container clusters delete ${CLUSTER_NAME} --zone ${ZONE}"
