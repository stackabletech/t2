package tech.stackable.t2;

import static java.nio.file.Files.createDirectories;
import static java.nio.file.Files.exists;
import static java.nio.file.Files.isDirectory;
import static java.nio.file.Files.isWritable;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.text.MessageFormat;

import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.BeanCreationException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableScheduling;

import tech.stackable.t2.process.ProcessLogger;

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
            LOGGER.info("Configured workspace directory: {}", path);
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
        if(templateDirectory.startsWith("~")) {
        	path = Path.of(StringUtils.replace(templateDirectory, "~", System.getProperty("user.home"), 1));
        }

        if (exists(path) && isDirectory(path)) {
            if (!isWritable(path)) {
                throw new BeanCreationException(String.format("The specified template directory '%s' is not writeable.", templateDirectory));
            }
            LOGGER.info("Configured template directory: {}", path);
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
    
    @Bean
    CommandLineRunner commandLineRunner() {
      return new CommandLineRunner() {
        @Override
        public void run(String... args) throws Exception {
            try {
            	LOGGER.info("Initializing tools...");
                ProcessBuilder processBuilder = new ProcessBuilder()
                        .command("sh", "-c", "init_tools.sh")
                        .directory(Paths.get("/").toFile());
                Process process = processBuilder.redirectErrorStream(true).start();
                int exitCode = process.waitFor();
                if (exitCode!=0) {
                    LOGGER.error("Error while initializing tools");
                    throw new RuntimeException("Error while initializing tools");
                }
            } catch (IOException | InterruptedException e) {
                LOGGER.error("Error while initializing tools", e);
                throw new RuntimeException("Error while initializing tools", e);
            }
        }
      };
    }

}
