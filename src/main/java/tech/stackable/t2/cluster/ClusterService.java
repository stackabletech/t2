package tech.stackable.t2.cluster;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Repository;

import io.micrometer.core.instrument.Counter;
import tech.stackable.t2.ansible.AnsibleResult;
import tech.stackable.t2.ansible.AnsibleService;
import tech.stackable.t2.domain.Cluster;
import tech.stackable.t2.domain.Status;
import tech.stackable.t2.files.FileService;
import tech.stackable.t2.terraform.TerraformResult;
import tech.stackable.t2.terraform.TerraformService;

/**
 * Creation and Termination of clusters
 */
@Repository
public class ClusterService {

    private static final Logger LOGGER = LoggerFactory.getLogger(ClusterService.class);

    private static final Duration CLEANUP_INACTIVITY_THRESHOLD = Duration.ofDays(1);

    @Autowired
    private FileService fileService;

    @Autowired
    private TerraformService terraformService;

    @Autowired
    private AnsibleService ansibleService;

    @Autowired
    @Qualifier("clustersRequestedCounter")
    private Counter clustersRequestedCounter;

    @Autowired
    @Qualifier("clustersCreatedCounter")
    private Counter clustersCreatedCounter;

    @Autowired
    @Qualifier("clustersTerminatedCounter")
    private Counter clustersTerminatedCounter;

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
    public Collection<Cluster> getClusters() {
        return this.clusters.values();
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
     * Start the creation of a new cluster.
     * 
     * @param clusterDefinition definition of the new cluster
     * @return cluster metadata
     */
    public Cluster startClusterCreation(Map<String, Object> clusterDefinition) {
        synchronized (this.clusters) {

            Cluster cluster = new Cluster();
            cluster.setStatus(Status.CREATION_STARTED);
            this.clustersRequestedCounter.increment();

            Path workingDirectory = this.fileService.workingDirectory(cluster.getId());

            this.fileService.createWorkingDirectory(workingDirectory, clusterDefinition);
            cluster.setStatus(Status.WORKING_DIR_CREATED);
            clusters.put(cluster.getId(), cluster);

            // This thread must be started if the cluster launch fails after terraform apply
            // has started as there may be created resources
            // which have to be torn down...
            Thread tearDownOnFailure = new Thread(() -> {
                this.terraformService.destroy(cluster.getId());
                this.fileService.cleanUpWorkingDirectory(workingDirectory);
            });

            new Thread(() -> {

                TerraformResult terraformResult = null;

                cluster.setStatus(Status.TERRAFORM_INIT);
                terraformResult = this.terraformService.init(cluster.getId());
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_INIT_FAILED);
                    this.fileService.cleanUpWorkingDirectory(workingDirectory);
                    return;
                }

                cluster.setStatus(Status.TERRAFORM_PLAN);
                terraformResult = this.terraformService.plan(cluster.getId());
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_PLAN_FAILED);
                    this.fileService.cleanUpWorkingDirectory(workingDirectory);
                    return;
                }

                cluster.setStatus(Status.TERRAFORM_APPLY);
                terraformResult = this.terraformService.apply(cluster.getId());
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_APPLY_FAILED);
                    tearDownOnFailure.start();
                    return;
                }

                cluster.setStatus(Status.ANSIBLE_PROVISIONING);
                AnsibleResult ansibleResult = this.ansibleService.run(cluster.getId());
                if (ansibleResult == AnsibleResult.ERROR) {
                    cluster.setStatus(Status.ANSIBLE_FAILED);
                    tearDownOnFailure.start();
                    return;
                }

                cluster.setStatus(Status.RUNNING);
                this.clustersCreatedCounter.increment();

            }).start();

            return cluster;
        }
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
            cluster.setStatus(Status.DELETION_STARTED);

            new Thread(() -> {

                Path workingDirectory = this.fileService.workingDirectory(cluster.getId());

                cluster.setStatus(Status.TERRAFORM_DESTROY);
                TerraformResult terraformResult = this.terraformService.destroy(cluster.getId());
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_DESTROY_FAILED);
                    return;
                }
                this.fileService.cleanUpWorkingDirectory(workingDirectory);
                cluster.setStatus(Status.TERMINATED);
                this.clustersTerminatedCounter.increment();
            }).start();

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

    // TODO re-enable
//    @SuppressWarnings("unchecked")
//    public byte[] createDiyCluster(Map<String, Object> clusterDefinition) {
//        Path tempDirectory;
//        Path workingDirectory;
//        try {
//            tempDirectory = Files.createTempDirectory("t2-diy-");
//        } catch (IOException e) {
//            throw new RuntimeException("Internal error creating temp folder.", e);
//        }
//        if (clusterDefinition.containsKey("metadata") && clusterDefinition.get("metadata") instanceof Map
//                && ((Map<String, Object>) clusterDefinition.get("metadata")).containsKey("name")) {
//            try {
//                workingDirectory = Files.createDirectory(tempDirectory
//                        .resolve((String) ((Map<String, Object>) clusterDefinition.get("metadata")).get("name")));
//            } catch (IOException e) {
//                throw new RuntimeException("Internal error creating temp folder.", e);
//            }
//        } else {
//            workingDirectory = tempDirectory;
//        }
//        this.fileService.createWorkingDirectory(workingDirectory, clusterDefinition);
//        ByteArrayOutputStream bos = new ByteArrayOutputStream();
//        ZipUtil.pack(tempDirectory.toFile(), bos);
//        return bos.toByteArray();
//    }

    /**
     * Cleans up list of clusters on every hour.
     * 
     * This method removes all clusters from the in-memory data which are {@link #readyForCleanup(Cluster)}
     */
    @Scheduled(cron = "0 0 * * * *")
    private void cleanup() {
        LOGGER.info("cleaning up clusters ...");
        List<UUID> clustersToDelete = this.clusters.values()
                .stream()
                .filter(ClusterService::readyForCleanup)
                .map(Cluster::getId)
                .collect(Collectors.toList());

        LOGGER.info("Found {} clusters to be cleaned up.", clustersToDelete.size());

        synchronized (clusters) {
            clustersToDelete.forEach(id -> {
                LOGGER.info("Cluster {} will be cleaned up.", id);
                this.clusters.remove(id);
            });
        }

        LOGGER.info("cleaned up {} clusters.", clustersToDelete.size());
    }

    /**
     * Decides if a given Cluster is ready to be cleaned up.
     * 
     * We assume that clusters that are not in state {@link Status#RUNNING} and haven't changed their state for a day are
     * ready to be removed.
     * 
     * @param cluster cluster to check
     * @return Is the given cluster ready to be cleaned up?
     */
    private static boolean readyForCleanup(Cluster cluster) {
        return !(cluster.getStatus() == Status.RUNNING)
                && Duration.between(cluster.getLastChangedAt(), LocalDateTime.now())
                        .compareTo(CLEANUP_INACTIVITY_THRESHOLD) > 0;
    }
}
