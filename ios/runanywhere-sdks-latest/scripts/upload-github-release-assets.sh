#!/usr/bin/env bash
# Upload pre-built xcframework zips to an existing or new GitHub Release.
# Requires: curl, jq, and a classic PAT or fine-grained token with Contents + Releases write.
#
# Usage:
#   export GITHUB_TOKEN=ghp_xxxxxxxx
#   ./upload-github-release-assets.sh r19 \
#     ../sdk/runanywhere-commons/dist/RACommons.xcframework-r19.zip \
#     ../sdk/runanywhere-commons/dist/RABackendLLAMACPP.xcframework-r19.zip
#
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-timmyy123/LLM-Hub}"
API="https://api.github.com/repos/${REPO}"
UPLOAD_HOST="https://uploads.github.com/repos/${REPO}"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN is not set. Create a token with repo scope (or fine-grained: Contents + Releases write), then:" >&2
  echo "  export GITHUB_TOKEN=..." >&2
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <tag> <zip> [zip ...]" >&2
  exit 1
fi

TAG="$1"
shift
FILES=("$@")
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { echo "missing file: $f" >&2; exit 1; }
done

auth_hdr=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

json_get() {
  local url="$1"
  curl -fsS "${auth_hdr[@]}" "$url"
}

json_post() {
  local url="$1"
  local body="$2"
  curl -fsS "${auth_hdr[@]}" -X POST "$url" -d "$body"
}

echo "==> Looking for release with tag ${TAG}"
rel_json="$(json_get "${API}/releases/tags/${TAG}" 2>/dev/null || true)"
if ! echo "$rel_json" | jq -e .id >/dev/null 2>&1; then
  echo "==> Creating release ${TAG}"
  body="$(jq -n --arg tag "$TAG" --arg name "iOS native SDK ${TAG}" \
    '{tag_name:$tag, name:$name, body:"Native xcframeworks (RACommons + RABackendLLAMACPP).", draft:false, prerelease:false}')"
  rel_json="$(json_post "${API}/releases" "$body")"
fi

REL_ID="$(echo "$rel_json" | jq -r .id)"
UPLOAD_URL="$(echo "$rel_json" | jq -r .upload_url | sed 's/{?name,label}//')"
if [[ -z "$REL_ID" || "$REL_ID" == "null" ]]; then
  echo "failed to resolve release id" >&2
  exit 1
fi
echo "==> Release id ${REL_ID}"

for f in "${FILES[@]}"; do
  base="$(basename "$f")"
  echo "==> Uploading ${base}"
  curl -fsS "${auth_hdr[@]}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${f}" \
    "${UPLOAD_URL}?name=${base}" >/dev/null
  echo "    ok"
done

echo "==> Done. SPM URL example:"
echo "    https://github.com/${REPO}/releases/download/${TAG}/RACommons.xcframework-${TAG}.zip"
