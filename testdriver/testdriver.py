import os
import os.path
import datetime
import time
import sys
from turtle import back
import yaml
import requests
import re
import threading
from datetime import datetime
from subprocess import PIPE, TimeoutExpired, Popen
from enum import Enum

class Cluster(Enum):
    NONE = "NONE"
    EXISTING = "EXISTING"
    MANAGED = "MANAGED"
    CREATE = "CREATE"
    DELETE = "DELETE"

# vars representing input
cluster_mode = None
interactive_mode = False
uid_gid_output = '0:0'
t2_url = None
t2_token = None
delete_cluster_id = None

# thread communication
thread_stop_signal = False
k8s_ping_terminated = False

# system processes running in the background (!= Python threads!)
background_processes = []

# cluster
cluster_id = None

# constants for file handles
CLUSTER_FOLDER = ".cluster/"
PRIVATE_KEY_FILE = f"{CLUSTER_FOLDER}key"
PUBLIC_KEY_FILE = f"{CLUSTER_FOLDER}key.pub"
TARGET_FOLDER = "/target/"
CLUSTER_DEFINITION_FILE = "/cluster.yaml"
TEST_SCRIPT_FILE = "/test.sh"
K8S_CONFIG_FILE = "/root/.kube/config"
CLUSTER_ACCESS_FILE = "/access.yaml"
CLUSTER_ACCESS_SCRIPT = "/access.sh"

# constants for file handles (logfiles and the like)
TESTDRIVER_LOGFILE = f"{TARGET_FOLDER}testdriver.log"
TEST_OUTPUT_LOGFILE = f"{TARGET_FOLDER}test-output.log"
STACKABLE_VERSIONS_FILE = f"{TARGET_FOLDER}stackable-versions.txt"
K8S_MONITORING_LOGFILE = f"{TARGET_FOLDER}k8s-ping.log"
K8S_MONITORING_SUMMARY_FILE = f"{TARGET_FOLDER}k8s-summary.txt"
K8S_POD_CHANGE_LOGFILE = f"{TARGET_FOLDER}k8s-pod-change.log"
K8S_POD_CHANGE_LOGFILE_SHORT = f"{TARGET_FOLDER}k8s-pod-change-short.log"
K8S_EVENT_WATCH_LOGFILE = f"{TARGET_FOLDER}k8s-event-watch.log"
K8S_EVENT_WATCH_LOGFILE_SHORT = f"{TARGET_FOLDER}k8s-event-watch-short.log"
K8S_EVENT_LIST_LOGFILE = f"{TARGET_FOLDER}k8s-event-list.log"
K8S_EVENT_LIST_LOGFILE_SHORT = f"{TARGET_FOLDER}k8s-event-list-short.log"
OUTPUT_FILES = [ TESTDRIVER_LOGFILE, TEST_OUTPUT_LOGFILE, K8S_MONITORING_LOGFILE, 
                    K8S_MONITORING_SUMMARY_FILE, K8S_POD_CHANGE_LOGFILE, K8S_POD_CHANGE_LOGFILE_SHORT,
                    K8S_EVENT_WATCH_LOGFILE, K8S_EVENT_WATCH_LOGFILE_SHORT, K8S_EVENT_LIST_LOGFILE, K8S_EVENT_LIST_LOGFILE_SHORT, STACKABLE_VERSIONS_FILE]

# misc constants
CLUSTER_LAUNCH_TIMEOUT = 3600
EXIT_CODE_CLUSTER_FAILED = 255

def process_input():
    """ 'input' means environment variables and volumes, because this script is the entrypoint of
        a Docker container.

        The input is checked for valid combinations/completeness and the values are processed.
    """
    global cluster_mode
    global interactive_mode
    global uid_gid_output
    global t2_url
    global t2_token
    global delete_cluster_id

    if not ('CLUSTER' in os.environ and os.environ['CLUSTER'] in Cluster._member_map_):
        print('Error: Please supply CLUSTER (values: NONE, EXISTING, MANAGED) as an environment variable.')
        exit(EXIT_CODE_CLUSTER_FAILED)
    
    cluster_mode = Cluster._member_map_[os.environ['CLUSTER']]

    interactive_mode = 'INTERACTIVE_MODE' in os.environ and os.environ['INTERACTIVE_MODE'].capitalize() == str(True)

    if 'UID_GID' in os.environ:
        uid_gid_output = os.environ['UID_GID']

    if cluster_mode == Cluster.MANAGED or cluster_mode == Cluster.CREATE or cluster_mode == Cluster.DELETE:
        if not ('T2_URL' in os.environ and 'T2_TOKEN' in os.environ):
            print('Error: For cluster mode MANAGED, please supply T2_URL and T2_TOKEN as environment variables.')
            exit(EXIT_CODE_CLUSTER_FAILED)
        t2_url = os.environ['T2_URL']
        t2_token = os.environ['T2_TOKEN']

    if not os.path.isdir(TARGET_FOLDER):
        print(f"Error: A target folder volume has to be supplied as {TARGET_FOLDER}. ")
        exit(EXIT_CODE_CLUSTER_FAILED)

    if cluster_mode == Cluster.MANAGED or cluster_mode == Cluster.CREATE:
        if not os.path.isfile(CLUSTER_DEFINITION_FILE):
            print(f"Error: For cluster mode MANAGED or CREATE, please supply a cluster definition as {CLUSTER_DEFINITION_FILE}")
            exit(EXIT_CODE_CLUSTER_FAILED)

    if cluster_mode == Cluster.EXISTING:
        if not (os.path.isfile(K8S_CONFIG_FILE) or os.path.isfile(CLUSTER_ACCESS_FILE)):
            print(f"Error: For cluster mode EXISTING, please supply either a T2 cluster access file as {CLUSTER_ACCESS_FILE} or a Kubernetes config file as {K8S_CONFIG_FILE}")
            exit(EXIT_CODE_CLUSTER_FAILED)

    if cluster_mode == Cluster.DELETE:
        if not 'CLUSTER_ID' in os.environ:
            print(f"Error: For cluster mode DELETE, please supply the ID of the cluster to delete as CLUSTER_ID")
            exit(EXIT_CODE_CLUSTER_FAILED)
        delete_cluster_id = os.environ['CLUSTER_ID']

    if not interactive_mode and cluster_mode in [Cluster.NONE, Cluster.MANAGED, Cluster.EXISTING]:
        if not os.path.isfile(TEST_SCRIPT_FILE):
            print('Error: Please supply a test script as /test.sh')
            exit(EXIT_CODE_CLUSTER_FAILED)


def set_target_folder_owner():
    """
        The target folder must be owned by the user/group given as UID_GID.
    """
    os.system(f"chown -R {uid_gid_output} {TARGET_FOLDER}")


def interactive_mode_wait():
    """ Waits for the termination of the interactive mode.
    """
    while not os.path.exists('/session_stopped'):
        time.sleep(1)
    log("Interactive session terminated")


def append_bytes(file, content):
    with open (file, "ab") as f:
        f.write(content)
        f.close()


def append_string(file, content):
    with open (file, "a") as f:
        f.write(content)
        f.close()


def timestamp():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def ping_k8s():
    global k8s_ping_terminated
    summary = { 0: 0, -1: 0}
    while not thread_stop_signal:
        proc = Popen(['/bin/bash', '-c', 'kubectl get pods --no-headers --all-namespaces --field-selector status.phase=Running'], stdout=PIPE, stderr=PIPE)
        try:
            out, error = proc.communicate(timeout=10)
        except TimeoutExpired:
            proc.kill()
            out, error = proc.communicate()
        if proc.returncode == 0:
            append_string(K8S_MONITORING_LOGFILE, f"{timestamp()} OK ({len(out)} bytes).\n")
            summary[proc.returncode] = summary[proc.returncode] + 1
        elif proc.returncode < 0:
            append_string(K8S_MONITORING_LOGFILE, f"{timestamp()} Timeout after 10 seconds.\n")
            summary[-1] = summary[-1] + 1
        else:
            append_string(K8S_MONITORING_LOGFILE, f"{timestamp()} Error. exit code={proc.returncode}.\n")
            append_bytes(K8S_MONITORING_LOGFILE, error)
            if proc.returncode in summary:
                summary[proc.returncode] = summary[proc.returncode] + 1
            else:
                summary[proc.returncode] = 1
        time.sleep(5)

    summary_text = f"""Ping statistics (kubectl get pods)

total # of pings:       {str(sum(summary.values())).rjust(8)}
# of successful pings:  {str(summary[0]).rjust(8)}
# of timed out pings:   {str(summary[-1]).rjust(8)}
# of errors:            {str(sum(summary.values()) - (summary[0] + summary[-1])).rjust(8)}
"""

    with open (K8S_MONITORING_SUMMARY_FILE, "w") as f:
        f.write(summary_text)
        f.close()

    k8s_ping_terminated = True


def start_k8s_monitoring():
    threading.Thread(target=ping_k8s, args=()).start()
    background_processes.append(Popen(['/bin/bash', '-c', f"kubectl get pods --all-namespaces -o yaml --watch > {K8S_POD_CHANGE_LOGFILE}"]))
    background_processes.append(Popen(['/bin/bash', '-c', f"kubectl get pods --all-namespaces --watch > {K8S_POD_CHANGE_LOGFILE_SHORT}"]))
    background_processes.append(Popen(['/bin/bash', '-c', f"kubectl get events --all-namespaces -o yaml --watch > {K8S_EVENT_WATCH_LOGFILE}"]))
    background_processes.append(Popen(['/bin/bash', '-c', f"kubectl get events --all-namespaces --watch -o=custom-columns='NAMESPACE:metadata.namespace,EVENT_TIME:eventTime,FIRST_TIMESTAMP:firstTimestamp,LAST_TIMESTAMP:lastTimestamp,TYPE:type,REASON:reason,OBJECT_KIND:involvedObject.kind,OBJECT_NAME:involvedObject.name,MESSAGE:message' > {K8S_EVENT_WATCH_LOGFILE_SHORT}"]))


def stop_all_background_tasks():
    """ Sets the stop signal to all background tasks and waits for them to be terminated.
        Must only be called from the MAIN thread.
        Furthermore, this method stops the system processes running in the background.
    """
    global thread_stop_signal
    
    for p in background_processes:
        p.terminate()

    thread_stop_signal = True
    while(not (k8s_ping_terminated)):
        time.sleep(1)


def init_output_files():
    """ Inits all the output files of the testdriver

        'init' means
        a) remove the files (to cleanup leftovers when a target folder is reused)
        b) create them as new, empty files
        c) change the owner according to the UID/GID given
        d) make it writable for the owner and world-readable
    """

    for file in OUTPUT_FILES:    
        os.system(f"rm -rf {file} || true")
        os.system(f"touch {file}")
        os.system(f"chown {uid_gid_output} {file}")
        os.system(f"chmod 664 {file}")


def log(msg=""):
    """ Logs the given text message to stdout AND the logfile """
    print(msg)
    sys.stdout.flush()
    f = open("/target/testdriver.log", "a")
    f.write('{:%Y-%m-%d %H:%M:%S.%s} :: '.format(datetime.now()))
    f.write(f"{msg}\n")
    f.close()    


def run_test_script():
    if os.path.isfile("/test.sh"):
        log(f"\n\ntest.sh:\n\n")
        with open ("/test.sh", "r") as f:
            log(f.read())
        log("\n\n")

    os.system(f"(sh /test.sh 2>&1; echo $? > /test_exit_code) | tee {TEST_OUTPUT_LOGFILE}")
    time.sleep(15)
    with open ("/test_exit_code", "r") as f:
        return int(f.read().strip())


def connect_with_cluster_access_file():
    with open (CLUSTER_ACCESS_FILE, "r") as f:
        cluster_access_file = yaml.load(f.read(), Loader=yaml.FullLoader)
        if 'access_script' in cluster_access_file:
            log("The T2 cluster access file contains an access script.")
            log("Writing access script to file...")
            with open (CLUSTER_ACCESS_SCRIPT, "w") as f:
                f.write(cluster_access_file['access_script'])
                f.close()
            os.system(f"chmod o+x {CLUSTER_ACCESS_SCRIPT}")
            log(f"Written access script to {CLUSTER_ACCESS_SCRIPT}.")
            log("Executing access script...")
            os.system(CLUSTER_ACCESS_SCRIPT)
            log("Executed access script.")
            return True
        elif 'kubeconfig' in cluster_access_file:
            log("The T2 cluster access file contains a kubeconfig.")
            log("Writing kubeconfig to file...")
            with open (K8S_CONFIG_FILE, "w") as f:
                f.write(cluster_access_file['kubeconfig'])
                f.close()
            log(f"Written kubeconfig to {K8S_CONFIG_FILE}.")
            return True

        log("Invalid T2 cluster access file.")
        return False


def connect_to_existing_cluster():
    if os.path.isfile(K8S_CONFIG_FILE):
        log(f"A kubeconfig file was supplied as {K8S_CONFIG_FILE}. The testdriver will use it to connect to the cluster")
        return True

    log(f"A T2 cluster access file was supplied as {CLUSTER_ACCESS_FILE}.")
    return connect_with_cluster_access_file()


def prepare_managed_cluster():

    # Create folder which holds cluster metadata
    os.system(f"rm -rf {CLUSTER_FOLDER} || true")
    os.mkdir(CLUSTER_FOLDER)

    # copy cluster definition and substitute environment variables
    os.system(f"envsubst < {CLUSTER_DEFINITION_FILE} > {CLUSTER_FOLDER}cluster.yaml")

    # save a copy in the target folder for the users to see the final cluster definition
    os.system(f"cp {CLUSTER_FOLDER}cluster.yaml {TARGET_FOLDER}cluster.yaml")
    os.system(f"chown -R {uid_gid_output} {TARGET_FOLDER}cluster.yaml")



def launch_cluster(): 
    """Launch a cluster.
    
    This function creates a folder .cluster/ where everything related to the cluster is stored.

    In the cluster definition, the 'publicKeys' section is extended with a generated public key. The according
    private key is used to access the cluster later.

    If the cluster launch fails, this script exits. T2 takes care of the termination of partly created clusters.

    Returns cluster ID (in UUID format)
    """

    # Generate SSH key
    os.system(f"ssh-keygen -f {PRIVATE_KEY_FILE} -q -N '' -C ''")
    with open (PUBLIC_KEY_FILE, "r") as f:
        public_key = f.read().strip()

    # Put SSH key in cluster definition file
    with open (f"{TARGET_FOLDER}cluster.yaml", "r") as f:
        cluster_definition_string = f.read()
    cluster_definition_yaml = yaml.load(cluster_definition_string, Loader=yaml.FullLoader)

    if(not "publicKeys" in cluster_definition_yaml or not isinstance(cluster_definition_yaml["publicKeys"], list)):
        cluster_definition_yaml["publicKeys"] = []
    cluster_definition_yaml["publicKeys"].append(public_key)        
    with open (f"{CLUSTER_FOLDER}/cluster.yaml", "w") as f:
        f.write(yaml.dump(cluster_definition_yaml, default_flow_style=False))
        f.close()

    # Dump cluster definiton 
    log(f"\n\ncluster.yaml:\n\n{yaml.dump(cluster_definition_yaml, default_flow_style=False)}\n\n")

    # Create cluster using T2 API
    start_time = time.time()        
    cluster = create_cluster(t2_url, t2_token, yaml.dump(cluster_definition_yaml, default_flow_style=False))    
    if(not cluster):
        log("Error: Failed to create cluster via API.")
        exit(EXIT_CODE_CLUSTER_FAILED)
    log(f"Created cluster '{cluster['id']}'. Waiting for cluster to be up and running...")

    # Wait for cluster to be up and running
    cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])
    while(CLUSTER_LAUNCH_TIMEOUT > (time.time()-start_time) and cluster['status']['state'] != 'RUNNING' and  not cluster['status']['failed']):
        time.sleep(5)
        cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])

    # Cluster launch failed
    if(cluster['status']['failed']):
        log("Cluster launch failed.")
        exit(EXIT_CODE_CLUSTER_FAILED)

    # Cluster launch exceeds timeout
    if(CLUSTER_LAUNCH_TIMEOUT <= (time.time()-start_time)):
        log("Timeout while launching cluster.")
        exit(EXIT_CODE_CLUSTER_FAILED)

    # Cluster is up and running
    log(f"Cluster '{cluster['id']}' is up and running.")

    return cluster['id']


def terminate_cluster(cluster_id):
    """Terminates the cluster identified by the data in the .cluster/ folder.
    """
    log(f"Terminating the test cluster...")

    start_time = time.time()        
    cluster = delete_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster_id)    
    if(not cluster):
        log("Failed to terminate cluster via API.")
        exit(EXIT_CODE_CLUSTER_FAILED)

    log(f"Started termination of cluster '{cluster['id']}'. Waiting for cluster to be terminated...")
    cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])
    while(CLUSTER_LAUNCH_TIMEOUT > (time.time()-start_time) and cluster['status']['state'] != 'TERMINATED' and  not cluster['status']['failed']):
        time.sleep(5)
        cluster = get_cluster(os.environ["T2_URL"], os.environ["T2_TOKEN"], cluster['id'])

    if(cluster['status']['failed']):
        log("Cluster termination failed.")
        exit(EXIT_CODE_CLUSTER_FAILED)

    if(CLUSTER_LAUNCH_TIMEOUT <= (time.time()-start_time)):
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
    log("Downloading Stackable client script for cluster from T2...")
    download_cluster_file(t2_url, t2_token, id, "stackable-client-script", "/tmp/stackable.sh")
    log("Downloading SSH config from T2...")
    download_cluster_file(t2_url, t2_token, id, "ssh-config", "/tmp/ssh-config")
    log("Downloading Stackable version information sheet for cluster from T2...")
    download_cluster_file(t2_url, t2_token, id, "stackable-versions", STACKABLE_VERSIONS_FILE)
    log("Downloading cluster access file for cluster from T2...")
    download_cluster_file(t2_url, t2_token, id, "access", CLUSTER_ACCESS_FILE)


def install_stackable_client_script():
    if(os.path.exists("/tmp/stackable.sh")):
        os.system('install /tmp/stackable.sh /usr/bin/stackable')
        log("Stackable client script installed as command 'stackable'")
        return

    log('Stackable client script not available on this cluster.')


def configure_ssh():
    if(os.path.exists("/tmp/ssh-config")):
        os.system('mkdir -p /root/.ssh/')
        os.system('cp /tmp/ssh-config /root/.ssh/config')
        os.chmod("/root/.ssh/config", 0o600)
        os.system(f"cp {PRIVATE_KEY_FILE} /root/.ssh/id_rsa")
        os.system(f"cp {PUBLIC_KEY_FILE} /root/.ssh/id_rsa.pub")
        os.system(f"chmod 600 /root/.ssh/id_rsa")
        os.system(f"chmod 644 /root/.ssh/id_rsa.pub")
        log("SSH configured to work directly with all cluster nodes")
        return

    log('SSH not configurable in this cluster.')


def write_retrospective_logs():

    try:
        process_dump_events_1 = Popen(['/bin/bash', '-c', f"kubectl get events --all-namespaces -o yaml > {K8S_EVENT_LIST_LOGFILE}"])
        process_dump_events_1.wait(timeout=120)
    except TimeoutExpired:
        pass

    try:
        process_dump_events_2 = Popen(['/bin/bash', '-c', f"kubectl get events --all-namespaces -o=custom-columns='NAMESPACE:metadata.namespace,EVENT_TIME:eventTime,FIRST_TIMESTAMP:firstTimestamp,LAST_TIMESTAMP:lastTimestamp,TYPE:type,REASON:reason,OBJECT_KIND:involvedObject.kind,OBJECT_NAME:involvedObject.name,MESSAGE:message' > {K8S_EVENT_LIST_LOGFILE_SHORT}"])
        process_dump_events_2.wait(timeout=120)
    except TimeoutExpired:
        pass

    if(os.path.exists("/usr/bin/stackable")):
        os.system(r"""cat /root/.ssh/config | grep 'Host main' | cut -d ' ' -f 2 | awk -F'/' '{print "stackable "$1" '\''journalctl -u k3s-agent'\'' > /target/"$1"-k3s-agent.log"}' | sh""")


if __name__ == "__main__":

    exit_code = 0
    cluster_connection_successful = False
    
    process_input()
    set_target_folder_owner()
    init_output_files()

    log("Starting T2 test driver...")

    if cluster_mode == Cluster.NONE:
        log("Testdriver operates without any cluster.")
    elif cluster_mode == Cluster.EXISTING:
        log("Testdriver operates on existing cluster.")
        cluster_connection_successful = connect_to_existing_cluster()
    elif cluster_mode == Cluster.MANAGED:
        log("Testdriver launches new managed cluster...")
        prepare_managed_cluster()
        cluster_id = launch_cluster()
        download_cluster_files(t2_url, t2_token, cluster_id)
        install_stackable_client_script()
        configure_ssh()
        cluster_connection_successful = connect_with_cluster_access_file()
    elif cluster_mode == Cluster.CREATE:
        log("Testdriver launches new cluster (create only, non-managed)...")
        prepare_managed_cluster()
        cluster_id = launch_cluster()
        download_cluster_files(t2_url, t2_token, cluster_id)
        cluster_connection_successful = connect_with_cluster_access_file()
        os.system(f"cp {CLUSTER_ACCESS_FILE} {TARGET_FOLDER}access.yaml")
    elif cluster_mode == Cluster.DELETE:
        cluster_id = delete_cluster_id

    # Start K8s cluster monitoring if we have a successfully created managed or existing cluster
    if(cluster_mode in [Cluster.EXISTING, Cluster.MANAGED] and cluster_connection_successful):
        log("Start Kubernetes cluster monitoring...")
        start_k8s_monitoring()
        log("Started Kubernetes cluster monitoring.")

    # Execute the test or go into interactive mode (mutually exclusive)
    if (cluster_mode == Cluster.NONE) or (cluster_connection_successful and (cluster_mode in [Cluster.EXISTING, Cluster.MANAGED])):

        if interactive_mode:
            log("Testdriver started in interactive mode.")
            log("To stop the cluster, please execute the stop-session command in the container.")
            interactive_mode_wait()
        else:
            log("Starting test script...")
            exit_code = run_test_script()
            log(f"Test script terminated with exit code {exit_code}")

    # Stop K8s cluster monitoring if we have a successfully created managed or existing cluster
    if(cluster_mode in [Cluster.EXISTING, Cluster.MANAGED] and cluster_connection_successful):

        if(cluster_mode in [Cluster.EXISTING, Cluster.MANAGED]):
            log("Stopping all background tasks...")        
            stop_all_background_tasks()
            log("All background tasks are stopped.")        

            log("Log stuff after_execution")
            write_retrospective_logs()

    # Stop K8s cluster
    if(cluster_mode in [Cluster.MANAGED, Cluster.DELETE]):
        terminate_cluster(cluster_id)

    # Set output file ownership recursively 
    # This is important as the test script might have added files which are not controlled
    # by this Python script and therefore most probably are owned by root
    set_target_folder_owner()

    log("T2 test driver finished.")
    exit(exit_code)
