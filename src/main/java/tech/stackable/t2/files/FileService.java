package tech.stackable.t2.files;

import static java.nio.file.Files.createDirectories;
import static java.nio.file.Files.exists;
import static java.nio.file.Files.isDirectory;
import static java.nio.file.Files.isWritable;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.MessageFormat;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

import org.apache.commons.io.FileUtils;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.BeanCreationException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;

import tech.stackable.t2.api.MalformedClusterDefinitionException;

/**
 * This service deals with the working directory of a cluster and the template directory.
 */
@Service
public class FileService {

    private static final Logger LOGGER = LoggerFactory.getLogger(FileService.class);

    private Path templateDirectory;
    private Path workspaceDirectory;

    public FileService(@Value("${t2.workspace.directory}") String workspaceDirectory, @Value("${t2.templates.directory}") String templateDirectory) {
        this.templateDirectory = assertIsDirectory(templateDirectory);
        this.workspaceDirectory = assertIsDirectory(workspaceDirectory);
    }

    /**
     * Resolves the working directory for the given cluster.
     * 
     * @param clusterId ID of the cluster
     * @return working directory
     */
    public Path workingDirectory(UUID clusterId) {
        Objects.requireNonNull(clusterId);

        return this.workspaceDirectory.resolve(clusterId.toString());
    }

    /**
     * Creates a working directory using the given cluster definition (YAML).
     * 
     * The creation includes the copying of the template files.
     * 
     * @param workingDirectory  working directory location, must not be <code>null</code>
     * @param clusterDefinition cluster definition
     */
    @SuppressWarnings("unchecked")
    public void createWorkingDirectory(Path workingDirectory, Map<String, Object> clusterDefinition) {
        Objects.requireNonNull(workingDirectory);
        Objects.requireNonNull(clusterDefinition);

        // Check if spec.template exists and is a String
        if (!clusterDefinition.containsKey("spec")
                || !(clusterDefinition.get("spec") instanceof Map)
                || !(((Map<String, Object>) clusterDefinition.get("spec")).containsKey("template"))
                || !(((Map<String, Object>) clusterDefinition.get("spec")).get("template") instanceof String)) {
            throw new MalformedClusterDefinitionException("The cluster definition does not contain a valid template name.");
        }

        String templateName = (String) ((Map<String, Object>) clusterDefinition.get("spec")).get("template");

        // Templates prefixed with '_' are considered not existing (they are deactivated)
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

            // Copy files of the needed template to the working directory
            FileUtils.copyDirectory(templateDirectory.resolve("_common").toFile(), workingDirectory.toFile());
            FileUtils.copyDirectory(templatePath.toFile(), workingDirectory.toFile());

        } catch (IOException e) {
            LOGGER.error("Working directory {} could not be created.", workingDirectory, e);
            throw new RuntimeException(String.format("Working directory %s could not be created.", workingDirectory));
        }
    }

    /**
     * Cleans up the working directory for the given cluster
     * 
     * @param workingDirectory working directory location
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

    /**
     * Makes sure that the given directory exists.
     * 
     * @param directoryName name of the directory to be checked
     * @return Path to the directory as Java NIO object.
     * @throws BeanCreationException if directory cannot be created as a writable directory.
     */
    private Path assertIsDirectory(String directoryName) {
        Path directoryPath = Path.of(directoryName);

        if (exists(directoryPath) && isDirectory(directoryPath)) {
            if (!isWritable(directoryPath)) {
                throw new BeanCreationException(String.format("The directory '%s' is not writeable.", directoryName));
            }
            return directoryPath;
        }

        if (exists(directoryPath)) {
            throw new BeanCreationException(String.format("The path '%s' is not a directory.", directoryName));
        }

        try {
            createDirectories(directoryPath);
            return directoryPath;
        } catch (IOException ioe) {
            throw new BeanCreationException(String.format("The directory '%s' cannot be created.", directoryName), ioe);
        }
    }
}
