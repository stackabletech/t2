package tech.stackable.t2.ansible;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Objects;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import tech.stackable.t2.process.ProcessLogger;

public class AnsibleRunner {

  private static final Logger LOGGER = LoggerFactory.getLogger(AnsibleRunner.class);  
  
  private Path ansibleFolder;

  private AnsibleRunner(Path ansibleFolder) {
    super();
    this.ansibleFolder = ansibleFolder;
  }

  public static AnsibleRunner create(Path ansibleFolder) {
    Objects.requireNonNull(ansibleFolder);
    if(!Files.exists(ansibleFolder) || !Files.isDirectory(ansibleFolder)) {
      LOGGER.error("The Ansible folder {} does not exist.");
      throw new IllegalArgumentException(String.format("The Ansible folder %s does not exist.", ansibleFolder));
    }
    return new AnsibleRunner(ansibleFolder);
  }
  
  public AnsibleResult run() {
    LOGGER.info("Running Ansible on {}", this.ansibleFolder);
    int result = this.callAnsible();
    return result==0 ? AnsibleResult.SUCCESS : AnsibleResult.ERROR;
  }
  
  // TODO configure key, not hard coded!!!
  private int callAnsible() {
    try {
        ProcessBuilder processBuilder = new ProcessBuilder()
            .command("sh", "-c", "ansible-playbook --private-key=/home/t2/.ssh/t2 playbooks/all.yml")
            .directory(this.ansibleFolder.toFile());
        Process process = processBuilder.start();
        ProcessLogger outLogger = ProcessLogger.start(process.getInputStream(), this.ansibleFolder.resolve("ansible.out.log"));
        ProcessLogger errLogger = ProcessLogger.start(process.getErrorStream(), this.ansibleFolder.resolve("ansible.err.log"));
        int exitCode = process.waitFor();
        outLogger.stop();
        errLogger.stop();
        return exitCode;
    } catch (IOException | InterruptedException e) {
      // TODO handle this kind of error.
      throw new RuntimeException(e);
    }
  }
  
}
