package tech.stackable.t2;

import static java.nio.file.Files.createDirectories;
import static java.nio.file.Files.exists;
import static java.nio.file.Files.isDirectory;
import static java.nio.file.Files.isWritable;

import java.io.IOException;
import java.nio.file.Path;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.BeanCreationException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class T2ServerApplication {

    private static final Logger LOGGER = LoggerFactory.getLogger(T2ServerApplication.class);

    public static void main(String[] args) {
        SpringApplication.run(T2ServerApplication.class, args);
    }

    @Bean(name = "workspaceDirectory")
    public Path workspaceDirectory(@Value("${t2.workspace.directory}") String workspaceDirectory) {

        LOGGER.info("Configure workspace directory...");

        Path path = Path.of(workspaceDirectory);

        if (exists(path) && isDirectory(path)) {
            if (!isWritable(path)) {
                throw new BeanCreationException(String.format("The specified workspace directory '%s' is not writeable.", workspaceDirectory));
            }
            return path;
        }

        if (exists(path)) {
            throw new BeanCreationException(String.format("The specified workspace directory '%s' is not a directory.", workspaceDirectory));
        }

        try {
            createDirectories(path);
            LOGGER.info("Configured workspace directory: {}", path);
            return path;
        } catch (IOException ioe) {
            throw new BeanCreationException(String.format("The specified workspace directory '%s' cannot be created.", workspaceDirectory), ioe);
        }

    }

    @Bean(name = "templateDirectory")
    public Path templateDirectory(@Value("${t2.templates.directory}") String templateDirectory) {

        LOGGER.info("Configure template directory...");

        Path path = Path.of(templateDirectory);

        if (exists(path) && isDirectory(path)) {
            if (!isWritable(path)) {
                throw new BeanCreationException(String.format("The specified template directory '%s' is not writeable.", templateDirectory));
            }
            return path;
        }

        if (exists(path)) {
            throw new BeanCreationException(String.format("The specified template directory '%s' is not a directory.", templateDirectory));
        }

        try {
            createDirectories(path);
            LOGGER.info("Configured template directory: {}", path);
            return path;
        } catch (IOException ioe) {
            throw new BeanCreationException(String.format("The specified template directory '%s' cannot be created.", templateDirectory), ioe);
        }

    }

}
