from typing import NamedTuple

from kfp.v2.dsl import pipeline
from kfp.v2.dsl import (Condition,
                        Dataset,
                        Input,
                        Model,
                        Output,
                        component)

from kfp.v2 import compiler

from google_cloud_pipeline_components import aiplatform as gcc_aip
from google.cloud.aiplatform import pipeline_jobs


PROJECT_ID = 'vertex-internal'
BUCKET_NAME= 'gs://vertex-internal-kfp'
PIPELINE_NAME = 'taxitrips'
PIPELINE_ROOT= f'{BUCKET_NAME}/pipeline-root-{PIPELINE_NAME}'
REGION= 'us-central1'


@component(
    packages_to_install=[
        "pandas",
        "numpy",
        "statsmodels",
        "google-cloud-aiplatform",
        "google-cloud-bigquery",
        "pyarrow"
    ], base_image="python:3.9",
)
def train_ts(dataset: Input[Dataset], output_model: Output[Model]):

    import pickle
    from google.cloud import bigquery
    from google.cloud import aiplatform as vertex_ai
    from statsmodels.tsa.arima.model import ARIMA

    bqclient = bigquery.Client()

    def download_table(bq_table_uri: str):
        prefix = "bq://"
        if bq_table_uri.startswith(prefix):
            bq_table_uri = bq_table_uri[len(prefix):]

        table = bigquery.TableReference.from_string(bq_table_uri)
        rows = bqclient.list_rows(
            table,
        )
        return rows.to_dataframe(create_bqstorage_client=False)

    # get the ID of the vertex dataset
    dataset_id = '/'.join(dataset.uri.split('/')[4:])
    # List all Vertex datasets and get the one that has the right ID
    datasets = [ds for ds in vertex_ai.TabularDataset.list() if ds.resource_name == dataset_id]

    # it should be only one
    if len(datasets) != 1:
        raise Exception(f'Got {len(datasets)} datasets with ID {dataset_id} in project {PROJECT_ID} (region {REGION})')

    # Get the URI of the BigQuery dataset
    bq_uri = datasets[0].gca_resource.metadata['inputConfig']['bigquerySource']['uri']
    print(f'Loading data for dataset {dataset_id} from {bq_uri}')

    df = download_table(bq_uri)
    # TODO Exclude all data that is not training data

    print(f"Fitting ARIMA model to dataset of {len(df)} rows")

    model = ARIMA(df['trips'], order=(1, 1, 0))
    model.fit()

    # Sorry for using pickle: It's bad practice because any change of version of package that you use can mean that
    # you cannot load your model anymore. For example use SavedModel if using Keras or joblib when using sklearn.
    file_name = output_model.path + f".pkl"
    print(f"Writing model to {file_name}")
    with open(file_name, 'wb') as file:
        pickle.dump(model, file)


@component(
    packages_to_install=[
        "numpy",
        "statsmodels",
    ], base_image="python:3.9",
)
def evaluate_model(dataset: Input[Dataset], model: Input[Model]) -> NamedTuple("output", [("deploy", str)]):

    import pickle

    # model URI is passed as gs:// so I could load it with GCS client but the bucket is also mounted under /gcs so...
    model_path = '/gcs' + model.uri[4:] + '.pkl'

    print(f"Loading model {model.uri} from {model_path}")

    with open(model_path, 'rb') as f:
        model_obj = pickle.load(f)

    # TODO Run the model on the test data from the input dataset

    # This implementation just checks that the model can be retrieved
    accepted = 'go' if model_obj else 'no go'
    return (accepted, )


@component(
    packages_to_install=[
        "numpy",
        "statsmodels",
    ], base_image="python:3.9",
)
def batch_predict(model: Input[Model]):

    # Load the model again
    import pickle
    model_path = '/gcs' + model.uri[4:] + '.pkl'

    print(f"Loading model {model.uri} from {model_path}")

    with open(model_path, 'rb') as f:
        model_obj = pickle.load(f)

    # Now run the model to generate the predictions and store them in BQ.
    # You can then run more pipeline steps to tune a threshold and/or to flag the anomalies in BQ.
    print('Running model in batch to produce predictions')
    # TODO


@pipeline(name=PIPELINE_NAME, pipeline_root=PIPELINE_ROOT)
def pipeline(
    bq_source: str = "bq://vertex-internal.kfp.taxitrips",
    bucket: str = BUCKET_NAME,
    project: str = PROJECT_ID,
    gcp_region: str = REGION,
    bq_dest: str = "",
    container_uri: str = "",
    batch_destination: str = ""
):

    dataset_create_op = gcc_aip.TabularDatasetCreateOp(
        display_name=f"{PIPELINE_NAME}-dataset",
        bq_source=bq_source,
        project=project,
        location=gcp_region
    )

    # Below are two options for running training step. I would recommend the first one to get started and then move
    # over to the second one.

    # First option: Train using on-the-fly defined component:
    train_op = train_ts(dataset=dataset_create_op.outputs['dataset'].ignore_type())

    # Or:
    # - define a Dockerfile that builds an image with the training code inside
    # - build the image and push it to Artifact Registry
    # - run a CustomContainerTrainingJob using this container as below:

    # training_op = gcc_aip.CustomContainerTrainingJobRunOp(
    #     display_name="custom-train",
    #     container_uri=container_uri,
    #     project=project,
    #     location=gcp_region,
    #     dataset=dataset_create_op.outputs["dataset"],
    #     staging_bucket=bucket,
    #     training_fraction_split=0.8,
    #     validation_fraction_split=0.1,
    #     test_fraction_split=0.1,
    #     bigquery_destination=bq_dest,
    #     model_serving_container_image_uri="us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.0-24:latest",
    #     model_display_name="scikit-beans-model-pipeline",
    #     machine_type="n1-standard-4",
    #     predefined_split_column_name='datasplit'
    # )

    # batch_predict_op = gcc_aip.ModelBatchPredictOp(
    #     project=project,
    #     location=gcp_region,
    #     job_display_name="beans-batch-predict",
    #     model=training_op.outputs["model"],
    #     gcs_source_uris=["{0}/batch_examples.csv".format(BUCKET_NAME)],
    #     instances_format="csv",
    #     gcs_destination_output_uri_prefix=batch_destination,
    #     machine_type="n1-standard-4"
    # )

    evaluate_model_op = evaluate_model(dataset=dataset_create_op.outputs['dataset'].ignore_type(),
                                       model=train_op.outputs['output_model'])

    with Condition(
            evaluate_model_op.outputs["deploy"] == 'go',
            name="run-batch-predict",
    ):
        batch_predict_op = batch_predict(model=train_op.outputs['output_model'])



if __name__ == '__main__':
    compiler.Compiler().compile(pipeline_func=pipeline,
                                package_path=f'{PIPELINE_NAME}.json')

    start_pipeline = pipeline_jobs.PipelineJob(
        display_name=PIPELINE_NAME,
        template_path=f'{PIPELINE_NAME}.json',
        enable_caching=True,
        location=REGION,
    )

    start_pipeline.run()


