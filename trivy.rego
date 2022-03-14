package trivy

import data.lib.trivy

default ignore = false

ignore_cve := {"CVE-2021-25122", "CVE-2021-22060"}

ignore {
	input.VulnerabilityID == ignore_cve[_]
}
