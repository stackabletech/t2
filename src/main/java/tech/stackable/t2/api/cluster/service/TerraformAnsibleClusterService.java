package tech.stackable.t2.api.cluster.service;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.MessageFormat;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Properties;
import java.util.UUID;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Repository;
import org.zeroturnaround.zip.ZipUtil;

import tech.stackable.t2.ansible.AnsibleResult;
import tech.stackable.t2.ansible.AnsibleService;
import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.api.cluster.domain.Status;
import tech.stackable.t2.dns.DnsService;
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
    @Qualifier("credentials")
    private Properties credentials;

    @Autowired
    private Optional<DnsService> dnsService;

    @Autowired
    private TemplateService templateService;

    @Autowired
    private TerraformService terraformService;

    @Autowired
    private AnsibleService ansibleService;

    private int provisionClusterLimit = -1;

    /**
     * cluster metadata per cluster (UUID)
     */
    private Map<UUID, Cluster> clusters = new HashMap<>();

    public TerraformAnsibleClusterService(@Value("${t2.cluster-count-limit}") int provisionClusterLimit) {
        this.provisionClusterLimit = provisionClusterLimit;
        LOGGER.info("Created TerraformAnsibleClusterService, cluster count limit: {}", this.provisionClusterLimit);
    }

    public Collection<Cluster> getAllClusters() {
        return this.clusters.values();
    }

    public Cluster getCluster(UUID id) {
        return this.clusters.get(id);
    }

    public Cluster createCluster(Map<String, Object> clusterDefinition) {
        synchronized (this.clusters) {

            if (isClusterLimitReached()) {
                throw new ClusterLimitReachedException();
            }
            
            Cluster cluster = new Cluster();
            cluster.setStatus(Status.CREATION_STARTED);

            Path workingDirectory = this.templateService.createWorkingDirectory(workspaceDirectory.resolve(cluster.getId().toString()), clusterDefinition);
            cluster.setStatus(Status.WORKING_DIR_CREATED);
            clusters.put(cluster.getId(), cluster);
            
            // This thread must be started if the cluster launch fails after terraform apply has started as there may be created resources
            // which have to be torn down...
            Thread tearDownOnFailure = new Thread(() -> {
                if(this.dnsService.isPresent() && StringUtils.isNotEmpty(cluster.getHostname())) {
                    this.dnsService.get().removeSubdomain(cluster.getShortId());
                }
                this.terraformService.destroy(workingDirectory, clusterName(cluster));
            });
            
            new Thread(() -> {

                TerraformResult terraformResult = null;

                cluster.setStatus(Status.TERRAFORM_INIT);
                terraformResult = this.terraformService.init(workingDirectory, clusterName(cluster));
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_INIT_FAILED);
                    return;
                }

                cluster.setStatus(Status.TERRAFORM_PLAN);
                terraformResult = this.terraformService.plan(workingDirectory, clusterName(cluster));
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_PLAN_FAILED);
                    return;
                }

                cluster.setStatus(Status.TERRAFORM_APPLY);
                terraformResult = this.terraformService.apply(workingDirectory, clusterName(cluster));
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_APPLY_FAILED);
                    tearDownOnFailure.start();
                    return;
                }

                if(1==1)return;
                
                cluster.setIpV4Address(this.terraformService.getIpV4(workingDirectory));

                if(this.dnsService.isPresent()) {
                    cluster.setStatus(Status.DNS_WRITE_RECORD);
                    String hostname = this.dnsService.get().addSubdomain(cluster.getShortId(), cluster.getIpV4Address());
                    if (hostname == null) {
                        cluster.setStatus(Status.DNS_WRITE_RECORD_FAILED);
                        tearDownOnFailure.start();
                        return;
                    }
                    
                    cluster.setHostname(hostname);
                }

                cluster.setStatus(Status.ANSIBLE_PROVISIONING);
                
                AnsibleResult ansibleResult = this.ansibleService.run(workingDirectory);
                if (ansibleResult == AnsibleResult.ERROR) {
                    cluster.setStatus(Status.ANSIBLE_FAILED);
                    tearDownOnFailure.start();
                    return;
                }

                cluster.setStatus(Status.RUNNING);

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

                if(this.dnsService.isPresent()) {
                    cluster.setStatus(Status.DNS_DELETE_RECORD);
                    boolean dnsRemovalSucceded = this.dnsService.get().removeSubdomain(cluster.getShortId());
                    if (!dnsRemovalSucceded) {
                        cluster.setStatus(Status.DNS_DELETE_RECORD_FAILED);
                        return;
                    }
                }

                Path terraformFolder = workspaceDirectory.resolve(cluster.getId().toString());

                cluster.setStatus(Status.TERRAFORM_DESTROY);
                TerraformResult terraformResult = this.terraformService.destroy(terraformFolder, clusterName(cluster));
                if (terraformResult == TerraformResult.ERROR) {
                    cluster.setStatus(Status.TERRAFORM_DESTROY_FAILED);
                    return;
                }
                cluster.setIpV4Address(null);
                cluster.setStatus(Status.TERMINATED);
            }).start();

            return cluster;
        }
    }

    public String getWireguardClientConfig(UUID id, int index) {
        Cluster cluster = this.clusters.get(id);
        if (cluster == null) {
            return null;
        }
        Path clusterBaseFolder = workspaceDirectory.resolve(cluster.getId().toString());
        try {
            return FileUtils.readFileToString(clusterBaseFolder.resolve(MessageFormat.format("resources/wireguard-client-config/{0}/wg.conf", index)).toFile(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            LOGGER.warn("Wireguard client config could not be read", e);
            return null;
        }
    }

    public String getClientScript(UUID id) {
        Cluster cluster = this.clusters.get(id);
        if (cluster == null) {
            return null;
        }
        Path clusterBaseFolder = workspaceDirectory.resolve(cluster.getId().toString());
        try {
            return FileUtils.readFileToString(clusterBaseFolder.resolve("resources/stackable.sh").toFile(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            LOGGER.warn("Stackable client script could not be read", e);
            return null;
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

    public String getKubeconfigFile(UUID id) {
        Cluster cluster = this.clusters.get(id);
        if (cluster == null) {
            return null;
        }
        Path clusterBaseFolder = workspaceDirectory.resolve(cluster.getId().toString());
        try {
            return FileUtils.readFileToString(clusterBaseFolder.resolve("resources/kubeconfig").toFile(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            LOGGER.warn("Kubeconfig could not be read", e);
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
            LOGGER.warn("Wireguard client config could not be read", e);
            return "";
        }
    }
    
    public byte[] createDiyCluster(Map<String, Object> clusterDefinition) {
        Path workingDirectory;
        try {
            workingDirectory = Files.createTempDirectory("t2-diy-");
        } catch (IOException e) {
            throw new RuntimeException("Internal error creating temp folder.", e);
        }
        this.templateService.createWorkingDirectory(workingDirectory, clusterDefinition);
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        ZipUtil.pack(workingDirectory.toFile(), bos);
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

    /**
     * Did we reach the max number of clusters?
     * @return Did we reach the max number of clusters?
     */
    private boolean isClusterLimitReached() {
        long nonTerminatedClusterCount = this.clusters.values().stream().filter(c -> c.getStatus()!=Status.TERMINATED).count();
        return nonTerminatedClusterCount >= this.provisionClusterLimit;
    }
    
    /**
     * Name of the given cluster in the cloud provider.
     * 
     * This name is used as 'datacenter name', 'vpc id' or the like.
     * 
     * @param clusterId Cluster ID
     * @return cluster name for the given cluster
     */
    private String clusterName(Cluster cluster) {
        return String.format("t2-%s", cluster.getShortId());
    }

}
