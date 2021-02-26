package tech.stackable.t2.api.cluster.controller;

import java.util.Base64;
import java.util.Collection;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.api.cluster.service.ClusterService;
import tech.stackable.t2.security.SecurityToken;
import tech.stackable.t2.security.TokenIncorrectException;
import tech.stackable.t2.security.TokenRequiredException;

@RestController
@RequestMapping("api/clusters")
public class ClusterController {

  @Autowired
  private ClusterService clusterService;

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

  @PostMapping()
  @ResponseBody
  @Operation(summary = "Creates a new cluster", description = "Creates a new cluster and starts it")
  public Cluster createCluster(
      @RequestHeader(name = "t2-token", required = false) String token,
      @RequestHeader(name = "t2-ssh-key", required = true) String sshKey) {
    checkToken(token);
    return clusterService.createCluster(new String(Base64.getDecoder().decode(sshKey)).trim());
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
  
  @GetMapping("{id}/wireguard-config/{index}")
  @ResponseBody
  @Operation(summary = "Get cluster", description = "Gets the wireguard client config with the specified index")
  public String getWireguardConfig(
      @Parameter(name = "id", description = "ID (UUID) of the cluster") @PathVariable(name = "id", required = true) UUID id,
      @Parameter(name = "index", description = "index of the wireguard client config") @PathVariable(name = "index", required = true) int index,
      @RequestHeader(name = "t2-token", required = false) String token) {
    checkToken(token);
    Cluster cluster = clusterService.getCluster(id);
    if (cluster == null) {
      throw new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id));
    }
    String wireguardClientConfig = this.clusterService.getWireguardClientConfig(id, index);
    if(wireguardClientConfig==null) {
      throw new ClusterNotFoundException(String.format("No wireguard config[%d] found for cluster with id '%s'.", index, id));
    }
    return wireguardClientConfig;
  }

  /**
   * Checks if the given token is valid, throws appropriate exception otherwise
   * @param token token
   */
  private void checkToken(String token) {
    if(token==null) {
      throw new TokenRequiredException();
    }
    if(!this.requiredToken.isOk(token)) {
      throw new TokenIncorrectException();
    }
  }

}
