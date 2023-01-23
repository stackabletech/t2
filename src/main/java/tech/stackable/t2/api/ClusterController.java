package tech.stackable.t2.api;

import java.text.MessageFormat;
import java.util.Collection;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import tech.stackable.t2.cluster.ClusterService;
import tech.stackable.t2.domain.Cluster;
import tech.stackable.t2.domain.Status;
import tech.stackable.t2.security.SecurityToken;
import tech.stackable.t2.security.TokenIncorrectException;
import tech.stackable.t2.security.TokenRequiredException;

@RestController
@RequestMapping("api/clusters")
public class ClusterController {

    private static final String API_VERSION = "t2.stackable.tech/v2";
    private static final String K8S_RESOURCE_NAME = "StackableT2Cluster";

    private static final Logger LOGGER = LoggerFactory.getLogger(ClusterController.class);

    @Autowired
    private ClusterService clusterService;

    @Autowired
    private SecurityToken token;

    @GetMapping()
    @ResponseBody
    @Operation(summary = "Get clusters", description = "Get list of clusters")
    public Collection<Cluster> getClusters(@RequestHeader(name = "t2-token", required = false) String token, @RequestParam(name = "status", required = false) Set<Status> statusFilter) {
        checkToken(token);
        return clusterService.getClusters(statusFilter);
    }

    @GetMapping("{id}")
    @ResponseBody
    @Operation(summary = "Get cluster", description = "Gets the specified cluster")
    public Cluster getCluster(
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        return clusterService.getCluster(id).orElseThrow(() -> new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id)));
    }

    @PostMapping(consumes = { "application/json", "application/yaml" })
    @ResponseBody
    @Operation(summary = "Creates a new cluster", description = "Creates a new cluster and starts it")
    public Cluster createCluster(
            @RequestHeader(name = "t2-token", required = false) String token,
            @RequestBody(required = true) String clusterDefinition) {

        checkToken(token);
        return clusterService.startClusterCreation(clusterDefinition(clusterDefinition));
    }

    @DeleteMapping("{id}")
    @ResponseBody
    @Operation(summary = "Deletes a cluster", description = "Deletes the specified cluster")
    public Cluster deleteCluster(
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        return clusterService.startClusterDeletion(id).orElseThrow(() -> new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id)));
    }

    @PutMapping("{id}")
    @ResponseBody
    @Operation(summary = "Set cluster status", description = "Sets the status on the specified cluster")
    public Cluster setClusterStatus(
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @Parameter(name = "status", description = "new status of the cluster") @RequestParam(name = "status", required = true) Status status,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        return clusterService.setClusterStatus(id, status);
    }

    @GetMapping("{id}/stackable-versions")
    @ResponseBody
    @Operation(summary = "read Stackable cluster information document", description = "Reads a text document which contains information about the cluster")
    public String getStackableVersions(
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        if (clusterService.getCluster(id).isEmpty()) {
            throw new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id));
        }
        return this.clusterService.getClusterInformation(id)
                .orElseThrow(() -> new ClusterNotFoundException(String.format("No Stackable cluster information document found for cluster with id '%s'.", id)));
    }

    @GetMapping("{id}/access")
    @ResponseBody
    @Operation(summary = "read access file", description = "Reads the access file which contains information how to access the cluster.")
    public String getAccessFile(
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        if (clusterService.getCluster(id).isEmpty()) {
            throw new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id));
        }
        return this.clusterService.getAccessFile(id)
                .orElseThrow(() -> new ClusterNotFoundException(String.format("No client access file found for cluster with id '%s'.", id)));
    }

    @GetMapping("{id}/log")
    @ResponseBody
    @Operation(summary = "read logs", description = "Reads the logs for the given cluster")
    public String getLog(
            @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
            @RequestHeader(name = "t2-token", required = false) String token) {
        checkToken(token);
        if (clusterService.getCluster(id).isEmpty()) {
            throw new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id));
        }
        return this.clusterService.getAccessFile(id).orElse("");
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
        if (!this.token.isOk(token)) {
            throw new TokenIncorrectException();
        }
    }

    /**
     * Parses the given cluster definition and returns a map representing the content.
     * 
     * @param clusterDefinition raw cluster definiton as provided by the request
     * @return cluster definition as map for further processing, <code>null</code> if no definition provided
     * @throws MalformedClusterDefinitionException if the cluster definition file is not valid
     */
    @SuppressWarnings("unchecked")
    private Map<String, Object> clusterDefinition(String clusterDefinition) {
        if (StringUtils.isBlank(clusterDefinition)) {
            return null;
        }

        Map<String, Object> result = null;
        try {
            result = new ObjectMapper(new YAMLFactory()).readValue(clusterDefinition, Map.class);
        } catch (JsonProcessingException e) {
            LOGGER.warn("The cluster definition does not contain valid YAML/JSON.", e);
            throw new MalformedClusterDefinitionException("The cluster definition does not contain valid YAML/JSON.", e);
        }

        if (!API_VERSION.equals(result.get("apiVersion"))) {
            throw new MalformedClusterDefinitionException(MessageFormat.format("The apiVersion must be '{0}'.", API_VERSION));
        }

        if (!K8S_RESOURCE_NAME.equals(result.get("kind"))) {
            throw new MalformedClusterDefinitionException(MessageFormat.format("The kind of requested resource must be '{0}'.", K8S_RESOURCE_NAME));
        }

        return result;
    }

}
