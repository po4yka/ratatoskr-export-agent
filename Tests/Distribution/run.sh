#!/bin/bash
set -euo pipefail

test_root=$(cd "$(dirname "$0")" && pwd)

"$test_root/PackageAppTests.sh"
"$test_root/EntitlementsPolicyTests.sh"
"$test_root/SignaturePolicyTests.sh"
"$test_root/SandboxSmokeTests.sh"
"$test_root/OwnerSecretValidationTests.sh"
"$test_root/WorkflowContractTests.sh"
"$test_root/CleanMachineAcceptanceTests.sh"
