from google.cloud import aiplatform
from google.cloud.aiplatform import PipelineJob
from google.cloud.aiplatform_v1 import MetadataServiceClient, ListContextsRequest
from google.api_core.client_options import ClientOptions
from google.cloud.bigquery import Client
from datetime import datetime
import pandas as pd
import logging
import json
import functions_framework


BQ_OUTPUT_PROJECT = 'pbalm-cxb-aa'
BQ_OUTPUT_DS = 'modelstore'
BQ_OUTPUT_TABLE = 'pipelines'

log = logging.getLogger()
log.addHandler(logging.StreamHandler())
log.setLevel(logging.INFO)


def get_pipeline_contexts(parent, region):
    client_options = ClientOptions(api_endpoint=f"{region}-aiplatform.googleapis.com")
    client = MetadataServiceClient(client_options=client_options)

    request = ListContextsRequest(
        parent=parent,
        filter="schema_title=\"system.PipelineRun\""
    )

    contexts = [c for c in client.list_contexts(request=request)]
    return contexts


def retrieve_metrics_job(project, region, job_data, context_map):
    schema_filter = "schema_title=\"system.Metrics\""
    job_name = job_data['run']
    log.info(f"Retrieving metrics for pipeline run {job_name}")
    aiplatform.init(project=project, location=region)
    if job_name in context_map:
        context_filter = f"in_context(\"{context_map[job_name]}\")"
        combined_filters = f"{schema_filter} AND {context_filter}"
        log.info(f"   Using filter {combined_filters}")
        artifacts = aiplatform.Artifact.list(filter=combined_filters)
        metrics = [json.dumps(a.metadata) for a in artifacts if a.metadata] # exclude empty dicts
        log.info(f"   Found {len(artifacts)} artifacts with {len(metrics)} sets of metrics for this job")
        return metrics
    else:
        log.info("No record in Metadata store for this job - this can happen if it never started")
        return []

def get_last_update_from_bq(project: str, region: str):
    bq = Client()
    sql = f'''SELECT max(update_time) ut 
        FROM `{BQ_OUTPUT_PROJECT}.{BQ_OUTPUT_DS}.{BQ_OUTPUT_TABLE}`
        WHERE project='{project}' AND region='{region}' '''
    log.info("Querying for last update:\n" + sql)
    res = bq.query(sql)
    last_update = res.to_dataframe()['ut'][0]    
    return last_update


# Retrieve the data with some arguments to allow testing outside the Cloud Function
#
# output_to_bq:    If the data retrieved should be written to BQ or not
# last_update_str: Retrieve pipeline data assuming the last update in BQ is according to this string. 
#                  Format: "2023-05-02T01:02:03". Timezone (implicit): UTC
def retrieve_data_spec(PROJECT, REGION, output_to_bq=True, last_update_arg: str = None):
    logging.info(f"Pulling from project {PROJECT} and region {REGION}")

    PARENT = f"projects/{PROJECT}/locations/{REGION}/metadataStores/default"

    if not last_update_arg:
        last_update = get_last_update_from_bq(PROJECT, REGION)

        if pd.isnull(last_update):
            log.info("No pipelines logged yet in model store. Use all.")
        else:
            last_update_arg = last_update.isoformat()
            log.info(f'Time of last update in target table was {last_update_arg} UTC')

    all_new_jobs = []
    
    if last_update_arg:
        all_new_jobs = PipelineJob.list(
            project=PROJECT,
            location=REGION,
            filter=f'update_time>\"{last_update_arg}+00:00\"'
        )
    else:
        all_new_jobs = PipelineJob.list(
            project=PROJECT,
            location=REGION
        )

    jobs = [job for job in all_new_jobs if job.done()]
    data = []
    log.info(f'Getting data from {len(jobs)} new and completed pipeline jobs')

    for job in jobs:
        job_data = {}
        job_data['name'] = job.display_name
        job_data['run'] = job.name        
        job_data['resource_name'] = job.resource_name
        job_data['url'] = f'https://console.cloud.google.com/vertex-ai/locations/{REGION}/pipelines/runs/{job.name}?project={PROJECT}'
        job_data['project'] = PROJECT
        job_data['region'] = REGION
        job_data['create_time'] = job.create_time
        job_data['update_time'] = job.update_time
        job_data['resource_name'] = job.resource_name
        job_data['labels'] = json.dumps(job.labels)
        job_data['state'] = str(job.state).split('.')[1]
        data.append(job_data)

    log.info('Pulling pipeline contexts from Vertex ML Metadata')
    contexts = get_pipeline_contexts(PARENT, REGION)
    context_map = {c.display_name: c.name for c in contexts}

    log.info('Retrieving metrics')
    for job_data in data:
        metrics = retrieve_metrics_job(PROJECT, REGION, job_data, context_map)
        job_data['metrics'] = metrics
        # log the framework as its own column, not just inside the metrics
        frameworks = []
        for m in metrics:
            m_obj = json.loads(m)
            if 'framework' in m_obj:
                frameworks.append(m_obj['framework'])
            else:
                frameworks.append('')
        job_data['framework'] = frameworks

    df = pd.DataFrame.from_records(data)
    print(df)

    if len(df) == 0:
        log.info("Nothing to output")
    else:
        log.info(f'Writing output - to BQ: {output_to_bq}')
        df.to_csv('modelstore.csv', index=False)

        with open('schema.json', 'r') as schema_file:
            schema = json.load(schema_file)

        if output_to_bq:
            df.to_gbq(
                destination_table=f'{BQ_OUTPUT_PROJECT}.{BQ_OUTPUT_DS}.{BQ_OUTPUT_TABLE}',
                project_id=BQ_OUTPUT_PROJECT,
                if_exists='append',
                table_schema=schema)

    # Return an HTTP response
    return 'OK'


# Register an HTTP function with the Functions Framework
@functions_framework.http
def retrieve_data(request):

    PROJECT = None
    if 'project' in request.args:
        PROJECT = request.args['project']
    else:
        logging.fatal('No project parameter in request')

    REGION = None
    if 'region' in request.args:
        REGION = request.args['region']
    else:
        logging.fatal('No region parameter in request')

    if not PROJECT or not REGION:
        log.fatal("Project or region not defined, expecting both these are HTTP parameters.")
        return "NOK"
    else:
        return retrieve_data_spec(PROJECT, REGION)
    

# Run code when running in stand-alone mode
#if __name__ == "main":
#    retrieve_data(None)

# SELECT name, PARSE_JSON(metrics) as json_metrics
# FROM `pbalm-cxb-aa.modelstore.pipelines`,
# UNNEST(metrics) AS metrics