package tech.stackable.t2.api.cluster.controller;

import java.util.Collection;
import java.util.Map;
import java.util.UUID;

import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.api.cluster.service.TerraformAnsibleClusterService;
import tech.stackable.t2.security.SecurityToken;
import tech.stackable.t2.security.TokenIncorrectException;
import tech.stackable.t2.security.TokenRequiredException;

@RestController
@RequestMapping("api/clusters")
public class ClusterController {

    private static final Logger LOGGER = LoggerFactory.getLogger(ClusterController.class);

    @Autowired
    private TerraformAnsibleClusterService clusterService;

    @Autowired
    private SecurityToken requiredToken;

    @GetMapping()
    @ResponseBody
    @Operation(summary = "Get all clusters", description = "Get list of all active clusters")
    public Collection<Cluster> getClusters(@RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        return clusterService.getAllClusters();
    }

    @GetMapping("{id}")
    @ResponseBody
    @Operation(summary = "Get cluster", description = "Gets the specified cluster")
    public Cluster getCluster(
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        Cluster cluster = clusterService.getCluster(id);
        if (cluster == null) {
            throw new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id));
        }
        return cluster;
    }

    @PostMapping(consumes = { "application/json", "application/yaml" })
    @ResponseBody
    @Operation(summary = "Creates a new cluster", description = "Creates a new cluster and starts it")
    public Cluster createCluster(
            @RequestHeader(name = "t2-token", required = false) String token,
            @RequestBody(required = true) String clusterDefinition) {

        checkToken(token);
        return clusterService.createCluster(clusterDefinition(clusterDefinition));
    }

    @DeleteMapping("{id}")
    @ResponseBody
    @Operation(summary = "Deletes a cluster", description = "Deletes the specified cluster")
    public Cluster deleteCluster(
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        Cluster cluster = clusterService.deleteCluster(id);
        if (cluster == null) {
            throw new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id));
        }
        return cluster;
    }

    @GetMapping("{id}/stackable-versions")
    @ResponseBody
    @Operation(summary = "read Stackable cluster information document", description = "Reads a text document which contains information about the cluster")
    public String getStackableVersions(
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        Cluster cluster = clusterService.getCluster(id);
        if (cluster == null) {
            throw new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id));
        }
        String stackableVersions = this.clusterService.getClusterInformation(id);
        if (stackableVersions == null) {
            throw new ClusterNotFoundException(String.format("No Stackable cluster information document found for cluster with id '%s'.", id));
        }
        return stackableVersions;
    }

    @GetMapping("{id}/access")
    @ResponseBody
    @Operation(summary = "read access file", description = "Reads the access file which contains information how to access the cluster.")
    public String getAccessFile(
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        Cluster cluster = clusterService.getCluster(id);
        if (cluster == null) {
            throw new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id));
        }
        String accessFile = this.clusterService.getAccessFile(id);
        if (accessFile == null) {
            throw new ClusterNotFoundException(String.format("No access file found for cluster with id '%s'.", id));
        }
        return accessFile;
    }

    @GetMapping("{id}/log")
    @ResponseBody
    @Operation(summary = "read logs", description = "Reads the logs for the given cluster")
    public String getLog (
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        Cluster cluster = clusterService.getCluster(id);
        if (cluster == null) {
            throw new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id));
        }
        return this.clusterService.getLogs(id);
    }

    /**
     * Checks if the given token is valid, throws appropriate exception otherwise
     * 
     * @param token token
     */
    private void checkToken(String token) {
        if (token == null) {
            throw new TokenRequiredException();
        }
        if (!this.requiredToken.isOk(token)) {
            throw new TokenIncorrectException();
        }
    }

    /**
     * Parses the given cluster definition and returns a map representing the
     * content.
     * 
     * @param clusterDefinition raw cluster definiton as provided by the request
     * @return cluster definition as map for further processing, <code>null</code>
     *         if no definition provided
     * @throws MalformedClusterDefinitionException if the cluster definition file is
     *                                             not valid
     */
    @SuppressWarnings("unchecked")
    private Map<String, Object> clusterDefinition(String clusterDefinition) {
        if (StringUtils.isBlank(clusterDefinition)) {
            return null;
        }

        Map<String, Object> clusterDefinitionMap = null;
        if (clusterDefinition != null) {
            try {
                clusterDefinitionMap = new ObjectMapper(new YAMLFactory()).readValue(clusterDefinition, Map.class);
            } catch (JsonProcessingException e) {
                LOGGER.warn("The cluster definition does not contain valid YAML/JSON.", e);
                throw new MalformedClusterDefinitionException("The cluster definition does not contain valid YAML/JSON.", e);
            }
        }
        
        if (!"t2.stackable.tech/v2".equals(clusterDefinitionMap.get("apiVersion"))) {
            throw new MalformedClusterDefinitionException("The apiVersion is either missing or not valid.");
        }

        if (!"StackableT2Cluster".equals(clusterDefinitionMap.get("kind"))) {
            throw new MalformedClusterDefinitionException("The kind of requested resource is either missing or not valid.");
        }

        return clusterDefinitionMap;
    }

}
