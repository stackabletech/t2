import os
import os.path
import requests
from dateutil import parser
from datetime import datetime, timedelta

t2_url = None
t2_token = None

def process_input():
    """ 'input' means environment variables and volumes, because this script is the entrypoint of
        a Docker container.

        The input is checked for valid combinations/completeness and the values are processed.
    """
    global t2_url
    global t2_token

    if not ('T2_URL' in os.environ and 'T2_TOKEN' in os.environ):
        print('Error: Please supply T2_URL and T2_TOKEN as environment variables.')
        exit(1)
    t2_url = os.environ['T2_URL']
    t2_token = os.environ['T2_TOKEN']


def get_clusters(t2_url, t2_token):
    response = requests.get(f"{t2_url}/api/clusters", headers={ "t2-token": t2_token, "Content-Type": "application/yaml" })
    if(response.status_code != 200):
        return None
    return response.json()


def is_cluster_in_state(cluster, states):
    return (
            'status' in cluster 
        and isinstance(cluster['status'], str) 
        and cluster['status'] in states
    )


def is_failed(cluster):
    return (
        is_cluster_in_state(cluster, ['LAUNCH_FAILED', 'TERMINATION_FAILED'])
    )


def is_older_than(cluster, timedelta):
    if not ('dateTimeCreated' in cluster and isinstance(cluster['dateTimeCreated'], str)):
        return False
    try:
        return (datetime.now() - parser.parse(cluster['dateTimeCreated'])) > timedelta
    except parser.ParserError:
        return True
    

def is_running_at_least_one_day(cluster):
    return is_cluster_in_state(cluster, ['RUNNING']) and is_older_than(cluster, timedelta(days=1))


def is_starting_at_least_one_day(cluster):
    return is_cluster_in_state(cluster, ['LAUNCHING']) and is_older_than(cluster, timedelta(days=1))


def is_terminating_at_least_one_day(cluster):
    return is_cluster_in_state(cluster, ['TERMINATING']) and is_older_than(cluster, timedelta(days=1))


def print_cluster(cluster):
    print(f"{cluster['id']}: {cluster['status']}, started at {cluster['dateTimeCreated']}")


def print_summary(clusters, header):
    if clusters and len(clusters)>0:
        print()
        print(header)
        for cluster in clusters:
            print_cluster(cluster)


if __name__ == "__main__":

    process_input()

    # Get all clusters
    clusters = get_clusters(t2_url, t2_token)

    # Get the relevant subsets of clusters
    failed_clusters = [c for c in filter(is_failed, clusters)]
    long_running_clusters = [c for c in filter(is_running_at_least_one_day, clusters)]
    long_starting_clusters = [c for c in filter(is_starting_at_least_one_day, clusters)]
    long_terminating_clusters = [c for c in filter(is_terminating_at_least_one_day, clusters)]

    # Print report
    print(f"Report for {t2_url}")
    print_summary(failed_clusters, "These clusters failed:")
    print_summary(long_running_clusters, "These clusters are running for more than a day:")
    print_summary(long_starting_clusters, "These clusters are starting for more than a day:")
    print_summary(long_terminating_clusters, "These clusters are terminating for more than a day:")
