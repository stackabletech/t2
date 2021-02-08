package tech.stackable.t2.ansible;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.MessageFormat;
import java.util.Objects;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import tech.stackable.t2.process.ProcessLogger;
import tech.stackable.t2.security.SshKey;

public class AnsibleRunner {

  private static final Logger LOGGER = LoggerFactory.getLogger(AnsibleRunner.class);  
  
  private Path ansibleFolder;

  private SshKey sshKey;
  
  private AnsibleRunner(Path ansibleFolder, SshKey sshKey) {
    super();
    this.sshKey = Objects.requireNonNull(sshKey);
    this.ansibleFolder = ansibleFolder;
  }

  public static AnsibleRunner create(Path ansibleFolder, SshKey sshKey) {
    Objects.requireNonNull(ansibleFolder);
    if(!Files.exists(ansibleFolder) || !Files.isDirectory(ansibleFolder)) {
      LOGGER.error("The Ansible folder {} does not exist.");
      throw new IllegalArgumentException(String.format("The Ansible folder %s does not exist.", ansibleFolder));
    }
    return new AnsibleRunner(ansibleFolder, sshKey);
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
            .command("sh", "-c", MessageFormat.format("ansible-playbook --private-key={0} playbooks/all.yml", sshKey.getPrivateKeyPath()))
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
