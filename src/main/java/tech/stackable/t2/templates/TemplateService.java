package tech.stackable.t2.templates;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.MessageFormat;
import java.util.HashMap;
import java.util.Map;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;

import tech.stackable.t2.api.cluster.controller.MalformedClusterDefinitionException;
import tech.stackable.t2.wireguard.WireguardService;

@Service
public class TemplateService {

    private static final Logger LOGGER = LoggerFactory.getLogger(TemplateService.class);

    @Autowired
    private WireguardService wireguardService;

    @Autowired
    @Qualifier("templateDirectory")
    private Path templateDirectory;

    /**
     * Creates a working directory for the given cluster, using the given cluster
     * definition (YAML)
     * 
     * @param workingDirectory  working directory location
     * @param clusterDefinition cluster definition as requested by the client. 
     * @return working directory path
     * @throws RuntimeException if directory does not exist
     */
    @SuppressWarnings("unchecked")
    public Path createWorkingDirectory(Path workingDirectory, Map<String, Object> clusterDefinition) {
        
        if(clusterDefinition==null) {
            throw new MalformedClusterDefinitionException("No cluster definition provided in the request.");
        }
        
        if (!clusterDefinition.containsKey("spec") ||
                !(clusterDefinition.get("spec") instanceof Map) ||
                !(((Map<String, Object>) clusterDefinition.get("spec")).containsKey("template")) ||
                !(((Map<String, Object>) clusterDefinition.get("spec")).get("template") instanceof String)) {
            throw new MalformedClusterDefinitionException(
                    "The cluster definition does not contain a valid template name.");
        }
        
        String templateName = (String) ((Map<String, Object>)clusterDefinition.get("spec")).get("template");

        if (StringUtils.startsWith(templateName, "_")) {
            throw new MalformedClusterDefinitionException(MessageFormat.format("The template {0} does not exist.", templateName));
        }

        Path templatePath = this.templateDirectory.resolve(templateName);
        if (!Files.exists(templatePath) || !Files.isDirectory(templatePath)) {
            throw new MalformedClusterDefinitionException(MessageFormat.format("The template {0} does not exist.", templateName));
        }

        try {


            if (!Files.exists(workingDirectory)) {
                Files.createDirectory(workingDirectory);
            }

            // Write cluster definition to working directory
            new ObjectMapper(new YAMLFactory()).writeValue(workingDirectory.resolve("cluster.yaml").toFile(), clusterDefinition);
            
            FileUtils.copyDirectory(templateDirectory.resolve("_common").toFile(), workingDirectory.toFile());
            
            FileUtils.copyDirectory(templatePath.toFile(), workingDirectory.toFile());

            this.createWireguardKeysFile(workingDirectory.resolve("wireguard.yaml").toFile());
            
        } catch (IOException e) {
            LOGGER.error("Working directory {} could not be created.", workingDirectory, e);
            throw new RuntimeException(String.format("Working directory %s could not be created.", workingDirectory));
        }
        return workingDirectory;
    }

    /**
     * Cleans up the working directory for the given cluster
     * 
     * @param workingDirectory  working directory location
     */
    public void cleanUpWorkingDirectory(Path workingDirectory) {
        
        try {

            if (!Files.exists(workingDirectory)) {
                return;
            }

            // remove terraform cache folder
            FileUtils.deleteDirectory(workingDirectory.resolve(".terraform/").toFile());
            
        } catch (IOException e) {
            LOGGER.warn("Working directory {} could not be cleaned up.", workingDirectory, e);
        }
    }

    private void createWireguardKeysFile(File file) throws IOException {
    	Map<String, Object> wireguardKeys = new HashMap<>();
    	wireguardKeys.put("server", wireguardService.keypair());
    	wireguardKeys.put("clients", wireguardService.keypairs(16).collect(Collectors.toList()));
    	new ObjectMapper(new YAMLFactory()).writeValue(file, wireguardKeys);
    }
    
}
