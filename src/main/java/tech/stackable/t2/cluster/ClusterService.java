package tech.stackable.t2.cluster;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.text.MessageFormat;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Random;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Repository;
import org.springframework.util.CollectionUtils;

import tech.stackable.t2.ansible.AnsibleResult;
import tech.stackable.t2.ansible.AnsibleService;
import tech.stackable.t2.api.ClusterNotFoundException;
import tech.stackable.t2.api.ClusterNotRunningException;
import tech.stackable.t2.api.IllegalClusterStateTransitionException;
import tech.stackable.t2.domain.Cluster;
import tech.stackable.t2.domain.Status;
import tech.stackable.t2.files.FileService;
import tech.stackable.t2.terraform.TerraformResult;
import tech.stackable.t2.terraform.TerraformService;
import tech.stackable.t2.util.RetryUtil;

/**
 * Creation and Termination of clusters
 */
@Repository
public class ClusterService {

    private static final Logger LOGGER = LoggerFactory.getLogger(ClusterService.class);

    @Autowired
    private FileService fileService;

    @Autowired
    private TerraformService terraformService;

    @Autowired
    private AnsibleService ansibleService;

    /**
     * This is the main storage for all clusters (by UUID).
     * 
     * Currently, this only exists in memory.
     */
    private Map<UUID, Cluster> clusters = new HashMap<>();

    /**
     * Get list of all clusters.
     * 
     * @return list of all clusters
     */
    public List<Cluster> getClusters() {
        return this.getClusters(null);
    }

    /**
     * Get list of clusters filtered by status.
     * 
     * @param statusFilter Set of Status values to be included in the list.
     * @return list of clusters, filtered by status
     */
    public List<Cluster> getClusters(Set<Status> statusFilter) {
        return this.clusters.values().stream()
                .filter(cluster -> (CollectionUtils.isEmpty(statusFilter) || statusFilter.contains(cluster.getStatus())))
                .collect(Collectors.toList());
    }

    /**
     * Get a cluster by its ID.
     * 
     * @param id ID of the cluster
     * @return cluster with the given ID
     */
    public Optional<Cluster> getCluster(UUID id) {
        return Optional.ofNullable(this.clusters.get(id));
    }

    /**
     * Set the status of a cluster.
     * 
     * There are only two allowed status changes:
     * 
     * <ul>
     * <li>{@link Status#LAUNCH_FAILED} to {@link Status#TERMINATED_MANUALLY}</li>
     * <li>{@link Status#TERMINATION_FAILED} to {@link Status#TERMINATED_MANUALLY}</li>
     * </ul>
     * 
     * @param id     ID of the cluster
     * @param status status to set on the cluster
     * @return cluster with the given ID and new status
     */
    public Cluster setClusterStatus(UUID id, Status status) {
        synchronized (this.clusters) {
            Cluster cluster = this.clusters.get(id);
            if (cluster == null) {
                throw new ClusterNotFoundException(MessageFormat.format("No cluster found with ID {0}", id));
            }
            synchronized (cluster) {
                if ((cluster.getStatus() == Status.LAUNCH_FAILED || cluster.getStatus() == Status.TERMINATION_FAILED) && status == Status.TERMINATED_MANUALLY) {
                    cluster.setStatus(status);
                    cluster.addEvent(MessageFormat.format("Status set to {0}", status));
                    return cluster;
                } else {
                    throw new IllegalClusterStateTransitionException(MessageFormat.format("The status of the cluster {0} cannot be set to {1}.", id, status));
                }
            }
        }
    }

    /**
     * Start the creation of a new cluster.
     * 
     * @param clusterDefinition definition of the new cluster
     * @return cluster metadata
     */
    public Cluster startClusterCreation(Map<String, Object> clusterDefinition) {
        synchronized (this.clusters) {

            Cluster cluster = new Cluster();

            synchronized (cluster) {
                Path workingDirectory = this.fileService.workingDirectory(cluster.getId());
                cluster.addEvent(MessageFormat.format("Creating working directory {0}...", workingDirectory));
                this.fileService.createWorkingDirectory(workingDirectory, clusterDefinition);
                cluster.addEvent(MessageFormat.format("Created working directory {0}.", workingDirectory));
                
                cluster.setStatus(Status.LAUNCHING);

                clusters.put(cluster.getId(), cluster);

                // Wait a certain amount of time after Terraform apply
                final int waitAfterTerraformApply = 
                    (
                        ((Map<String, Object>) clusterDefinition.get("spec")).containsKey("waitAfterTerraform") &&
                        ((Map<String, Object>) clusterDefinition.get("spec")).get("waitAfterTerraform") instanceof Integer 
                    ) ? ((Integer)((Map<String, Object>) clusterDefinition.get("spec")).get("waitAfterTerraform")).intValue() : 0;

                // Launching cluster in new thread
                new Thread(() -> {

                    final AtomicBoolean eventualFailureFlag = new AtomicBoolean(false);

                    RetryUtil.<TerraformResult>retryTask(
                        1,
                        30,
                        () -> {
                            return this.terraformService.init(cluster.getId());
                        },
                        TerraformResult.ERROR,
                        tryNumber -> {
                            cluster.addEvent(MessageFormat.format("Terraform init started (try #{0}).", tryNumber));
                        }, 
                        (tfResult, tryNumber) -> {
                            cluster.addEvent(MessageFormat.format("Terraform init failed with result {0} after {1} tries.", tfResult, tryNumber));
                            cluster.addEvent("Working directory cleanup started...");
                            this.fileService.cleanUpWorkingDirectory(workingDirectory);
                            cluster.addEvent("Working directory cleaned up.");
                            cluster.setStatus(Status.LAUNCH_FAILED);
                            eventualFailureFlag.set(true);
                        }
                    );

                    if(eventualFailureFlag.get()) {
                        return;
                    }
                    cluster.addEvent("Terraform init successful.");

                    RetryUtil.<TerraformResult>retryTask(
                        1,
                        30,
                        () -> {
                            return this.terraformService.plan(cluster.getId());
                        },
                        TerraformResult.ERROR,
                        tryNumber -> {
                            cluster.addEvent(MessageFormat.format("Terraform plan started (try #{0}).", tryNumber));
                        }, 
                        (tfResult, tryNumber) -> {
                            cluster.addEvent(MessageFormat.format("Terraform plan failed with result {0} after {1} tries.", tfResult, tryNumber));
                            cluster.addEvent("Working directory cleanup started...");
                            this.fileService.cleanUpWorkingDirectory(workingDirectory);
                            cluster.addEvent("Working directory cleaned up.");
                            cluster.setStatus(Status.LAUNCH_FAILED);
                            eventualFailureFlag.set(true);
                        }
                    );

                    if(eventualFailureFlag.get()) {
                        return;
                    }
                    cluster.addEvent("Terraform plan successful.");

                    RetryUtil.<TerraformResult>retryTask(
                        1,
                        30,
                        () -> {
                            return this.terraformService.apply(cluster.getId());
                        },
                        TerraformResult.ERROR,
                        tryNumber -> {
                            cluster.addEvent(MessageFormat.format("Terraform apply started (try #{0}).", tryNumber));
                        }, 
                        (tfResult, tryNumber) -> {
                            cluster.addEvent(MessageFormat.format("Terraform apply failed with result {0} after {1} tries.", tfResult, tryNumber));
                            cleanupAfterFailedLaunch(cluster);
                            eventualFailureFlag.set(true);
                        }
                    );

                    if(eventualFailureFlag.get()) {
                        return;
                    }
                    cluster.addEvent("Terraform apply successful.");

                    if(waitAfterTerraformApply > 0) {
                        cluster.addEvent(MessageFormat.format("Waiting after Terraform apply for {0} minutes.", waitAfterTerraformApply));
                        try {
                            Thread.sleep(waitAfterTerraformApply * 60_000);
                        } catch (InterruptedException e) {
                            cluster.addEvent(MessageFormat.format("Waiting after Terraform apply for {0} minutes was interrupted.", waitAfterTerraformApply));
                            cleanupAfterFailedLaunch(cluster);
                            eventualFailureFlag.set(true);
                        }
                    }

                    RetryUtil.<AnsibleResult>retryTask(
                        1,
                        30,
                        () -> {
                            return this.ansibleService.launch(cluster.getId());
                        },
                        AnsibleResult.ERROR,
                        tryNumber -> {
                            cluster.addEvent(MessageFormat.format("Ansible launch started (try #{0}).", tryNumber));
                        }, 
                        (tfResult, tryNumber) -> {
                            cluster.addEvent(MessageFormat.format("Ansible launch failed with result {0} after {1} tries.", tfResult, tryNumber));
                            cleanupAfterFailedLaunch(cluster);
                            eventualFailureFlag.set(true);
                        }
                    );
                    
                    if(eventualFailureFlag.get()) {
                        return;
                    }
                    cluster.addEvent("Ansible launch successful.");
                    cluster.addEvent("Cluster up and running!");
                    cluster.setStatus(Status.RUNNING);

                }).start();
            }

            return cluster;
        }
    }

    /**
     * Cleans up after a failed cluster launch and eventually sets the status to {@link Status#LAUNCH_FAILED}.
     * 
     * The cleanup happens in a separate thread!
     * 
     * @param cluster cluster to be cleaned up.
     */
    private void cleanupAfterFailedLaunch(Cluster cluster) {
        new Thread(() -> {
            synchronized (cluster) {
                Path workingDirectory = this.fileService.workingDirectory(cluster.getId());

                cluster.addEvent("Ansible cleanup started.");
                AnsibleResult ansibleResult = this.ansibleService.cleanup(cluster.getId());
                if (ansibleResult == AnsibleResult.SUCCESS) {
                    cluster.addEvent("Ansible cleanup successful.");
                } else {
                    cluster.addEvent("Ansible cleanup failed.");
                }

                cluster.addEvent("Terraform destroy started.");
                TerraformResult terraformResult = this.terraformService.destroy(cluster.getId());
                if (terraformResult == TerraformResult.SUCCESS) {
                    cluster.addEvent("Terraform destroy successful.");
                } else {
                    cluster.addEvent(MessageFormat.format("Terraform destroy failed with result {0}", terraformResult));
                }

                cluster.addEvent("Working directory cleanup started...");
                this.fileService.cleanUpWorkingDirectory(workingDirectory);
                cluster.addEvent("Working directory cleaned up.");

                cluster.setStatus(Status.LAUNCH_FAILED);
            }
        }).start();
    }

    /**
     * Starts the deletion/termination of a cluster.
     * 
     * @param id ID of the cluster
     * @return cluster metadata
     */
    public Optional<Cluster> startClusterDeletion(UUID id) {
        synchronized (this.clusters) {
            Cluster cluster = this.clusters.get(id);
            if (cluster == null) {
                return Optional.empty();
            }

            synchronized (cluster) {
                if (cluster.getStatus() != Status.RUNNING) {
                    throw new ClusterNotRunningException(MessageFormat.format("The cluster {0} is not running.", id));
                }

                cluster.setStatus(Status.TERMINATING);

                new Thread(() -> {
                    synchronized (cluster) {
                        Path workingDirectory = this.fileService.workingDirectory(cluster.getId());

                        AnsibleResult ansibleResult = RetryUtil.<AnsibleResult>retryTask(
                            3,
                            30,
                            () -> {
                                return this.ansibleService.cleanup(cluster.getId());
                            },
                            AnsibleResult.ERROR,
                            tryNumber -> {
                                cluster.addEvent(MessageFormat.format("Ansible cleanup started (try #{0}).", tryNumber));
                            }, 
                            (tfResult, tryNumber) -> {
                                cluster.addEvent(MessageFormat.format("Ansible cleanup failed with result {0} after {1} tries.", tfResult, tryNumber));
                            }
                        );

                        if(ansibleResult == AnsibleResult.SUCCESS) {
                            cluster.addEvent("Ansible cleanup successful.");
                        }
    
                        TerraformResult terraformResult = RetryUtil.<TerraformResult>retryTask(
                            3,
                            30,
                            () -> {
                                return this.terraformService.destroy(cluster.getId());
                            },
                            TerraformResult.ERROR,
                            tryNumber -> {
                                cluster.addEvent(MessageFormat.format("Terraform destroy started (try #{0}).", tryNumber));
                            }, 
                            (tfResult, tryNumber) -> {
                                cluster.addEvent(MessageFormat.format("Terraform destroy failed with result {0} after {1} tries.", tfResult, tryNumber));
                            }
                        );
    
                        if(terraformResult == TerraformResult.SUCCESS) {
                            cluster.addEvent("Terraform destroy successful.");
                        }

                        cluster.addEvent("Working directory cleanup started...");
                        this.fileService.cleanUpWorkingDirectory(workingDirectory);
                        cluster.addEvent("Working directory cleaned up.");

                        if (ansibleResult != AnsibleResult.SUCCESS || terraformResult != TerraformResult.SUCCESS) {
                            cluster.setStatus(Status.TERMINATION_FAILED);
                            return;
                        }

                        cluster.setStatus(Status.TERMINATED);
                    }
                }).start();
            }

            return Optional.of(cluster);
        }
    }

    /**
     * Reads the cluster info textfile from the working directory of the given cluster.
     * 
     * @param id ID of the cluster in whose working directory the file is located
     * @return content of the cluster-info textfile
     */
    public Optional<String> getClusterInformation(UUID id) {
        return this.getFileContent(id, "resources/cluster-info.txt");
    }

    /**
     * Reads the client access file from the working directory of the given cluster.
     * 
     * @param id ID of the cluster in whose working directory the file is located
     * @return content of the client access file
     */
    public Optional<String> getAccessFile(UUID id) {
        return this.getFileContent(id, "resources/access.yaml");
    }

    /**
     * Reads the logfile from the working directory of the given cluster.
     * 
     * @param id ID of the cluster in whose working directory the file is located
     * @return content of the logfile
     */
    public Optional<String> getLogs(UUID id) {
        return this.getFileContent(id, "cluster.log");
    }

    /**
     * Reads the content of a file in the working directory of a cluster.
     * 
     * @param id       ID of the cluster in whose working directory the file is located
     * @param filename relative filename in the working directory
     * @return file content, empty if not resolvable.
     */
    private Optional<String> getFileContent(UUID id, String filename) {
        Path file = this.fileService.workingDirectory(id).resolve(filename);
        try {
            return Optional.of(FileUtils.readFileToString(file.toFile(), StandardCharsets.UTF_8));
        } catch (IOException e) {
            LOGGER.warn("{file} could not be read.", e);
            return Optional.empty();
        }
    }
}
