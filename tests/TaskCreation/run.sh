#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
TASK_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TASK_TEST_DIR"' EXIT
swiftc reminder/Services/TaskCreation/TaskRecognitionDateValidator.swift tests/TaskCreation/AppleRecognitionValidationTests.swift -o "$TASK_TEST_DIR/dates"
"$TASK_TEST_DIR/dates"
python3 - "$TASK_TEST_DIR" <<'PY'
import sys
from pathlib import Path
root=Path(sys.argv[1])
s=Path('reminder/Services/AITaskParserService.swift').read_text()
root.joinpath('payload.swift').write_text('import Foundation\n'+s[s.index('struct AIParsedTaskPayload'):s.index('private struct AIParseTaskImageResponse')])
root.joinpath('matching.swift').write_text('''import Foundation
struct HouseholdMembership { var id: UUID; var nickname: String? }
struct FamilyProfile {
 var id: UUID; var name: String; var displayName: String; var primaryMembership: HouseholdMembership?
 static func mergingMembershipRows(_ profiles: [FamilyProfile], memberships: [HouseholdMembership]) -> [FamilyProfile] { profiles }
}
''')
PY
swiftc "$TASK_TEST_DIR/payload.swift" tests/TaskCreation/PayloadDecodingTests.swift -o "$TASK_TEST_DIR/payload"
"$TASK_TEST_DIR/payload"
swiftc "$TASK_TEST_DIR/matching.swift" reminder/Utilities/AIParticipantHintMatcher.swift tests/TaskCreation/ParticipantMatchingTests.swift -o "$TASK_TEST_DIR/matching"
"$TASK_TEST_DIR/matching"
