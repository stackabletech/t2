package tech.stackable.t2.ansible;

import java.io.IOException;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import tech.stackable.t2.process.ProcessLogger;

@Service
public class AnsibleService {

    private static final Logger LOGGER = LoggerFactory.getLogger(AnsibleService.class);

    @Autowired
    @Qualifier("workspaceDirectory")
    private Path workspaceDirectory;
    
    private final Set<Process> runningProcesses = new HashSet<Process>();
    
    private final Counter ansibleProcessesStarted;
    
    private final Counter ansibleProcessesCompleted;

    public AnsibleService(MeterRegistry meterRegistry) {
    	meterRegistry.gauge("ANSIBLE_PROCESSES_RUNNING", this.runningProcesses, Set::size);
    	this.ansibleProcessesStarted = meterRegistry.counter("ANSIBLE_PROCESSES_STARTED");
    	this.ansibleProcessesCompleted = meterRegistry.counter("ANSIBLE_PROCESSES_COMPLETED");
	}

	public AnsibleResult run(Path workingDirectory) {
        LOGGER.info("Running Ansible on {}", workingDirectory);
        int result = this.callAnsible(workingDirectory);
        return result == 0 ? AnsibleResult.SUCCESS : AnsibleResult.ERROR;
    }

    private int callAnsible(Path workingDirectory) {
        try {
            ProcessBuilder processBuilder = new ProcessBuilder()
                    .command("sh", "-c", "ansible-playbook launch.yml")
                    .directory(workingDirectory.toFile());
            Process process = processBuilder.redirectErrorStream(true).start();
            this.runningProcesses.add(process);
            this.ansibleProcessesStarted.increment();
            ProcessLogger outLogger = ProcessLogger.start(process.getInputStream(), workingDirectory.resolve("cluster.log"), "ansible");
            int exitCode = process.waitFor();
            this.runningProcesses.remove(process);
            this.ansibleProcessesCompleted.increment();
            outLogger.stop();
            return exitCode;
        } catch (IOException | InterruptedException e) {
            LOGGER.error("Error while calling Ansible", e);
            throw new RuntimeException("Error while calling Ansible", e);
        }
    }

}
