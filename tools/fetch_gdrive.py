#!/usr/bin/env python3
import sys
import os
from typing import List, Tuple


def parse_args(argv: List[str]) -> List[Tuple[str, str]]:
	if len(argv) < 3 or len(argv) % 2 == 0:
		print("Usage: fetch_gdrive.py <url_or_id> <output_path> [<url_or_id> <output_path> ...]", file=sys.stderr)
		sys.exit(2)
	pairs: List[Tuple[str, str]] = []
	args = argv[1:]
	for i in range(0, len(args), 2):
		pairs.append((args[i], args[i+1]))
	return pairs


def main() -> int:
	pairs = parse_args(sys.argv)
	try:
		import gdown
	except Exception as e:
		print(f"gdown is not installed: {e}", file=sys.stderr)
		return 1

	os.makedirs('/workspace/artifacts', exist_ok=True)
	status = 0
	for src, out_path in pairs:
		try:
			# Allow using bare IDs or full URLs
			url = src
			if '/' not in src and len(src) >= 20:
				url = f"https://drive.google.com/uc?id={src}"
			print(f"[gdown] Downloading {url} -> {out_path}")
			gdown.download(url, out_path, quiet=False, fuzzy=True)
		except Exception as e:
			print(f"[gdown] Failed: {src} -> {out_path}: {e}", file=sys.stderr)
			status = 1
	return status


if __name__ == '__main__':
	sys.exit(main())