#!/bin/bash

# REGION is the region where the Cloud Function will be deployed.
# The projects and regions from where to collect data are passed
# as arguments when invoking the Cloud Function.

gcloud functions deploy modelstore_feeder \
--region=$REGION \
--no-allow-unauthenticated \
--gen2 \
--trigger-http \
--runtime=python310 \
--memory=1GB \
--source=. \
--entry-point=retrieve_data
