import os
import os.path
import datetime
import time
import sys
import yaml
import requests
import re
import subprocess

CLUSTER_FOLDER = ".cluster/"
PRIVATE_KEY_FILE = f"{CLUSTER_FOLDER}key"
PUBLIC_KEY_FILE = f"{CLUSTER_FOLDER}key.pub"
TIMEOUT_SECONDS = 3600

EXIT_CODE_CLUSTER_FAILED = 255

def prerequisites():
    """ Checks the prerequisites of this script and fails if they are not satisfied. """
    if not 'T2_TOKEN' in os.environ:
        print("Error: Please supply T2_TOKEN as an environment variable.")
        exit(EXIT_CODE_CLUSTER_FAILED)
    if not 'T2_URL' in os.environ:
        print("Error: Please supply T2_URL as an environment variable.")
        exit(EXIT_CODE_CLUSTER_FAILED)
    if not os.path.isfile("/cluster.yaml"):
        print("Error Please supply cluster definition as file in /cluster.yaml.")
        exit(EXIT_CODE_CLUSTER_FAILED)


def init_log():
    """ Inits the log files.
        a) remove the files that will be written later
        b) create the empty testdriver log and make it accessible
    """
    os.system('rm -rf /target/testdriver.log || true')
    os.system('rm -rf /target/k8s_pod_change.log || true')
    os.system('rm -rf /target/k8s_pod_change_short.log || true')
    os.system('rm -rf /target/k8s_event.log || true')
    os.system('rm -rf /target/k8s_event_short.log || true')
    os.system('touch /target/testdriver.log')
    os.system(f"chown {uid_gid_output} /target/testdriver.log")
    os.system('chmod 664 /target/testdriver.log')
    os.system('rm -rf /target/test_output.log || true')
    os.system('rm -rf /target/stackable-versions.txt || true')


def log(msg=""):
    """ Logs the given text message to stdout AND the logfile """
    print(msg)
    sys.stdout.flush()
    f = open("/target/testdriver.log", "a")
    f.write('{:%Y-%m-%d %H:%M:%S.%s} :: '.format(datetime.datetime.now()))
    f.write(f"{msg}\n")
    f.close()    


def is_dry_run():
    """ Checks if the testdriver should be executed as a 'dry run', which means
        that the cluster is not created.
    """
    return 'DRY_RUN' in os.environ and os.environ['DRY_RUN']=='true'


def is_interactive_mode():
    """ Checks if the testdriver should be run in 'interactive mode', which means
        that the cluster is created and after that, the script waits for the file
        '/cluster_lock' to be deleted.
    """
    return 'INTERACTIVE_MODE' in os.environ and os.environ['INTERACTIVE_MODE']=='true'


def run_test_script():
    if os.path.isfile("/test.sh"):
        log(f"\n\ntest.sh:\n\n")
        with open ("/test.sh", "r") as f:
            log(f.read())
        log("\n\n")

        os.system('touch /target/test_output.log')
        os.system(f"chown {uid_gid_output} /target/test_output.log")
        os.system('chmod 664 /target/test_output.log')
        os.system('touch /target/k8s_pod_change.log')
        os.system(f"chown {uid_gid_output} /target/k8s_pod_change.log")
        os.system('chmod 664 /target/k8s_pod_change.log')
        os.system('touch /target/k8s_event.log')
        os.system(f"chown {uid_gid_output} /target/k8s_event.log")
        os.system('chmod 664 /target/k8s_event.log')
        proc_k8s_pod_changelog = subprocess.Popen(['/bin/bash', '-c', 'kubectl get pods --all-namespaces -o yaml --watch > /target/k8s_pod_change.log'])
        proc_k8s_pod_changelog_short = subprocess.Popen(['/bin/bash', '-c', 'kubectl get pods --all-namespaces --watch > /target/k8s_pod_change_short.log'])
        proc_k8s_eventlog = subprocess.Popen(['/bin/bash', '-c', 'kubectl get events --all-namespaces -o yaml --watch > /target/k8s_event.log'])
        proc_k8s_eventlog_short = subprocess.Popen(['/bin/bash', '-c', "kubectl get events --all-namespaces --watch -o=custom-columns='NAMESPACE:metadata.namespace,EVENT_TIME:eventTime,FIRST_TIMESTAMP:firstTimestamp,LAST_TIMESTAMP:lastTimestamp,TYPE:type,REASON:reason,OBJECT_KIND:involvedObject.kind,OBJECT_NAME:involvedObject.name,MESSAGE:message' > /target/k8s_event_short.log"])
        os.system('(sh /test.sh 2>&1; echo $? > /test_exit_code) | tee /target/test_output.log')
        time.sleep(15)
        proc_k8s_pod_changelog.terminate()
        proc_k8s_pod_changelog_short.terminate()
        proc_k8s_eventlog.terminate()
        proc_k8s_eventlog_short.terminate()
        with open ("/test_exit_code", "r") as f:
            return int(f.read().strip())
    else:
        log("No test script supplied.")
        return 0


def launch(): 
    """Launch a cluster.
    
    This function creates a folder .cluster/ where everything related to the cluster is stored.

    In the cluster definition, the 'publicKeys' section is extended with a generated public key. The according
    private key is used to access the cluster later.

    If the cluster launch fails, this script exits. T2 takes care of the termination of partly created clusters.

    Returns cluster UUID
    """

    os.mkdir(CLUSTER_FOLDER)
    os.system(f"ssh-keygen -f {PRIVATE_KEY_FILE} -q -N '' -C ''")
    with open (PUBLIC_KEY_FILE, "r") as f:
        public_key = f.read().strip()

    with open ("/_cluster.yaml", "r") as f:
        cluster_definition_string = f.read()
    cluster_definition_yaml = yaml.load(cluster_definition_string, Loader=yaml.FullLoader)

    if(not "publicKeys" in cluster_definition_yaml or not isinstance(cluster_definition_yaml["publicKeys"], list)):
        log("Error: The cluster definition file does not contain a valid 'publicKeys' section.")
        exit(EXIT_CODE_CLUSTER_FAILED)
    cluster_definition_yaml["publicKeys"].append(public_key)        
    with open (f"{CLUSTER_FOLDER}/_cluster.yaml", "w") as f:
        f.write(yaml.dump(cluster_definition_yaml, default_flow_style=False))
        f.close()

    log(f"\n\ncluster.yaml:\n\n{yaml.dump(cluster_definition_yaml, default_flow_style=False)}\n\n")

    start_time = time.time()        
    cluster = create_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], yaml.dump(cluster_definition_yaml, default_flow_style=False))    
    if(not cluster):
        log("Error: Failed to create cluster via API.")
        exit(EXIT_CODE_CLUSTER_FAILED)

    log(f"Created cluster '{cluster['id']}'. Waiting for cluster to be up and running...")

    cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])
    while(TIMEOUT_SECONDS > (time.time()-start_time) and cluster['status']['state'] != 'RUNNING' and  not cluster['status']['failed']):
        time.sleep(5)
        cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])

    if(cluster['status']['failed']):
        log("Cluster launch failed.")
        exit(EXIT_CODE_CLUSTER_FAILED)

    if(TIMEOUT_SECONDS <= (time.time()-start_time)):
        log("Timeout while launching cluster.")
        exit(EXIT_CODE_CLUSTER_FAILED)

    log(f"Cluster '{cluster['id']}' is up and running.")

    with open(f"{CLUSTER_FOLDER}/uuid", "w") as uuid_text_file:
        print(cluster['id'], file=uuid_text_file)

    return cluster['id']


def terminate():
    """Terminates the cluster identified by the data in the .cluster/ folder.
    """
    with open (f"{CLUSTER_FOLDER}/uuid", "r") as f:
        uuid = f.read().strip()

    start_time = time.time()        
    cluster = delete_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], uuid)    
    if(not cluster):
        log("Failed to terminate cluster via API.")
        exit(EXIT_CODE_CLUSTER_FAILED)

    log(f"Started termination of cluster '{cluster['id']}'. Waiting for cluster to be terminated...")
    cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])
    while(TIMEOUT_SECONDS > (time.time()-start_time) and cluster['status']['state'] != 'TERMINATED' and  not cluster['status']['failed']):
        time.sleep(5)
        cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])

    if(cluster['status']['failed']):
        log("Cluster termination failed.")
        exit(EXIT_CODE_CLUSTER_FAILED)

    if(TIMEOUT_SECONDS <= (time.time()-start_time)):
        log("Timeout while launching cluster.")
        exit(EXIT_CODE_CLUSTER_FAILED)

    log(f"Cluster '{cluster['id']}' is terminated.")


def create_cluster(t2_url, t2_token, cluster_definition):
    """Create a cluster using T2 REST API

    Returns:
    - JSON representing cluster (REST response)
    """
    response = requests.post(f"{t2_url}/api/clusters", data=cluster_definition, headers={ "t2-token": t2_token, "Content-Type": "application/yaml" })
    if(response.status_code != 200):
        log(f"API call to create cluster returned error code {response}")
        return None
    return response.json()


def get_cluster(t2_url, t2_token, id):
    """Get the cluster information using T2 REST API

    Returns:
    - JSON representing cluster (REST response)
    """
    response = requests.get(f"{t2_url}/api/clusters/{id}", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        log(f"API call to get cluster returned error code {response.status_code}")
        return None
    return response.json()


def delete_cluster(t2_url, t2_token, id):
    """Delete the cluster using T2 REST API

    Returns:
    - JSON representing terminated cluster (REST response)
    """
    response = requests.delete(f"{t2_url}/api/clusters/{id}", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        log(f"API call to delete cluster returned error code {response.status_code}")
        return None
    return response.json()


def download_cluster_file(t2_url, t2_token, id, resource_name, destination_path):
    """Downloads the cluster resource file with the given resource name to the given destination."""
    response = requests.get(f"{t2_url}/api/clusters/{id}/{resource_name}", headers={ "t2-token": t2_token })
    if(response.status_code != 200):
        log(f"API call to get resource '{resource_name}' returned error code {response.status_code}")
        return 
    with open (destination_path, "w") as f:
        f.write(response.text)
        f.close()


def download_cluster_files(t2_url, t2_token, id):
    """Downloads the various files belonging to the cluster using T2 REST API"""
    os.system('mkdir -p /download')
    log("Downloading Stackable client script for cluster from T2...")
    download_cluster_file(t2_url, t2_token, id, "stackable-client-script", "/download/stackable.sh")
    log("Downloading SSH config from T2...")
    download_cluster_file(t2_url, t2_token, id, "ssh-config", "/download/ssh-config")
    log("Downloading Stackable version information sheet for cluster from T2...")
    download_cluster_file(t2_url, t2_token, id, "stackable-versions", "/download/stackable-versions.txt")
    log("Downloading kubeconfig from T2...")
    download_cluster_file(t2_url, t2_token, id, "kubeconfig", "/download/kubeconfig")


def install_stackable_client_script():
    if(os.path.exists("/download/stackable.sh")):
        os.system('install /download/stackable.sh /usr/bin/stackable')
        log("Stackable client script installed as command 'stackable'")
        return

    log('Stackable client script not available on this cluster.')


def configure_ssh():
    if(os.path.exists("/download/ssh-config")):
        os.system('mkdir -p /root/.ssh/')
        os.system('cp /download/ssh-config /root/.ssh/config')
        os.chmod("/root/.ssh/config", 0o600)
        os.system(f"cp {PRIVATE_KEY_FILE} /root/.ssh/id_rsa")
        os.system(f"cp {PUBLIC_KEY_FILE} /root/.ssh/id_rsa.pub")
        os.system(f"chmod 600 /root/.ssh/id_rsa")
        os.system(f"chmod 644 /root/.ssh/id_rsa.pub")
        log("SSH configured to work directly with all cluster nodes")
        return

    log('SSH not configurable in this cluster.')


def configure_k8s_access():

    if(not os.path.exists("/download/kubeconfig")):
        log("No kubeconfig available for this cluster")
        return

    if(os.path.exists("/download/ssh-config") and os.path.exists("/download/stackable.sh")):
        (_, api_port) = create_kubeconfig_for_ssh_tunnel("/download/kubeconfig", "/root/.kube/config")
        os.system(f"stackable -i {PRIVATE_KEY_FILE} api-tunnel {api_port}")
        log("Successfully set up kubeconfig to access cluster through SSH tunnel.")
    
    else:
        os.system('cp /download/kubeconfig /root/.kube/config')
        log("Successfully set up kubeconfig to access cluster.")

    os.system("chmod 600 /root/.kube/config")


def close_ssh_tunnel():

    if(os.path.exists("/download/ssh-config") and os.path.exists("/download/stackable.sh")):
        os.system(f"stackable -i {PRIVATE_KEY_FILE} close-api-tunnel")
        log("Successfully closed SSH tunnel.")


def create_kubeconfig_for_ssh_tunnel(kubeconfig_file, kubeconfig_target_file):
    """
        Creates a kubeconfig in which the Server URL is modified to use a locally set up SSH tunnel. (using 127.0.0.1 as an address)

        Returns a tuple consisting of: 
            - the original IP/Servername of the K8s API
            - the original Port of the K8s API
    """
    with open (kubeconfig_file, "r") as f:
        kubeconfig = yaml.load(f.read(), Loader=yaml.FullLoader)

    original_server_address = kubeconfig["clusters"][0]["cluster"]["server"]

    address_pattern = re.compile('https://([^:]*):([0-9]+)')

    match = address_pattern.match(original_server_address)

    if not match:
        print('Error: No API address found in kubeconfig')
        exit(EXIT_CODE_CLUSTER_FAILED)

    original_api_hostname = match.group(1)
    original_api_port = match.group(2)

    kubeconfig["clusters"][0]["cluster"]["server"] = f"https://127.0.0.1:{original_api_port}"

    with open (kubeconfig_target_file, "w") as f:
        f.write(yaml.dump(kubeconfig, default_flow_style=False))
        f.close()

    return (original_api_hostname, original_api_port)        


def provide_version_information_sheet():

    if(os.path.exists("/download/stackable-versions.txt")):
        os.system('cp /download/stackable-versions.txt /target/')
        os.system(f"chown {uid_gid_output} /target/stackable-versions.txt")
        os.system('chmod 664 /target/stackable-versions.txt')
        log('Stackable version information available in /target/stackable-versions.txt')
        return

    log('Stackable version information not available in this cluster.')


def ex_post_logs():

    if(os.path.exists("/download/ssh-config") and os.path.exists("/download/stackable.sh")):
        os.system(r"""cat /root/.ssh/config | grep 'Host main' | cut -d ' ' -f 2 | awk -F'/' '{print "stackable "$1" '\''journalctl -u k3s-agent'\'' > /target/"$1"-k3s-agent.log"}' | sh""")


if __name__ == "__main__":

    # check if we have everything to get started
    prerequisites()

    # exit code of the T2 testdriver
    exit_code = 0

    # determine user/group for output files (default: root/root)
    uid_gid_output = "0:0"
    if 'UID_GID' in os.environ:
        uid_gid_output = os.environ['UID_GID']

    # Set target folder ownership 
    os.system(f"chown -R {uid_gid_output} /target/")

    # clear/init log files
    init_log()

    log("Starting T2 test driver...")

    dry_run = is_dry_run()
    interactive_mode = is_interactive_mode()

    # copy cluster.yaml and substitute environment variables
    os.system('envsubst < cluster.yaml > _cluster.yaml')

    if not dry_run:
        log(f"Creating a cluster using T2 at {os.environ['T2_URL']}...")
        cluster_id = launch()
        download_cluster_files(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster_id)
        install_stackable_client_script()
        configure_ssh()
        configure_k8s_access()
        provide_version_information_sheet()
    else:
        log(f"DRY RUN: Not creating a cluster!")
        os.system('cp /_cluster.yaml /target/cluster.yaml')
        os.system(f"chown -R {uid_gid_output} /target/cluster.yaml")

    if not interactive_mode:    
        log("Running test script...")
        exit_code = run_test_script()
        log("Test script finished.")
    else:
        log("Interactive mode. The testdriver will be open for business until you stop it by creating the file /cluster_lock")
        while not os.path.exists('/cluster_lock'):
            time.sleep(1)

    # Set output file ownership recursively 
    # This is important as the test script might have added files which are not controlled
    # by this Python script and therefore most probably are owned by root
    os.system(f"chown -R {uid_gid_output} /target/")

    if not dry_run:
        ex_post_logs()
        log(f"Terminating the test cluster...")
        close_ssh_tunnel()
        terminate()

    log("T2 test driver finished.")

    exit(exit_code)
