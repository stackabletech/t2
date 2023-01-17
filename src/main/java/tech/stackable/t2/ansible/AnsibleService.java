package tech.stackable.t2.ansible;

import java.io.IOException;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import tech.stackable.t2.files.FileService;
import tech.stackable.t2.util.ProgressLogger;

/**
 * This service wraps Ansible commands.
 */
@Service
public class AnsibleService {

    private static final Logger LOGGER = LoggerFactory.getLogger(AnsibleService.class);

    @Autowired
    private FileService fileService;

    /**
     * In-memory storage of all running Ansible processes.
     */
    private final Set<Process> runningProcesses = new HashSet<Process>();

    private final Counter ansibleProcessesStarted;
    private final Counter ansibleProcessesCompleted;

    public AnsibleService(MeterRegistry meterRegistry) {
        meterRegistry.gauge("ANSIBLE_PROCESSES_RUNNING", this.runningProcesses, Set::size);
        this.ansibleProcessesStarted = meterRegistry.counter("ANSIBLE_PROCESSES_STARTED");
        this.ansibleProcessesCompleted = meterRegistry.counter("ANSIBLE_PROCESSES_COMPLETED");
    }

    public AnsibleResult run(UUID clusterId) {
        LOGGER.info("Running Ansible for cluster {}", clusterId);

        Path workingDirectory = this.fileService.workingDirectory(clusterId);

        try {

            // Set up Ansible process to be run in the working dir of the cluster
            ProcessBuilder processBuilder = new ProcessBuilder()
                    .command("sh", "-c", "ansible-playbook launch.yml")
                    .directory(workingDirectory.toFile());

            // Start Ansible process (stderr redirected to stdout)
            Process process = processBuilder.redirectErrorStream(true).start();
            this.runningProcesses.add(process);
            this.ansibleProcessesStarted.increment();

            ProgressLogger logger = ProgressLogger.start(
                    process.getInputStream(),
                    workingDirectory.resolve("cluster.log"),
                    "ansible");

            // Wait for termination of Ansible process
            int exitCode = process.waitFor();

            this.runningProcesses.remove(process);
            this.ansibleProcessesCompleted.increment();

            // Stop process logging
            logger.stop();

            return AnsibleResult.byExitCode(exitCode);
        } catch (IOException | InterruptedException e) {
            LOGGER.error("Error while calling Ansible", e);
            throw new RuntimeException("Error while calling Ansible", e);
        }
    }

}
