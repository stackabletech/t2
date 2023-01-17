package tech.stackable.t2.api.cluster.service;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Repository;
import org.zeroturnaround.zip.ZipUtil;

import io.micrometer.core.instrument.Counter;
import tech.stackable.t2.ansible.AnsibleResult;
import tech.stackable.t2.ansible.AnsibleService;
import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.api.cluster.domain.Status;
import tech.stackable.t2.templates.TemplateService;
import tech.stackable.t2.terraform.TerraformResult;
import tech.stackable.t2.terraform.TerraformService;

/**
 * Manages clusters provisioned with Terraform and Ansible
 */
@Repository
public class TerraformAnsibleClusterService {

    private static final Logger LOGGER = LoggerFactory.getLogger(TerraformAnsibleClusterService.class);

    private static final Duration CLEANUP_INACTIVITY_THRESHOLD = Duration.ofDays(1);

    @Autowired
    @Qualifier("workspaceDirectory")
    private Path workspaceDirectory;

    @Autowired
    private TemplateService templateService;

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
     * cluster metadata per cluster (UUID)
     */
    private Map<UUID, Cluster> clusters = new HashMap<>();

    public TerraformAnsibleClusterService() {
        LOGGER.info("Created TerraformAnsibleClusterService");
    }

    public Collection<Cluster> getAllClusters() {
        return this.clusters.values();
    }

    public Cluster getCluster(UUID id) {
        return this.clusters.get(id);
    }

    public Cluster createCluster(Map<String, Object> clusterDefinition) {
        synchronized (this.clusters) {

            Cluster cluster = new Cluster();
            cluster.setStatus(Status.CREATION_STARTED);
            this.clustersRequestedCounter.increment();

            Path workingDirectory = this.templateService.createWorkingDirectory(workspaceDirectory.resolve(cluster.getId().toString()), clusterDefinition);
            cluster.setStatus(Status.WORKING_DIR_CREATED);
            clusters.put(cluster.getId(), cluster);
            
            // This thread must be started if the cluster launch fails after terraform apply has started as there may be created resources
            // which have to be torn down...
            Thread tearDownOnFailure = new Thread(() -> {
                this.terraformService.destroy(workingDirectory, cluster.getId());
                this.templateService.cleanUpWorkingDirectory(workspaceDirectory.resolve(cluster.getId().toString()));
            });
            
            new Thread(() -> {

                TerraformResult terraformResult = null;

                cluster.setStatus(Status.TERRAFORM_INIT);
                terraformResult = this.terraformService.init(workingDirectory, cluster.getId());
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_INIT_FAILED);
                    return;
                }

                cluster.setStatus(Status.TERRAFORM_PLAN);
                terraformResult = this.terraformService.plan(workingDirectory, cluster.getId());
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_PLAN_FAILED);
                    return;
                }

                cluster.setStatus(Status.TERRAFORM_APPLY);
                terraformResult = this.terraformService.apply(workingDirectory, cluster.getId());
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_APPLY_FAILED);
                    tearDownOnFailure.start();
                    return;
                }

                cluster.setStatus(Status.ANSIBLE_PROVISIONING);
                
                AnsibleResult ansibleResult = this.ansibleService.run(workingDirectory);
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

    public Cluster deleteCluster(UUID id) {
        synchronized (this.clusters) {
            Cluster cluster = this.clusters.get(id);
            if (cluster == null) {
                return null;
            }
            cluster.setStatus(Status.DELETION_STARTED);

            new Thread(() -> {

                Path terraformFolder = workspaceDirectory.resolve(cluster.getId().toString());

                cluster.setStatus(Status.TERRAFORM_DESTROY);
                TerraformResult terraformResult = this.terraformService.destroy(terraformFolder, cluster.getId());
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_DESTROY_FAILED);
                    return;
                }
                this.templateService.cleanUpWorkingDirectory(workspaceDirectory.resolve(cluster.getId().toString()));
                cluster.setStatus(Status.TERMINATED);
                this.clustersTerminatedCounter.increment();
            }).start();

            return cluster;
        }
    }

    public String getVersionInformation(UUID id) {
        Cluster cluster = this.clusters.get(id);
        if (cluster == null) {
            return null;
        }
        Path clusterBaseFolder = workspaceDirectory.resolve(cluster.getId().toString());
        try {
            return FileUtils.readFileToString(clusterBaseFolder.resolve("resources/stackable-versions.txt").toFile(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            LOGGER.warn("Stackable version information document could not be read", e);
            return null;
        }
    }

    public String getAccessFile(UUID id) {
        Cluster cluster = this.clusters.get(id);
        if (cluster == null) {
            return null;
        }
        Path clusterBaseFolder = workspaceDirectory.resolve(cluster.getId().toString());
        try {
            return FileUtils.readFileToString(clusterBaseFolder.resolve("resources/access.yaml").toFile(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            LOGGER.warn("access file could not be read", e);
            return null;
        }
    }

    public String getLogs(UUID id) {
        Cluster cluster = this.clusters.get(id);
        if (cluster == null) {
            return "";
        }
        Path clusterBaseFolder = workspaceDirectory.resolve(cluster.getId().toString());
        try {
            return FileUtils.readFileToString(clusterBaseFolder.resolve("cluster.log").toFile(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            LOGGER.warn("logs could not be read", e);
            return "";
        }
    }
    
    @SuppressWarnings("unchecked")
    public byte[] createDiyCluster(Map<String, Object> clusterDefinition) {
        Path tempDirectory;
        Path workingDirectory;
        try {
            tempDirectory = Files.createTempDirectory("t2-diy-");
        } catch (IOException e) {
            throw new RuntimeException("Internal error creating temp folder.", e);
        }
        if(clusterDefinition.containsKey("metadata") && clusterDefinition.get("metadata") instanceof Map && ((Map<String,Object>)clusterDefinition.get("metadata")).containsKey("name")) {
            try {
                workingDirectory = Files.createDirectory(tempDirectory.resolve((String)((Map<String,Object>)clusterDefinition.get("metadata")).get("name")));
            } catch (IOException e) {
                throw new RuntimeException("Internal error creating temp folder.", e);
            }
        } else {
            workingDirectory = tempDirectory;
        }
        this.templateService.createWorkingDirectory(workingDirectory, clusterDefinition);
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        ZipUtil.pack(tempDirectory.toFile(), bos);
        return bos.toByteArray();
    }
    
    /**
     * Cleans up list of clusters regularly.
     */
    @Scheduled(cron = "0 0 * * * *") // on the hour
    private void cleanup() {
        LOGGER.info("cleaning up clusters ...");
        List<UUID> clustersToDelete = this.clusters.values()
                .stream()
                .filter(TerraformAnsibleClusterService::readyForCleanup)
                .map(Cluster::getId)
                .collect(Collectors.toList());

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
     * We assume that clusters that are not in state {@link Status#RUNNING} and
     * haven't changed their state for a day are ready to be removed.
     * 
     * @param cluster cluster to check
     * @return Is the given cluster ready to be cleaned up?
     */
    private static boolean readyForCleanup(Cluster cluster) {
        return !(cluster.getStatus() == Status.RUNNING)
                && Duration.between(cluster.getLastChangedAt(), LocalDateTime.now()).compareTo(CLEANUP_INACTIVITY_THRESHOLD) > 0;
    }

}
