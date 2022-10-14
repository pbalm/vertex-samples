#install.packages(c("reticulate", "glue"))

library(glue)
library(IRdisplay)

# Cloud blog: "Use R to train and deploy machine learning models on Vertex AI"
#
# https://cloud.google.com/blog/products/ai-machine-learning/train-and-deploy-ml-models-with-r-and-plumber-on-vertex-ai

PROJECT_ID <- "cxb1-prj-test-no-vpcsc"
REGION <- "europe-west1"
BUCKET_URI <- glue("gs://{PROJECT_ID}-vertex-r")

DOCKER_REPO <- "vertex-r"
IMAGE_NAME <- "vertex-r"
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

library(reticulate)
library(glue)
use_python(Sys.which("python3"))

aiplatform <- import("google.cloud.aiplatform")
aiplatform$init(project = PROJECT_ID, location = REGION, staging_bucket = BUCKET_URI)

# TODO: Base image is in US, can be incompatible with resource constraint
sh("gcloud builds submit --region={REGION} --tag={IMAGE_URI} --timeout=1h")

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
  display_name = "California Housing Endpoint",
  project = PROJECT_ID,
  location = REGION
)

# Deploy the model
model$deploy(endpoint = endpoint, machine_type = "n1-standard-4")

# Test the model endpoint using the first 5 rows from the training dataset
library(jsonlite)
df <- read.csv(text=sh("gsutil cat {data_uri}", intern = TRUE))
head(df, 5)

instances <- list(instances=head(df[, names(df) != "median_house_value"], 5))
instances

json_instances <- toJSON(instances)
url <- glue("https://{REGION}-aiplatform.googleapis.com/v1/{endpoint$resource_name}:predict")
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

