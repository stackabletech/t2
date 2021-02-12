package tech.stackable.t2.ansible;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.MessageFormat;
import java.util.Properties;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Service;
import org.springframework.ui.freemarker.FreeMarkerTemplateUtils;

import freemarker.template.Configuration;
import freemarker.template.Template;
import freemarker.template.TemplateException;
import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.process.ProcessLogger;
import tech.stackable.t2.security.SshKey;

@Service
public class AnsibleService {

  private static final Logger LOGGER = LoggerFactory.getLogger(AnsibleService.class);  

  @Autowired
  @Qualifier("workspaceDirectory")
  private Path workspaceDirectory;
  
  @Autowired
  private SshKey sshKey;
  
  @Autowired
  private ResourceLoader resourceLoader;
  
  public AnsibleResult run(Path ansibleFolder) {
    LOGGER.info("Running Ansible on {}", ansibleFolder);
    int result = this.callAnsible(ansibleFolder);
    return result==0 ? AnsibleResult.SUCCESS : AnsibleResult.ERROR;
  }
  
  private int callAnsible(Path ansibleFolder) {
    try {
        ProcessBuilder processBuilder = new ProcessBuilder()
            .command("sh", "-c", MessageFormat.format("ansible-playbook --private-key={0} playbooks/all.yml", sshKey.getPrivateKeyPath()))
            .directory(ansibleFolder.toFile());
        Process process = processBuilder.start();
        ProcessLogger outLogger = ProcessLogger.start(process.getInputStream(), ansibleFolder.resolve("ansible.out.log"));
        ProcessLogger errLogger = ProcessLogger.start(process.getErrorStream(), ansibleFolder.resolve("ansible.err.log"));
        int exitCode = process.waitFor();
        outLogger.stop();
        errLogger.stop();
        return exitCode;
    } catch (IOException | InterruptedException e) {
      LOGGER.error("Error while calling Ansible", e);
      throw new RuntimeException("Error while calling Ansible", e);
    }
  }
  
  // TODO externalize template stuff: https://github.com/stackabletech/t2/issues/8
  /**
   * Gets the Ansible folder for the given cluster, creates it if necessary
   * @param cluster Cluster
   * @return Ansible folder for the given cluster
   */
  public Path ansibleFolder(Cluster cluster) {
    Path ansibleFolder = workspaceDirectory.resolve(cluster.getId().toString()).resolve("ansible");
    
    if(Files.exists(ansibleFolder) && Files.isDirectory(ansibleFolder)) {
      return ansibleFolder;
    }

    try {
      Properties props = new Properties();
      if(cluster.getIpV4Address()!=null) {
        props.put("cluster_ip", cluster.getIpV4Address());
      }
      if(cluster.getHostname()!=null) {
        props.put("cluster_hostname", cluster.getHostname());
      }
      props.put("cluster_uuid", cluster.getId());
      props.put("ssh_key_public", sshKey.getPublicKeyPath().toString());
      props.put("ssh_key_private", sshKey.getPrivateKeyPath().toString());
      copyFromResources("ansible/ansible.cfg", ansibleFolder.getParent());
      copyFromResources("ansible/roles/nginx/handlers/main.yml", ansibleFolder.getParent());
      copyFromResources("ansible/roles/nginx/templates/index.fm.html", ansibleFolder.getParent());
      copyFromResources("ansible/roles/nginx/tasks/main.yml", ansibleFolder.getParent());
      copyFromResources("ansible/roles/tasks/main.yml", ansibleFolder.getParent());
      copyFromResources("ansible/roles/firewalld/tasks/main.yml", ansibleFolder.getParent());
      copyFromResources("ansible/roles/enterprise_linux/tasks/main.yml", ansibleFolder.getParent());
      copyFromResources("ansible/playbooks/all.fm.yml", ansibleFolder.getParent());
      copyFromResources("ansible/inventory/group_vars/all/all.yml", ansibleFolder.getParent());
      copyFromResources("ansible/inventory/inventory.fm", ansibleFolder.getParent());
      copyFromResources("ansible/ansible.cfg", ansibleFolder.getParent());
      Files.walk(ansibleFolder)
      .filter(Files::isRegularFile)
      .filter(path -> StringUtils.contains(path.getFileName().toString(), ".fm"))
      .forEach(path -> {
        String newFileName = StringUtils.replace(path.getFileName().toString(), ".fm", "");
        Path processedFile = path.getParent().resolve(newFileName);
        try {
          InputStreamReader reader = new InputStreamReader(FileUtils.openInputStream(path.toFile()));
          Template template = new Template(newFileName, reader, new Configuration(Configuration.VERSION_2_3_30));
          String processedTemplateContent = FreeMarkerTemplateUtils.processTemplateIntoString(template, props);
          Files.writeString(processedFile, processedTemplateContent);
          Files.delete(path);
        } catch (IOException | TemplateException e) {
          LOGGER.error("Ansible directory for cluster {} could not be created.", cluster.getId(), e);
          throw new RuntimeException(String.format("Ansible directory for cluster %s could not be created.", cluster.getId()));
        }
      });
    } catch (IOException ioe) {
      LOGGER.error("Ansible directory for cluster {} could not be created.", cluster.getId(), ioe);
      throw new RuntimeException(String.format("Ansible directory for cluster %s could not be created.", cluster.getId()));
    }
    return ansibleFolder;
  }
  
  private void copyFromResources(String file, Path target) throws IOException {
    Resource resource = this.resourceLoader.getResource(String.format("classpath:templates/%s", file));
    String contents = new BufferedReader(new InputStreamReader(resource.getInputStream())).lines().collect(Collectors.joining(System.lineSeparator()));
    Path targetFile = target.resolve(file);
    Files.createDirectories(targetFile.getParent());
    Files.writeString(targetFile, contents);
  }
}
