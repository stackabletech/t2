package tech.stackable.t2.terraform;

import java.io.IOException;
import java.nio.file.Path;
import java.text.MessageFormat;
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
 * This service wraps Hashicorp Terraform commands.
 */
@Service
public class TerraformService {

    private static final Logger LOGGER = LoggerFactory.getLogger(TerraformService.class);

    @Autowired
    private FileService fileService;

    /**
     * In-memory storage of all running Terraform processes.
     */
    private final Set<Process> runningProcesses = new HashSet<Process>();

    private final Counter terraformProcessesStarted;
    private final Counter terraformProcessesCompleted;

    public TerraformService(MeterRegistry meterRegistry) {
        meterRegistry.gauge("TERRAFORM_PROCESSES_RUNNING", this.runningProcesses, Set::size);
        this.terraformProcessesStarted = meterRegistry.counter("TERRAFORM_PROCESSES_STARTED");
        this.terraformProcessesCompleted = meterRegistry.counter("TERRAFORM_PROCESSES_COMPLETED");
    }

    /**
     * Run <code>terraform init</code> in the given directory.
     * 
     * @param clusterId Cluster for which the Terraform command should be executed.
     * @return result of the Terraform command.
     */
    public TerraformResult init(UUID clusterId) {
        return TerraformResult.byExitCode(this.callTerraform(clusterId, TerraformCommand.INIT));
    }

    /**
     * Run <code>terraform plan</code> in the given directory.
     * 
     * @param clusterId Cluster for which the Terraform command should be executed.
     * @return result of the Terraform command.
     */
    public TerraformResult plan(UUID clusterId) {
        return TerraformResult.byExitCode(this.callTerraform(clusterId, TerraformCommand.PLAN));
    }

    /**
     * Run <code>terraform apply</code> in the given directory.
     * 
     * @param clusterId Cluster for which the Terraform command should be executed.
     * @return result of the Terraform command.
     */
    public TerraformResult apply(UUID clusterId) {
        return TerraformResult.byExitCode(this.callTerraform(clusterId, TerraformCommand.APPLY));
    }

    /**
     * Run <code>terraform destroy</code> in the given directory.
     * 
     * @param clusterId Cluster for which the Terraform command should be executed.
     * @return result of the Terraform command.
     */
    public TerraformResult destroy(UUID clusterId) {
        return TerraformResult.byExitCode(this.callTerraform(clusterId, TerraformCommand.DESTROY));
    }

    /**
     * Calls Hashicorp Terraform.
     * 
     * @param clusterId Cluster for which the Terraform command should be executed.
     * @param command   Terraform command to be called.
     * @param params    optional commands to be appended to the call.
     * @return exit code of the process
     */
    private int callTerraform(UUID clusterId, TerraformCommand command) {
        LOGGER.info("Running Terraform {} for cluster {} ...", command, clusterId);

        Path workingDirectory = this.fileService.workingDirectory(clusterId);

        try {

            // Set up Terraform process to be run in the working dir of the cluster
            ProcessBuilder processBuilder = new ProcessBuilder()
                    .command("sh", "-c", command.toString())
                    .directory(workingDirectory.toFile());

            // Provide cluster ID as Terraform variable
            processBuilder.environment().put("TF_VAR_cluster_id", clusterId.toString());

            // Start Terraform process (stderr redirected to stdout)
            Process process = processBuilder.redirectErrorStream(true).start();
            this.runningProcesses.add(process);
            this.terraformProcessesStarted.increment();

            // Set up process logging
            ProgressLogger logger = ProgressLogger.start(
                    process.getInputStream(),
                    workingDirectory.resolve("cluster.log"),
                    MessageFormat.format("terraform-{0}", command));

            // Wait for termination of Terraform process
            int exitCode = process.waitFor();

            this.runningProcesses.remove(process);
            this.terraformProcessesCompleted.increment();

            // Stop process logging
            logger.stop();

            return exitCode;

        } catch (IOException | InterruptedException e) {
            LOGGER.error("Error while calling terraform", e);
            throw new RuntimeException("Error while calling terraform", e);
        }
    }
}

/**
 * Terraform command
 */
enum TerraformCommand {

    INIT("terraform init -input=false -no-color"),
    PLAN("terraform plan -detailed-exitcode -input=false -no-color"),
    APPLY("terraform apply -auto-approve -input=false -no-color"),
    DESTROY("terraform destroy -auto-approve -no-color");

    private String command;

    private TerraformCommand(String command) {
        this.command = command;
    }

    @Override
    public String toString() {
        return command;
    }
}
