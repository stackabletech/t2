package tech.stackable.t2.ansible;

import java.io.IOException;
import java.nio.file.Path;
import java.text.MessageFormat;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

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

    public AnsibleResult launch(UUID clusterId) {
        return this.run(clusterId, "launch.yaml", "ansible-launch");
    }

    public AnsibleResult cleanup(UUID clusterId) {
        return this.run(clusterId, "cleanup.yaml", "ansible-cleanup");
    }

    /**
     * Runs the given playbook on the given cluster.
     * 
     * @param clusterId ID of the cluster on which the playbook should be run.
     * @param playbook  Ansible playbook
     * @return result of the Ansible run
     */
    private AnsibleResult run(UUID clusterId, String playbook, String loggingPrefix) {
        LOGGER.info("Running Ansible playbook {} for cluster {}", playbook, clusterId);

        Path workingDirectory = this.fileService.workingDirectory(clusterId);

        try {

            // Set up Ansible process to be run in the working dir of the cluster
            ProcessBuilder processBuilder = new ProcessBuilder()
                    .command("sh", "-c", MessageFormat.format("ansible-playbook {0}", playbook))
                    .directory(workingDirectory.toFile());

            // Start Ansible process (stderr redirected to stdout)
            Process process = processBuilder.redirectErrorStream(true).start();

            ProgressLogger logger = ProgressLogger.start(
                    process.getInputStream(),
                    workingDirectory.resolve("cluster.log"),
                    loggingPrefix);

            // Wait for termination of Ansible process
            int exitCode = process.waitFor();

            // Stop process logging
            logger.stop();

            return AnsibleResult.byExitCode(exitCode);
        } catch (IOException | InterruptedException e) {
            LOGGER.error("Error while calling Ansible", e);
            throw new RuntimeException("Error while calling Ansible", e);
        }
    }

}
