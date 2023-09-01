# Global Model Store for Vertex AI

The "Global Model Store" aims to be a repository of all information about
pipelines and models that are being trained on Vertex AI, across different
projects and regions. As such, it allows the user to get a complete overview
of the organization.

The Global Model Store is a Cloud Function that retrieves the data and links
the information (for example by linking pipeline metadata with Model
Registry artefacts). This Cloud Function writes the data to a table in
BigQuery. On top of this BigQuery table, we can build a dashboard to
visualize the information that answers business questions, such as:

  * How many models do we have in our organization, what is their
    description and what are their performance metrics?
  * Which projects have the largest growth in resource consumption on Vertex
Training?
  * Which models have been trained on tables containing PII?

## Example Implementation

We provide here an example implementation that 

  * collects all models trained on Vertex AI Pipelines, 
  * extracts the model performance metrics and training parameters (hyperparameters, modeling framework and version), and 
  * reports the link to the model in the Model Registry

Our example implementation can be run multiple times, since it will only
retrieve data that did not exist yet during the previous run.

## User Guide

### Set up BigQuery table

First, export two variables to define the project and the region where we
will store the aggregated data from our pipelines and models:

```
export PROJECT=<my project>
export REGION=<my region>
```

In the script `bq_setup.bash`, set the `BQ_DS` and `BQ_TABLE` variables to
the BigQuery dataset and table that we want to use respectively. The dataset
and the table will be created if needed.

Execute the script `bq_setup.bash`.

### Deploy the Cloud Function

The Cloud Function is implemented in `cloudfunction/main.py` for the user to
customize to their business need.

Run the script `deploy_cloud_function.bash` from the `cloudfunction`
directory:

```
cd cloudfunction
./deploy_cloud_function.bash
```

### Configure Cloud Scheduler to trigger the Cloud Function

The Cloud Function should periodically check a given project for pipelines
and models in a given region (the project and region are passed as
arguments to the Cloud Function). We will trigger the Cloud Function using
Cloud Scheduler.

  * Access [Cloud
    Scheduler](https://pantheon.corp.google.com/cloudscheduler) in the
Console
  * Create a new Cloud Scheduler in the same project and region as the
    BigQuery dataset and table (the central project for the model store)
  * Set a frequency for the Scheduler to poll the projects, for example,
every 15 minutes: `*/15 * * * *`
  * Use target type "HTTP" and the target URL should be the URL of the Cloud
    Function, with the project and region that it should poll appended. For
example, if you wanted to collect the information about pipelines and models
from a project called `bi-project` in region `europe-west4`, the target URL
could look like this:
`https://my-modelstore-cf-kpvs43u5eq-ez.a.run.app/?project=bi-project&region=europe-west4`

### Dashboard

We do not yet provide an example dashboard here but it will be included in
the next version of this repository.
