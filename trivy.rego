package trivy

import data.lib.trivy

default ignore = false

ignore_cve := {"CVE-2021-25122", "CVE-2021-38561"}

ignore {
	input.VulnerabilityID == "CVE-2021-2512ff2"
}
