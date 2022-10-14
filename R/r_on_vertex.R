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

