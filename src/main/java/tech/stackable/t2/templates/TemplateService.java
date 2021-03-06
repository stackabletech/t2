package tech.stackable.t2.templates;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.MessageFormat;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;
import java.util.stream.Collectors;

import org.apache.commons.io.FileUtils;
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

    @Autowired
    @Qualifier("credentials")
    private Properties credentials;

    /**
     * Creates a working directory for the given cluster, using the given cluster
     * definition (YAML)
     * 
     * @param workingDirectory  working directory location
     * @param clusterDefinition cluster definition as requested by the client. 
     * @return working directory path
     * @throws RuntimeException if directory does not exist
     */
    public Path createWorkingDirectory(Path workingDirectory, Map<String, Object> clusterDefinition) {
    	
    	if(clusterDefinition==null) {
    		throw new MalformedClusterDefinitionException("No cluster definition provided in the request.");
    	}
    	
    	if(!clusterDefinition.containsKey("template") || !(clusterDefinition.get("template") instanceof String)) {
    		throw new MalformedClusterDefinitionException("The cluster definition does not contain a valid template name.");
    	}
    	
        String templateName = (String) clusterDefinition.get("template");

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

    private void createWireguardKeysFile(File file) throws IOException {
    	Map<String, Object> wireguardKeys = new HashMap<>();
    	wireguardKeys.put("server", wireguardService.keypair());
    	wireguardKeys.put("clients", wireguardService.keypairs(16).collect(Collectors.toList()));
    	new ObjectMapper(new YAMLFactory()).writeValue(file, wireguardKeys);
    }
    
}
