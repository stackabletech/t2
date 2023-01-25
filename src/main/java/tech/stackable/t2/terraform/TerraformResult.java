package tech.stackable.t2.terraform;

/**
 * Result of a call to Terraform.
 */
public enum TerraformResult {

    ERROR,
    SUCCESS,
    CHANGES_PRESENT;

    /**
     * Get Terraform result by exit code.
     * 
     * @param exitCode Exit code of the Terraform process.
     * @return Terraform result
     */
    public static TerraformResult byExitCode(int exitCode) {
        switch (exitCode) {
        case 0:
            return SUCCESS;
        case 2:
            return CHANGES_PRESENT;
        default:
            return ERROR;
        }
    }
}
