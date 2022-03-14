package trivy

import data.lib.trivy

default ignore = false

# Ignore CSRF
ignore {
	# https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2021-25122
	input.CweIDs[_] == "CVE-2021-25122"
}
