package tech.stackable.t2.templates;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.MessageFormat;
import java.util.Map;
import java.util.Properties;
import java.util.stream.Collectors;

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

@Service
public class TemplateService {

  private static final Logger LOGGER = LoggerFactory.getLogger(TemplateService.class);  

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
   * Gets the working directory for the given cluster, creates it if necessary
   * @param cluster Cluster
   * @return working folder for the given cluster
   */
  public Path workingDirectory(Cluster cluster) {
    Path workingDirectory = workspaceDirectory.resolve(cluster.getId().toString());
    
    if(Files.exists(workingDirectory) && Files.isDirectory(workingDirectory)) {
      return workingDirectory;
    }

    try {
      
      // The cluster config is the base for the props that can be used in a template
      Map<Object, Object> clusterConfig = clusterConfig();
      
      // Additional props that can be used in a template
      clusterConfig.put("ssh_key_public_path", sshKey.getPublicKeyPath().toString());
      clusterConfig.put("ssh_key_private_path", sshKey.getPrivateKeyPath().toString());
      clusterConfig.put("datacenter_name", MessageFormat.format("t2-{0}", cluster.getId()));
      clusterConfig.put("public_hostname", MessageFormat.format("{0}.{1}", cluster.getShortId(), this.domain));
            
      // TODO externalize template stuff: https://github.com/stackabletech/t2/issues/8
      
      // Copy all template files
      copyFromResources("main.fm.tf", workingDirectory);
      copyFromResources("ansible.cfg", workingDirectory);
      copyFromResources("playbook.yml", workingDirectory);
      copyFromResources("inventory/group_vars/all/all.yml", workingDirectory);
      copyFromResources("templates/ansible-inventory.tpl", workingDirectory);
      copyFromResources("templates/ssh-script.tpl", workingDirectory);

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
              String processedTemplateContent = FreeMarkerTemplateUtils.processTemplateIntoString(template, clusterConfig);
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
  private void copyFromResources(String file, Path target) throws IOException {
    Resource resource = this.resourceLoader.getResource(String.format("classpath:templates/default/%s", file));
    String contents = new BufferedReader(new InputStreamReader(resource.getInputStream())).lines().collect(Collectors.joining(System.lineSeparator()));
    Path targetFile = target.resolve(file);
    Files.createDirectories(targetFile.getParent());
    Files.writeString(targetFile, contents);
  }

  @SuppressWarnings("unchecked")
  private Map<Object, Object> clusterConfig() throws IOException {
    Resource resource = this.resourceLoader.getResource("classpath:templates/default/cluster.json");
    String contents = new BufferedReader(new InputStreamReader(resource.getInputStream())).lines().collect(Collectors.joining(System.lineSeparator()));
    ObjectMapper mapper = new ObjectMapper();
    return mapper.readValue(contents, Map.class);
  }

}
