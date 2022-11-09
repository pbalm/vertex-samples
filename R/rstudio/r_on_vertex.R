#install.packages(c("reticulate", "glue", "IRdisplay"), "~/Rlib")

library(glue)
library(IRdisplay)
library(reticulate)
library(glue)
library(jsonlite)


use_python(Sys.which("python3"))

# Cloud blog: "Use R to train and deploy machine learning models on Vertex AI"
#
# https://cloud.google.com/blog/products/ai-machine-learning/train-and-deploy-ml-models-with-r-and-plumber-on-vertex-ai

PROJECT_ID <- "cxb1-prj-test-no-vpcsc"
REGION <- "europe-west1"
BUCKET_URI <- glue("gs://{PROJECT_ID}-vertex-r")

DOCKER_REPO <- "vertex-r"
IMAGE_NAME <- "vertex-r-billingproj-logs"
IMAGE_TAG <- "latest"
IMAGE_URI <- glue("{REGION}-docker.pkg.dev/{PROJECT_ID}/{DOCKER_REPO}/{IMAGE_NAME}:{IMAGE_TAG}")

# Define function to execute shell commands
sh <- function(cmd, args = c(), intern = FALSE) {
  if (is.null(args)) {
    cmd <- glue(cmd)
    s <- strsplit(cmd, " ")[[1]]
    cmd <- s[1]
    if (length(s) > 1) {
      args <- s[2:length(s)]
    }
  }
  ret <- system2(cmd, args, stdout = TRUE, stderr = TRUE)
  if ("errmsg" %in% attributes(attributes(ret))$names) cat(attr(ret, "errmsg"), "\n")
  if (intern) return(ret) else cat(paste(ret, collapse = "\n"))
}


#sh("pip install --user --upgrade google-cloud-aiplatform")

# Create staging bucket (only do this once)
#sh("gsutil mb -l {REGION} -p {PROJECT_ID} {BUCKET_URI}")


aiplatform <- import("google.cloud.aiplatform")
aiplatform$init(project = PROJECT_ID, location = REGION, staging_bucket = BUCKET_URI)

# TODO: Base image is in US, can be incompatible with resource constraint
sh("gcloud builds submit --region={REGION} --tag={IMAGE_URI} --timeout=1h --billing-project={PROJECT_ID} --project={PROJECT_ID} --gcs-log-dir={BUCKET_URI}")

# Create Vertex AI Managed Dataset
data_uri <- "gs://cloud-samples-data/ai-platform-unified/datasets/tabular/california-housing-tabular-regression.csv"
dataset <- aiplatform$TabularDataset$create(
  display_name = "California Housing Dataset",
  gcs_source = data_uri
)

# Create the training job
job <- aiplatform$CustomContainerTrainingJob(
  display_name = "vertex-r",
  container_uri = IMAGE_URI,
  command = c("Rscript", "train.R"),
  model_serving_container_command = c("Rscript", "serve.R"),
  model_serving_container_image_uri = IMAGE_URI
)

# And run it - train the model
model <- job$run(
  dataset=dataset,
  model_display_name = "vertex-r-model",
  machine_type = "n1-standard-4"
)

# Create an endpoint
endpoint <- aiplatform$Endpoint$create(
  display_name = "California Housing Endpoint 4",
  project = PROJECT_ID,
  location = REGION
)

# Deploy the model
model$deploy(endpoint = endpoint, machine_type = "n1-standard-4")

# Test the model endpoint using the first 5 rows from the training dataset
df <- read.csv(text=sh("gsutil cat {data_uri}", intern = TRUE))
head(df, 5)

instances <- list(instances=head(df[, names(df) != "median_house_value"], 5))
instances

json_instances <- toJSON(instances)
# {"instances":[{"longitude":-122.23,"latitude":37.88,"housing_median_age":41,"total_rooms":880,"total_bedrooms":129,"population":322,"households":126,"median_income":8.3252},{"longitude":-122.22,"latitude":37.86,"housing_median_age":21,"total_rooms":7099,"total_bedrooms":1106,"population":2401,"households":1138,"median_income":8.3014},{"longitude":-122.24,"latitude":37.85,"housing_median_age":52,"total_rooms":1467,"total_bedrooms":190,"population":496,"households":177,"median_income":7.2574},{"longitude":-122.25,"latitude":37.85,"housing_median_age":52,"total_rooms":1274,"total_bedrooms":235,"population":558,"households":219,"median_income":5.6431},{"longitude":-122.25,"latitude":37.85,"housing_median_age":52,"total_rooms":1627,"total_bedrooms":280,"population":565,"households":259,"median_income":3.8462}]}

ENDPOINT_ID=endpoint$resource_name
ENDPOINT_ID="projects/cxb1-prj-test-no-vpcsc/locations/europe-west1/endpoints/7732557414892830720"

url <- glue("https://{REGION}-aiplatform.googleapis.com/v1/{ENDPOINT_ID}:predict")
access_token <- sh("gcloud auth print-access-token", intern = TRUE)

sh(
  "curl",
  c("--tr-encoding",
    "-s",
    "-X POST",
    glue("-H 'Authorization: Bearer {access_token}'"),
    "-H 'Content-Type: application/json'",
    url,
    glue("-d {json_instances}")
  ),
)

# Example:
#
# TOKEN=$(gcloud auth print-access-token)
# curl -X POST -H "Authorization: Bearer $TOKEN" \
# -H "Content-Type: application/json" \
# https://europe-west1-aiplatform.googleapis.com/v1/projects/cxb1-prj-test-no-vpcsc/locations/europe-west1/endpoints/7732557414892830720:predict \
# -d '{"instances":[{"longitude":-122.23,"latitude":37.88,"housing_median_age":41,"total_rooms":880,"total_bedrooms":129,"population":322,"households":126,"median_income":8.3252},{"longitude":-122.22,"latitude":37.86,"housing_median_age":21,"total_rooms":7099,"total_bedrooms":1106,"population":2401,"households":1138,"median_income":8.3014},{"longitude":-122.24,"latitude":37.85,"housing_median_age":52,"total_rooms":1467,"total_bedrooms":190,"population":496,"households":177,"median_income":7.2574},{"longitude":-122.25,"latitude":37.85,"housing_median_age":52,"total_rooms":1274,"total_bedrooms":235,"population":558,"households":219,"median_income":5.6431},{"longitude":-122.25,"latitude":37.85,"housing_median_age":52,"total_rooms":1627,"total_bedrooms":280,"population":565,"households":259,"median_income":3.8462}]}'

# Upload to Model Registry
gcs_model_loc="gs://cxb1-prj-test-no-vpcsc-vertex-r/aiplatform-custom-training-2022-10-14-13:52:14.024/model"
#gs://cxb1-prj-test-no-vpcsc-vertex-r-010-new-model-version/model

# * upload the first version with model_id="housing_prices" and subsequent versions with parent_model="housing_prices"
# * the container image, unless modified, start a JypyterLab instance on start-up. We use the serving container command
#   to make it start up a web service that serves predictions.
# * specify the predict and health routes (path in the URL to make predictions and call the heartbeat service) for the
#   batch predictions. The Endpoint will generate default routes but the Batch Prediction does not.

# This command doesn't work because I can't get it to interpret the serving command and args correctly.
# It will read a string as a list of chars that are each their own command or arg.
# The below example will make it look ok but it still doesn't work.

# uploaded_model = aiplatform$Model$upload(
#                         display_name="Housing Prices",
#                         parent_model="housing_prices", 
#                         is_default_version=T,
#                         serving_container_image_uri=IMAGE_URI,
#                         serving_container_command=c("Rscript", " "),
#                         serving_container_args=c("/root/serve.R", " "),
#                         serving_container_predict_route="/predict",
#                         serving_container_health_route="/health",
#                         artifact_uri=gcs_model_loc)

MODEL_NAME="Housing Prices"

sh(paste("gcloud ai models upload",
    "--region={REGION}",
    "--display-name=housing_prices_7_billingproj_logs",
    "--container-image-uri={IMAGE_URI}",
    paste0("--artifact-uri=", gcs_model_loc),
    "--container-health-route=/health",
    "--container-predict-route=/predict",
    "--container-command=Rscript",
    "--container-args=/root/serve.R"))
