package tech.stackable.t2.terraform;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Objects;
import java.util.Properties;

import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import tech.stackable.t2.process.ProcessLogger;

public class TerraformRunner {

  private static final Logger LOGGER = LoggerFactory.getLogger(TerraformRunner.class);  
  
  private Path terraformFolder;
  private String datacenterName;
  private Properties credentials;

  private TerraformRunner(Path terraformFolder, String datacenterName, Properties credentials) {
    super();
    this.terraformFolder = terraformFolder;
    this.datacenterName = datacenterName;
    this.credentials = credentials;
  }

  public static TerraformRunner create(Path terraformFolder, String datacenterName, Properties credentials) {
    Objects.requireNonNull(terraformFolder);
    Objects.requireNonNull(datacenterName);
    if(StringUtils.isBlank(datacenterName)) {
      throw new IllegalArgumentException("The datacenterName must not be empty.");
    }
    if(!Files.exists(terraformFolder) || !Files.isDirectory(terraformFolder)) {
      LOGGER.error("The Terraform folder {} does not exist.");
      throw new IllegalArgumentException(String.format("The Terraform folder %s does not exist.", terraformFolder));
    }
    return new TerraformRunner(terraformFolder, datacenterName, credentials);
  }
  
  public TerraformResult init() {
    LOGGER.info("Running Terraform init on {}", this.terraformFolder);
    int result = this.callTerraform("init", "-input=false");
    return result==0 ? TerraformResult.SUCCESS : TerraformResult.ERROR;
  }

  public TerraformResult plan() {
    LOGGER.info("Running Terraform plan on {}", this.terraformFolder);
    int result = this.callTerraform("plan", "-detailed-exitcode -input=false");
    switch (result) {
    case 0:
      return TerraformResult.SUCCESS;
    case 2:
      return TerraformResult.CHANGES_PRESENT;
    default:
      return TerraformResult.ERROR;
    }
  }
  
  public TerraformResult apply() {
    LOGGER.info("Running Terraform apply on {}", this.terraformFolder);
    int result = this.callTerraform("apply", "-auto-approve -input=false");
    return result==0 ? TerraformResult.SUCCESS : TerraformResult.ERROR;
  }
  
  public TerraformResult destroy() {
    LOGGER.info("Running Terraform destroy on {}", this.terraformFolder);
    int result = this.callTerraform("destroy", "-auto-approve");
    return result==0 ? TerraformResult.SUCCESS : TerraformResult.ERROR;
  }
  
  public String getIpV4() {
    try {
      return Files.readString(this.terraformFolder.resolve("ip4v"));
    } catch (IOException e) {
      LOGGER.error("IPv4 Address for Cluster with TF file {} could not be read.", this.terraformFolder, e);
      return null;
    }
  }
  
  private int callTerraform(String command, String params) {
    try {
        ProcessBuilder processBuilder = new ProcessBuilder()
            .command("sh", "-c", String.format("terraform %s %s -no-color", command, params))
            .directory(this.terraformFolder.toFile());
        processBuilder.environment().put("TF_VAR_ionos_datacenter", datacenterName);
        this.credentials.forEach((key, value) -> {
          processBuilder.environment().put(String.format("TF_VAR_%s", key), value.toString());
        });
        Process process = processBuilder.start();
        ProcessLogger outLogger = ProcessLogger.start(process.getInputStream(), this.terraformFolder.resolve(String.format("terraform_%s.out.log", command)));
        ProcessLogger errLogger = ProcessLogger.start(process.getErrorStream(), this.terraformFolder.resolve(String.format("terraform_%s.err.log", command)));
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
