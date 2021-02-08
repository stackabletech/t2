package tech.stackable.t2.api.cluster.domain;

import com.fasterxml.jackson.annotation.JsonFormat;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * Status of a cluster
 */
@Schema(description = "Status of a Cluster")
@JsonFormat(shape = JsonFormat.Shape.OBJECT)
public enum Status {
  
  NEW,
  CREATION_STARTED,
  TERRAFORM_INIT,
  TERRAFORM_INIT_FAILED(true),
  TERRAFORM_PLAN,
  TERRAFORM_PLAN_FAILED(true),
  TERRAFORM_APPLY,
  TERRAFORM_APPLY_FAILED(true),
  TERRAFORM_DESTROY,
  TERRAFORM_DESTROY_FAILED(true),
  ANSIBLE_PROVISIONING,
  ANSIBLE_FAILED(true),
  RUNNING,
  DELETION_STARTED,
  TERMINATED;
  
  private boolean failed = false;

  private Status() {
  }
  
  private Status(boolean failed) {
    this.failed = failed;
  }

  public boolean isFailed() {
    return failed;
  }
  
  public String getState() {
    return name();
  }
}
