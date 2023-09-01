#!/bin/bash

# Deploying Cloud Function to this project:
PROJECT=pbalm-cxb-aa
REGION=europe-west4
# This means that we will report the metrics from the above project.
# The project with the model store that we will report the data to
# is configured in the main.py code.

gcloud functions deploy modelstore_feeder \
--region=$REGION \
--no-allow-unauthenticated \
--gen2 \
--trigger-http \
--runtime=python310 \
--memory=1GB \
--source=. \
--entry-point=retrieve_data
