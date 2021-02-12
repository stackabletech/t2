package tech.stackable.t2.terraform;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
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
public class TerraformService {

  private static final Logger LOGGER = LoggerFactory.getLogger(TerraformService.class);  

  @Autowired
  @Qualifier("workspaceDirectory")
  private Path workspaceDirectory;
  
  @Autowired
  @Qualifier("credentials")
  private Properties credentials;

  @Autowired
  private SshKey sshKey;
  
  @Autowired
  private ResourceLoader resourceLoader;
  
  public TerraformResult init(Path terraformFolder, String datacenter) {
    LOGGER.info("Running Terraform init on {}", terraformFolder);
    int result = this.callTerraform(terraformFolder, datacenter, "init", "-input=false");
    return result==0 ? TerraformResult.SUCCESS : TerraformResult.ERROR;
  }

  public TerraformResult plan(Path terraformFolder, String datacenter) {
    LOGGER.info("Running Terraform plan on {}", terraformFolder);
    int result = this.callTerraform(terraformFolder, datacenter, "plan", "-detailed-exitcode -input=false");
    switch (result) {
    case 0:
      return TerraformResult.SUCCESS;
    case 2:
      return TerraformResult.CHANGES_PRESENT;
    default:
      return TerraformResult.ERROR;
    }
  }
  
  public TerraformResult apply(Path terraformFolder, String datacenter) {
    LOGGER.info("Running Terraform apply on {}", terraformFolder);
    int result = this.callTerraform(terraformFolder, datacenter, "apply", "-auto-approve -input=false");
    return result==0 ? TerraformResult.SUCCESS : TerraformResult.ERROR;
  }
  
  public TerraformResult destroy(Path terraformFolder, String datacenter) {
    LOGGER.info("Running Terraform destroy on {}", terraformFolder);
    int result = this.callTerraform(terraformFolder, datacenter, "destroy", "-auto-approve");
    return result==0 ? TerraformResult.SUCCESS : TerraformResult.ERROR;
  }
  
  public String getIpV4(Path terraformFolder) {
    try {
      return Files.readString(terraformFolder.resolve("ipv4"));
    } catch (IOException e) {
      LOGGER.error("IPv4 Address for Cluster with TF file {} could not be read.", terraformFolder, e);
      return null;
    }
  }
  
  // TODO externalize template stuff: https://github.com/stackabletech/t2/issues/8
  /**
   * Gets the Terraform folder for the given cluster, creates it if necessary
   * @param cluster Cluster
   * @return Terraform folder for the given cluster
   */
  public Path terraformFolder(Cluster cluster) {
    Path terraformFolder = workspaceDirectory.resolve(cluster.getId().toString()).resolve("terraform");
    
    if(Files.exists(terraformFolder) && Files.isDirectory(terraformFolder)) {
      return terraformFolder;
    }

    try {
      Properties props = new Properties();
      if(cluster.getIpV4Address()!=null) {
        props.put("cluster_ip", cluster.getIpV4Address());
      }
      props.put("cluster_uuid", cluster.getId());
      if(cluster.getHostname()!=null) {
        props.put("cluster_hostname", cluster.getHostname());
      }
      props.put("ssh_key_public", sshKey.getPublicKeyPath().toString());
      props.put("ssh_key_private", sshKey.getPrivateKeyPath().toString());
      copyFromResources("terraform/cluster.fm.tf", terraformFolder.getParent());
      Files.walk(terraformFolder)
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
      LOGGER.error("Terraform directory for cluster {} could not be created.", cluster.getId(), ioe);
      throw new RuntimeException(String.format("Terraform directory for cluster %s could not be created.", cluster.getId()));
    }
    return terraformFolder;
  }
  
  
  private int callTerraform(Path terraformFolder, String datacenter, String command, String params) {
    try {
        ProcessBuilder processBuilder = new ProcessBuilder()
            .command("sh", "-c", String.format("terraform %s %s -no-color", command, params))
            .directory(terraformFolder.toFile());
        processBuilder.environment().put("TF_VAR_ionos_datacenter", datacenter);
        // TODO only use selected values needed for terraform
        this.credentials.forEach((key, value) -> {
          processBuilder.environment().put(String.format("TF_VAR_%s", key), value.toString());
        });
        Process process = processBuilder.start();
        ProcessLogger outLogger = ProcessLogger.start(process.getInputStream(), terraformFolder.resolve(String.format("terraform_%s.out.log", command)));
        ProcessLogger errLogger = ProcessLogger.start(process.getErrorStream(), terraformFolder.resolve(String.format("terraform_%s.err.log", command)));
        int exitCode = process.waitFor();
        outLogger.stop();
        errLogger.stop();
        return exitCode;
    } catch (IOException | InterruptedException e) {
      LOGGER.error("Error while calling terraform", e);
      throw new RuntimeException("Error while calling terraform", e);
    }
  }

  private void copyFromResources(String file, Path target) throws IOException {
    Resource resource = this.resourceLoader.getResource(String.format("classpath:templates/%s", file));
    String contents = new BufferedReader(new InputStreamReader(resource.getInputStream())).lines().collect(Collectors.joining(System.lineSeparator()));
    Path targetFile = target.resolve(file);
    Files.createDirectories(targetFile.getParent());
    Files.writeString(targetFile, contents);
  }
}
