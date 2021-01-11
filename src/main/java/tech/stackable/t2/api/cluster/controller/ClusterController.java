package tech.stackable.t2.api.cluster.controller;

import java.util.Collection;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.api.cluster.service.ClusterService;

/**
 * REST Controller to manage clusters.
 */
@RestController
@RequestMapping("api/clusters")
public class ClusterController {

  @Autowired
  private ClusterService clusterService;

  /**
   * Get list of all clusters
   * 
   * @return list of all clusters
   */
  @GetMapping()
  @ResponseBody
  public Collection<Cluster> getClusters() {
    return clusterService.getAllClusters();
  }

  /**
   * Get information for a single cluster
   * 
   * @param id
   * @return information for a single cluster
   */
  @GetMapping("{id}")
  @ResponseBody
  public Cluster getCluster(@PathVariable(name = "id", required = true) UUID id) {
    Cluster cluster = clusterService.getCluster(id);
    if (cluster == null) {
      throw new ClusterNotFoundException(String.format("No cluster found with id '%s'.", id));
    }
    return cluster;
  }

  /**
   * Create a new cluster
   * 
   * @return information for the cluster
   */
  @PostMapping()
  @ResponseBody
  public Cluster createCluster() {
    return clusterService.createCluster();
  }

  /**
   * Delete a cluster
   * 
   * @param id
   */
  @DeleteMapping("{id}")
  @ResponseBody
  public void deleteCluster(@PathVariable(name = "id", required = true) UUID id) {
    clusterService.deleteCluster(id);
  }

}
