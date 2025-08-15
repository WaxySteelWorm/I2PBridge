#!/usr/bin/env python3
import sys
import os
import json
import hashlib
from typing import Any, Dict, List, Optional

# Lazy import androguard to allow the script to show a helpful error if missing
try:
	from androguard.core.bytecodes.apk import APK
except Exception as e:
	print(json.dumps({
		"ok": False,
		"error": "Androguard not installed or failed to import",
		"detail": str(e)
	}))
	sys.exit(1)

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


def compute_sha256(file_path: str) -> str:
	sha256 = hashlib.sha256()
	with open(file_path, 'rb') as f:
		for chunk in iter(lambda: f.read(1024 * 1024), b''):
			sha256.update(chunk)
	return sha256.hexdigest()


def get_attr(elem, name: str) -> Optional[str]:
	if elem is None:
		return None
	return elem.get(ANDROID_NS + name)


def parse_manifest(apk: APK) -> Dict[str, Any]:
	# Parse AXML to standard XML and extract attributes in a namespace-aware way
	xml_bytes = apk.get_android_manifest_axml().get_xml()
	try:
		import xml.etree.ElementTree as ET
		root = ET.fromstring(xml_bytes)
	except Exception as exc:
		return {
			"manifest_parse_error": str(exc)
		}

	result: Dict[str, Any] = {}

	# manifest level
	result["package_name"] = root.get("package")
	result["version_code"] = get_attr(root, "versionCode")
	result["version_name"] = get_attr(root, "versionName")

	# uses-sdk
	uses_sdk = root.find("uses-sdk")
	result["min_sdk"] = get_attr(uses_sdk, "minSdkVersion")
	result["target_sdk"] = get_attr(uses_sdk, "targetSdkVersion")

	# application level
	application = root.find("application")
	result["application"] = {
		"debuggable": (get_attr(application, "debuggable") == "true"),
		"allowBackup": get_attr(application, "allowBackup"),
		"usesCleartextTraffic": get_attr(application, "usesCleartextTraffic"),
		"networkSecurityConfig": get_attr(application, "networkSecurityConfig"),
		"requestsLegacyExternalStorage": get_attr(application, "requestLegacyExternalStorage"),
		"backupAgent": get_attr(application, "backupAgent"),
	}

	# Permissions (declared)
	permissions: List[str] = []
	for perm in root.findall("uses-permission"):
		name = get_attr(perm, "name")
		if name:
			permissions.append(name)
	result["permissions"] = sorted(list(set(permissions)))

	# Extract components and their export status
	def collect_components(tag: str) -> List[Dict[str, Any]]:
		items: List[Dict[str, Any]] = []
		for el in root.findall(tag):
			name = get_attr(el, "name")
			exported = get_attr(el, "exported")
			# intent-filters (summarize data schemes/hosts)
			filters: List[Dict[str, Any]] = []
			for ifilter in el.findall("intent-filter"):
				data_items: List[Dict[str, Optional[str]]] = []
				for data in ifilter.findall("data"):
					data_items.append({
						"scheme": get_attr(data, "scheme"),
						"host": get_attr(data, "host"),
						"path": get_attr(data, "path"),
						"mimeType": get_attr(data, "mimeType"),
					})
				filters.append({
					"hasCategoryLAUNCHER": any((c.get(ANDROID_NS + "name") == "android.intent.category.LAUNCHER") for c in ifilter.findall("category")),
					"actions": [get_attr(a, "name") for a in ifilter.findall("action") if get_attr(a, "name")],
					"data": data_items,
				})
			items.append({
				"name": name,
				"exported": exported,
				"intent_filters": filters,
			})
		return items

	result["activities"] = collect_components("activity")
	result["services"] = collect_components("service")
	result["receivers"] = collect_components("receiver")
	result["providers"] = collect_components("provider")

	return result


def get_signing_info(apk: APK) -> Dict[str, Any]:
	info: Dict[str, Any] = {"signers": []}
	try:
		# Try v2/v3 first, then v1 (JAR)
		certs: List[bytes] = []
		try:
			certs.extend(apk.get_certificates_der_v2())
		except Exception:
			pass
		try:
			certs.extend(apk.get_certificates_der_v3())
		except Exception:
			pass
		try:
			certs.extend(apk.get_certificates_der_v1())
		except Exception:
			pass
		seen = set()
		for c in certs:
			if not c:
				continue
			digest = hashlib.sha256(c).hexdigest()
			if digest in seen:
				continue
			seen.add(digest)
			info["signers"].append({
				"sha256": digest
			})
	except Exception as e:
		info["error"] = str(e)
	return info


def main() -> int:
	if len(sys.argv) < 2:
		print(json.dumps({
			"ok": False,
			"error": "Usage: analyze_apk.py /absolute/path/to/app.apk"
		}))
		return 2

	apk_path = sys.argv[1]
	if not os.path.isabs(apk_path):
		apk_path = os.path.abspath(apk_path)
	if not os.path.exists(apk_path):
		print(json.dumps({"ok": False, "error": f"APK not found: {apk_path}"}))
		return 1

	result: Dict[str, Any] = {"ok": True}
	try:
		result["file_path"] = apk_path
		result["file_size_bytes"] = os.path.getsize(apk_path)
		result["sha256"] = compute_sha256(apk_path)

		apk = APK(apk_path)
		result["badging"] = {
			"package_name": apk.package,
			"version_name": apk.get_androidversion_name(),
			"version_code": apk.get_androidversion_code(),
			"min_sdk": apk.get_min_sdk_version(),
			"target_sdk": apk.get_target_sdk_version(),
			"max_sdk": apk.get_max_sdk_version(),
		}
		result["manifest"] = parse_manifest(apk)
		result["permissions_declared"] = sorted(apk.get_permissions())
		result["main_activity"] = apk.get_main_activity()
		result["activities_all"] = sorted(apk.get_activities() or [])
		result["services_all"] = sorted(apk.get_services() or [])
		result["receivers_all"] = sorted(apk.get_receivers() or [])
		result["providers_all"] = sorted(apk.get_providers() or [])
		result["signing"] = get_signing_info(apk)

		# Simple security heuristics
		heuristics: List[Dict[str, Any]] = []
		app_cfg = result.get("manifest", {}).get("application", {})
		if app_cfg.get("debuggable", False):
			heuristics.append({"id": "DBG001", "severity": "medium", "title": "Application is debuggable"})
		allow_backup = app_cfg.get("allowBackup")
		if allow_backup is None or allow_backup == "true":
			heuristics.append({"id": "BK001", "severity": "medium", "title": "allowBackup is enabled or unspecified (defaults true)"})
		uct = app_cfg.get("usesCleartextTraffic")
		if uct is None:
			heuristics.append({"id": "CL001", "severity": "info", "title": "usesCleartextTraffic not explicitly set"})
		elif uct == "true":
			heuristics.append({"id": "CL002", "severity": "high", "title": "Cleartext traffic is allowed for the application"})
		nsc = app_cfg.get("networkSecurityConfig")
		if nsc:
			heuristics.append({"id": "NSC001", "severity": "info", "title": f"Custom networkSecurityConfig present: {nsc}"})
		result["heuristics"] = heuristics

		print(json.dumps(result, indent=2))
		return 0
	except Exception as e:
		print(json.dumps({
			"ok": False,
			"error": str(e)
		}))
		return 1


if __name__ == "__main__":
	sys.exit(main())