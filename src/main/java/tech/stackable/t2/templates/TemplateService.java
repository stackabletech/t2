package tech.stackable.t2.templates;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.MessageFormat;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import org.apache.commons.io.FileUtils;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Service;
import org.springframework.ui.freemarker.FreeMarkerTemplateUtils;

import com.fasterxml.jackson.databind.ObjectMapper;

import freemarker.template.Configuration;
import freemarker.template.Template;
import freemarker.template.TemplateException;
import tech.stackable.t2.api.cluster.domain.Cluster;
import tech.stackable.t2.security.SshKey;
import tech.stackable.t2.wireguard.WireguardService;

@Service
public class TemplateService {

  private static final Logger LOGGER = LoggerFactory.getLogger(TemplateService.class);  

  @Autowired
  private WireguardService wireguardService;

  @Autowired
  @Qualifier("workspaceDirectory")
  private Path workspaceDirectory;
  
  @Autowired
  @Qualifier("credentials")
  private Properties credentials;

  @Value("${t2.dns.cluster-domain}")
  private String domain;

  @Autowired
  private SshKey sshKey;
  
  @Autowired
  private ResourceLoader resourceLoader;
  
  /**
   * Creates a working directory for the given cluster, using the given cluster definition (JSON)
   * @param cluster Cluster
   * @param clusterDefinition cluster definition as requested by the client. If missing, default of the template is used
   * @return working folder for the given cluster
   */
  public Path createWorkingDirectory(Cluster cluster, Map<String, Object> clusterDefinition) {
    Path workingDirectory = workspaceDirectory.resolve(cluster.getId().toString());
    
    if(Files.exists(workingDirectory) && Files.isDirectory(workingDirectory)) {
      throw new RuntimeException(String.format("Working directory for cluster %s could not be created because it already exists.", cluster.getId()));
    }

    try {
      
      // Template variables
      Map<String, Object> templateVariables = new HashMap<>();

      // Generate Keypairs for Wireguard
      String natPrivateKey = this.wireguardService.generatePrivateKey();
      String natPublicKey = this.wireguardService.generatePublicKey(natPrivateKey);
      List<String> clientPrivateKeys = Stream.generate(wireguardService::generatePrivateKey).limit(8).collect(Collectors.toList());
      List<String> clientPublicKeys = clientPrivateKeys.stream().map(this.wireguardService::generatePublicKey).collect(Collectors.toList());
      
      // Additional props that can be used in a template
      templateVariables.put("t2_ssh_key_public", sshKey.getPublicKeyPath().toString());
      templateVariables.put("t2_ssh_key_private", sshKey.getPrivateKeyPath().toString());
      templateVariables.put("datacenter_name", MessageFormat.format("t2-{0}", cluster.getId()));
      templateVariables.put("public_hostname", MessageFormat.format("{0}.{1}", cluster.getShortId(), this.domain));
      templateVariables.put("wireguard_client_public_keys", clientPublicKeys);
      templateVariables.put("wireguard_client_private_keys", clientPrivateKeys);
      templateVariables.put("wireguard_nat_public_key", natPublicKey);
      templateVariables.put("wireguard_nat_private_key", natPrivateKey);

      // Use cluster definition provided in request or load the dafault from the template files
      if(clusterDefinition!=null) {
        templateVariables.put("clusterDefinition", clusterDefinition);
      } else {
        templateVariables.put("clusterDefinition", defaultClusterDefinition());
      }
      
      // Copy all template files
      copyFromResources("main.fm.tf", workingDirectory);
      copyFromResources("ansible.cfg", workingDirectory);
      copyFromResources("playbook.yml", workingDirectory);
      copyFromResources("templates/ansible-variables.tpl", workingDirectory);
      copyFromResources("templates/ansible-inventory.tpl", workingDirectory);
      copyFromResources("templates/ssh-script.tpl", workingDirectory);
      copyFromResources("templates/ssh-nat-script.tpl", workingDirectory);
      copyFromResources("templates/wg-client.conf.tpl", workingDirectory);
      copyFromResources("templates/wg.conf.tpl", workingDirectory);

      copyFromResources("roles/nat/handlers/main.yml", workingDirectory);
      copyFromResources("roles/nat/tasks/main.yml", workingDirectory);
      copyFromResources("roles/nat/tasks/bind.yml", workingDirectory);
      copyFromResources("roles/nat/tasks/firewall.yml", workingDirectory);
      copyFromResources("roles/nat/templates/bind/named.conf.j2", workingDirectory);
      copyFromResources("roles/nat/templates/bind/stackable.zone.j2", workingDirectory);
      copyFromResources("roles/nat/templates/firewall/setup-firewall.service.j2", workingDirectory);

      copyFromResources("roles/nginx/handlers/main.yml", workingDirectory);
      copyFromResources("roles/nginx/templates/index.html", workingDirectory);
      copyFromResources("roles/nginx/tasks/main.yml", workingDirectory);

      copyFromResources("roles/wireguard/tasks/main.yml", workingDirectory);
      copyFromResources("roles/wireguard/handlers/main.yml", workingDirectory);

      copyFromResources("roles/protected/defaults/main.yml", workingDirectory);
      copyFromResources("roles/protected/handlers/main.yml", workingDirectory);
      copyFromResources("roles/protected/tasks/main.yml", workingDirectory);
      copyFromResources("roles/protected/tasks/network.yml", workingDirectory);
      copyFromResources("roles/protected/templates/chrony.conf.j2", workingDirectory);
      copyFromResources("roles/protected/templates/network/configure_network.service.j2", workingDirectory);
      copyFromResources("roles/protected/templates/network/networkconf.sh.j2", workingDirectory);
      copyFromResources("roles/protected/templates/network/resolv.conf.j2", workingDirectory);
      
      // templating w/ Freemarker
      Files.walk(workingDirectory)
          .filter(Files::isRegularFile)
          .filter(path -> StringUtils.contains(path.getFileName().toString(), ".fm"))
          .forEach(path -> {
            String newFileName = StringUtils.replace(path.getFileName().toString(), ".fm", "");
            Path processedFile = path.getParent().resolve(newFileName);
            try {
              InputStreamReader reader = new InputStreamReader(FileUtils.openInputStream(path.toFile()));
              Configuration cfg = new Configuration(Configuration.VERSION_2_3_30);
              cfg.setInterpolationSyntax(Configuration.SQUARE_BRACKET_INTERPOLATION_SYNTAX);
              cfg.setTagSyntax(Configuration.SQUARE_BRACKET_TAG_SYNTAX);
              cfg.setSetting("number_format", "0.####");
              Template template = new Template(newFileName, reader, cfg);
              String processedTemplateContent = FreeMarkerTemplateUtils.processTemplateIntoString(template, templateVariables);
              Files.writeString(processedFile, processedTemplateContent);
              Files.delete(path);
            } catch (IOException | TemplateException e) {
              LOGGER.error("Working directory for cluster {} could not be created.", cluster.getId(), e);
              throw new RuntimeException(String.format("Working directory for cluster %s could not be created.", cluster.getId()));
            }
          });
    } catch (IOException ioe) {
      LOGGER.error("Working directory for cluster {} could not be created.", cluster.getId(), ioe);
      throw new RuntimeException(String.format("Working directory for cluster %s could not be created.", cluster.getId()));
    }
    return workingDirectory;
  }
  
  public Path getWorkingDirectory(Cluster cluster) {
    Path workingDirectory = workspaceDirectory.resolve(cluster.getId().toString());
    
    if(!Files.exists(workingDirectory) || !Files.isDirectory(workingDirectory)) {
      throw new RuntimeException(String.format("Working directory for cluster %s does not exist.", cluster.getId()));
    }
    
    return workingDirectory;
  }
  
  private void copyFromResources(String file, Path target) throws IOException {
    Resource resource = this.resourceLoader.getResource(String.format("classpath:templates/default/%s", file));
    String contents = new BufferedReader(new InputStreamReader(resource.getInputStream())).lines().collect(Collectors.joining(System.lineSeparator()));
    Path targetFile = target.resolve(file);
    Files.createDirectories(targetFile.getParent());
    Files.writeString(targetFile, contents);
  }

  @SuppressWarnings("unchecked")
  private Map<String, Object> defaultClusterDefinition() throws IOException {
    Resource resource = this.resourceLoader.getResource("classpath:templates/default/cluster.json");
    String contents = new BufferedReader(new InputStreamReader(resource.getInputStream())).lines().collect(Collectors.joining(System.lineSeparator()));
    ObjectMapper mapper = new ObjectMapper();
    return mapper.readValue(contents, Map.class);
  }

}
