package trivy

import data.lib.trivy

default ignore = false

ignore {
	# https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2021-25122
	input.VulnerabilityID == "CVE-2021-25122"
}
