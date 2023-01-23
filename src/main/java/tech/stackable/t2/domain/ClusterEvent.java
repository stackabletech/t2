package tech.stackable.t2.domain;

import java.time.Duration;
import java.time.LocalDateTime;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(description = "Event (status change) in cluster's history")
public class ClusterEvent {

    @Schema(description = "Timestamp of status change", required = true)
    private LocalDateTime timestamp;

    @Schema(description = "Time that has expired since cluster launch", required = true)
    private Duration timeSinceClusterLaunch;

    @Schema(description = "description", required = true)
    private String description;

    public ClusterEvent(String description, LocalDateTime clusterLaunchTimestamp) {
        this.timestamp = LocalDateTime.now();
        this.timeSinceClusterLaunch = Duration.between(clusterLaunchTimestamp, this.timestamp);
        this.description = description;
    }

    public LocalDateTime getTimestamp() {
        return timestamp;
    }

    public String getDescription() {
        return description;
    }

    public Duration getTimeSinceClusterLaunch() {
        return timeSinceClusterLaunch;
    }
}
