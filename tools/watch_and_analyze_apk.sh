#!/usr/bin/env bash
set -euo pipefail
APK_PATH="/workspace/artifacts/app-release.apk"
VENV_DIR="/workspace/.venvs/apksec"
OUT_JSON="/workspace/artifacts/apk_analysis.json"

mkdir -p "$(dirname "$APK_PATH")" "$(dirname "$OUT_JSON")" "$VENV_DIR"

if [ ! -d "$VENV_DIR/bin" ]; then
	python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
python -m pip install --upgrade --quiet pip
python -m pip install --quiet "androguard>=3.4.0"

echo "[watch] Waiting for APK at $APK_PATH ..."
while [ ! -f "$APK_PATH" ]; do
	sleep 2
	date '+[watch] %Y-%m-%d %H:%M:%S still waiting...'
	done

echo "[watch] APK detected. Starting analysis..."
python /workspace/tools/analyze_apk.py "$APK_PATH" > "$OUT_JSON" || {
	echo "[watch] Analysis failed" >&2
	exit 1
}

echo "[watch] Analysis complete: $OUT_JSON"