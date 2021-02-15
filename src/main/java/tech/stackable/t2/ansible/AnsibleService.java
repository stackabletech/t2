package tech.stackable.t2.ansible;

import java.io.IOException;
import java.nio.file.Path;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import tech.stackable.t2.process.ProcessLogger;

@Service
public class AnsibleService {

  private static final Logger LOGGER = LoggerFactory.getLogger(AnsibleService.class);  

  @Autowired
  @Qualifier("workspaceDirectory")
  private Path workspaceDirectory;
  
  public AnsibleResult run(Path workingDirectory) {
    LOGGER.info("Running Ansible on {}", workingDirectory);
    int result = this.callAnsible(workingDirectory);
    return result==0 ? AnsibleResult.SUCCESS : AnsibleResult.ERROR;
  }
  
  private int callAnsible(Path ansibleFolder) {
    try {
        ProcessBuilder processBuilder = new ProcessBuilder()
            .command("sh", "-c", "ansible-playbook playbook.yml")
            .directory(ansibleFolder.toFile());
        Process process = processBuilder.redirectErrorStream(true).start();
        ProcessLogger outLogger = ProcessLogger.start(process.getInputStream(), ansibleFolder.resolve("ansible.log"), "ansible");
        int exitCode = process.waitFor();
        outLogger.stop();
        return exitCode;
    } catch (IOException | InterruptedException e) {
      LOGGER.error("Error while calling Ansible", e);
      throw new RuntimeException("Error while calling Ansible", e);
    }
  }
  
}
