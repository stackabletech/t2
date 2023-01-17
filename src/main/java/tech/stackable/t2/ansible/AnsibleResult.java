package tech.stackable.t2.ansible;

/**
 * Result of a call to Ansible.
 */
public enum AnsibleResult {

    ERROR,
    SUCCESS;

    /**
     * Get Ansible result by exit code.
     * 
     * @param exitCode Exit code of the Ansible process.
     * @return Ansible result
     */
    public static AnsibleResult byExitCode(int exitCode) {
        return exitCode == 0 ? SUCCESS : ERROR;
    }

}
