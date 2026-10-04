#!/usr/bin/env bash
set -Eeuo pipefail
# Linux amd64 GitHub-hosted runner only. No system-wide installation.
test "$(uname -s)/$(uname -m)" = Linux/x86_64 || { printf 'Linux amd64 required\n' >&2; exit 1; }
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool_dir="$root_dir/.tools/bin"
mkdir -p "$tool_dir"
work_dir="$(mktemp -d)"
trap 'rm -r "$work_dir"' EXIT

download_checked() {
  local repo="$1" tag="$2" archive="$3" sums="$4" binary="$5"
  local extract_dir="$work_dir/${binary}-${tag//\//_}"
  mkdir -p "$extract_dir"
  gh release download "$tag" --repo "$repo" --pattern "$archive" --pattern "$sums" --dir "$extract_dir"
  (cd "$extract_dir" && shasum -a 256 -c "$sums" --ignore-missing)
  tar -xzf "$extract_dir/$archive" -C "$tool_dir" "$binary"
}

download_checked score-spec/score-k8s 0.19.0 score-k8s_0.19.0_linux_amd64.tar.gz checksums.txt score-k8s
download_checked open-policy-agent/gatekeeper v3.23.1 gator-v3.23.1-linux-amd64.tar.gz sha256sums.txt gator
download_checked kubernetes-sigs/kustomize kustomize/v5.8.2 kustomize_v5.8.2_linux_amd64.tar.gz checksums.txt kustomize
download_checked yannh/kubeconform v0.8.0 kubeconform-linux-amd64.tar.gz CHECKSUMS kubeconform
download_checked rhysd/actionlint v1.7.7 actionlint_1.7.7_linux_amd64.tar.gz actionlint_1.7.7_checksums.txt actionlint

gh release download v0.11.0 --repo koalaman/shellcheck \
  --pattern shellcheck-v0.11.0.linux.x86_64.tar.gz --dir "$work_dir"
printf '%s  %s\n' b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6 \
  "$work_dir/shellcheck-v0.11.0.linux.x86_64.tar.gz" | shasum -a 256 -c -
tar -xzf "$work_dir/shellcheck-v0.11.0.linux.x86_64.tar.gz" -C "$work_dir"
cp "$work_dir/shellcheck-v0.11.0/shellcheck" "$tool_dir/shellcheck"

curl -fsSL --retry 3 -o "$work_dir/helm-v4.3.0-linux-amd64.tar.gz" https://get.helm.sh/helm-v4.3.0-linux-amd64.tar.gz
curl -fsSL --retry 3 -o "$work_dir/helm-v4.3.0-linux-amd64.tar.gz.sha256sum" https://get.helm.sh/helm-v4.3.0-linux-amd64.tar.gz.sha256sum
(cd "$work_dir" && shasum -a 256 -c helm-v4.3.0-linux-amd64.tar.gz.sha256sum)
tar -xzf "$work_dir/helm-v4.3.0-linux-amd64.tar.gz" -C "$work_dir" linux-amd64/helm
cp "$work_dir/linux-amd64/helm" "$tool_dir/helm"

python3 -m venv "$root_dir/.tools/yamllint-venv"
"$root_dir/.tools/yamllint-venv/bin/pip" install --disable-pip-version-check yamllint==1.38.0
ln -sf "$root_dir/.tools/yamllint-venv/bin/yamllint" "$tool_dir/yamllint"
