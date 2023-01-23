package tech.stackable.t2.domain;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(description = "Status of a cluster")
public enum Status {

    NEW,
    LAUNCHING,
    LAUNCH_FAILED,
    RUNNING,
    TERMINATING,
    TERMINATION_FAILED,
    TERMINATED,
    TERMINATED_MANUALLY;
}
