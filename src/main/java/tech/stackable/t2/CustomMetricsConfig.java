package tech.stackable.t2;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

/**
 * Spring Boot configuration for metrics.
 */
@Configuration
public class CustomMetricsConfig {

    @Bean(name = "clustersCreatedCounter")
    public Counter clustersCreatedCounter(MeterRegistry meterRegistry) {
        return meterRegistry.counter("CLUSTERS_CREATED");
    }

    @Bean(name = "clustersRequestedCounter")
    public Counter clustersRequestedCounter(MeterRegistry meterRegistry) {
        return meterRegistry.counter("CLUSTERS_REQUESTED");
    }

    @Bean(name = "clustersTerminatedCounter")
    public Counter clustersTerminatedCounter(MeterRegistry meterRegistry) {
        return meterRegistry.counter("CLUSTERS_TERMINATED");
    }
}
