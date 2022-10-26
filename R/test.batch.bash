#!/bin/bash -x

# Put this script in an empty directory with the name "test.[INDEX]" and replace [INDEX] with the name of your test
# run so you can easily find it in the GCP Console.
# For example, the directory could be "test.001-first-test" and the container, the model and the batch prediction
# job will have "001-first-test" in the name.

INDEX=$(echo $(basename $(pwd)) | cut -d. -f2-)

export LOCATION=europe-west1
export PROJECT_ID=$(gcloud config list --format 'value(core.project)')
export REPO_NAME=vertex-custom-$INDEX
export IMAGE_NAME=vertex-custom-$INDEX
export MODEL_NAME=test-model-$INDEX
export BATCH_JOB_NAME=test-batch-prediction-$INDEX
export IMAGE_TAG=latest
export IMAGE_URI=${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}
export BUCKET=${PROJECT_ID}-vertex-r-$INDEX

cat << EOF > Dockerfile
FROM rocker/tidyverse:4.1
WORKDIR /root

COPY serve.R /root/serve.R

# Install the Google Cloud SDK
RUN apt-get update
RUN apt-get install -yy curl apt-transport-https ca-certificates gnupg
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
RUN apt-get update && apt-get install google-cloud-cli

# Install R packages
RUN install2.r --error plumber
RUN install2.r --error randomForest
RUN install2.r --error jsonlite

EXPOSE 8080
ENTRYPOINT ["Rscript", "/root/serve.R"]
EOF

cat << EOF > serve.R
#!/usr/bin/env Rscript
library(plumber)

predict <- function(req, res) {
    return(list(predictions=list(1, 2, 3)))
}

pr() %>%
    pr_get("/health", function() "OK") %>%
    pr_post("/predict", predict) %>%
    pr_run(host = "0.0.0.0", port=as.integer(Sys.getenv("AIP_HTTP_PORT", 8080)))
EOF

gcloud artifacts repositories create ${REPO_NAME} \
    --repository-format=docker \
    --location=${LOCATION}

gsutil mb -l ${LOCATION} gs://${BUCKET}
echo 42 > model.txt
gsutil cp model.txt gs://${BUCKET}/model/model.txt

gcloud builds submit --region=$LOCATION --tag=$IMAGE_URI --timeout=1h  --gcs-log-dir=gs://$BUCKET --project=${PROJECT_ID}

echo Uploading version 1 of model

gcloud ai models upload \
    --region=${LOCATION} \
    --display-name=${MODEL_NAME} \
    --model-id=${MODEL_NAME} \
    --container-image-uri=${IMAGE_URI} \
    --artifact-uri=gs://${BUCKET}/model/ \
    --container-health-route=/health \
    --container-predict-route=/predict \
    --container-command=Rscript \
    --container-args=/root/serve.R

export MODEL_ID=$(gcloud ai models list --region=${LOCATION} --filter=display_name=${MODEL_NAME} --format='value(name)' | head -n1)

#
# Run Vertex AI Batch Prediction using this model
#

# input data
cat << EOF > instances.csv
a,b,c
1,2,3
4,5,6
7,8,9
EOF

gsutil cp instances.csv gs://${BUCKET}/batch/data/instances.csv

GCS_OUTPUT="gs://${BUCKET}/batch/output/"

# batch prediction request body
cat << EOF > batch_pred_req.json
{
  "displayName": "$BATCH_JOB_NAME",
  "model": "projects/${PROJECT_ID}/locations/${LOCATION}/models/${MODEL_ID}",
  "inputConfig": {
    "instancesFormat": "csv",
    "gcsSource": {
      "uris": [
        "gs://${BUCKET}/batch/data/instances.csv"
      ]
    },
  },
  "outputConfig": {
    "predictionsFormat": "jsonl",
    "gcsDestination": {
      "outputUriPrefix": "$GCS_OUTPUT"
    }
  },
  "dedicatedResources": {
    "machineSpec": {
      "machineType": "n1-standard-32",
      "acceleratorCount": "0"
    },
    "startingReplicaCount": 1,
    "maxReplicaCount": 1
  }

}
EOF

# Create the Batch Prediction job
submit_result=$(curl -X POST \
    -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d @batch_pred_req.json \
    "https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/batchPredictionJobs")


# The work is done now, now we're just going to wait for the job to finish and get the results.

#
# Poll for job to finish
#

# first wait a bit
sleep 300

# extract job name from submit_result
JOB_NAME=$(echo $submit_result | grep name | cut -d\" -f4)
job_info=$(curl -X GET -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" https://us-central1-aiplatform.googleapis.com/v1/$JOB_NAME)

# poll for job to complete
while [[ "$(echo $job_info | grep state)" == *"JOB_STATE_SUCCEEDED"* ]]; 
do 
  date
  echo $job_info | grep state
  echo 
  sleep 300
  job_info=$(curl -X GET -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" https://us-central1-aiplatform.googleapis.com/v1/$JOB_NAME)
done

#
# Collect the output
#
JOB_OUTPUT=$(gsutil ls ${GCS_OUTPUT} | grep "^${GCS_OUTPUT}prediction-$MODEL_NAME" | sort | tail -1)

for F in $(gsutil ls $JOB_OUTPUT | grep "^${JOB_OUTPUT}prediction.errors_stats"); do gsutil cat $F; done
