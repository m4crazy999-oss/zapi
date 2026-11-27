#!/usr/bin/env python3
"""
Empacota todo o projeto Flutter/Android (zapi/) em um arquivo .zip limpo na raiz
do repositório, pronto para enviar ao GitHub e compilar o APK via GitHub Actions.
"""

import argparse
import base64
import datetime
import hashlib
import json
import os
import pathlib
import zipfile

EXCLUDE_DIRS = {
    ".dart_tool",
    ".gradle",
    "build",
    "node_modules",
    "__pycache__",
    ".idea",
    "zapi-server",
}

EXCLUDE_FILES = {
    ".DS_Store",
    "Thumbs.db",
    "google-services.json",
    "key.properties",
    "zapi-release.jks",
    "serviceAccountKey.json",
    ".env",
}

README_CONTENT = """Zapi Android — Pacote pronto para GitHub Actions -> APK

Como gerar seu APK no GitHub:
1. Extraia TODO o conteudo deste ZIP na raiz do seu repositorio GitHub
   (a pasta .github/workflows/build-apk.yml precisa ficar na raiz).
2. No repositorio do GitHub:
   - Settings > Secrets and variables > Actions: cadastre os 5 Secrets
     (GOOGLE_SERVICES_JSON_BASE64, ANDROID_KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD).
   - Settings > Actions > General > Workflow permissions: marque "Read and write permissions".
3. Envie os arquivos para a branch "main" (git push origin main).
4. Acompanhe em Actions > "Build Zapi Android APK" e baixe o APK em Artifacts ou Releases.
"""


def should_skip(rel_path: pathlib.PurePosixPath) -> bool:
    for part in rel_path.parts:
        if part in EXCLUDE_DIRS:
            return True
    if rel_path.name in EXCLUDE_FILES or rel_path.name.startswith(".env."):
        return True
    if rel_path.name.startswith("serviceAccount") and rel_path.suffix == ".json":
        return True
    if rel_path.suffix in {".jks", ".keystore", ".apk", ".aab", ".p12", ".pem"}:
        return True
    return False


def build_zip(version_tag: str) -> None:
    repo_root = pathlib.Path(__file__).resolve().parents[2]
    zapi_dir = repo_root / "zapi"
    downloads_dir = repo_root / "public" / "downloads"
    downloads_dir.mkdir(parents=True, exist_ok=True)

    # Limpa zips antigos da pasta public/downloads para manter somente a versão atual.
    for old_zip in downloads_dir.glob("zapi-*.zip"):
        old_zip.unlink()

    filename = f"zapi-{version_tag}.zip"
    zip_path = downloads_dir / filename

    included_files: list[str] = []
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for current_root, dirs, files in os.walk(zapi_dir):
            dirs[:] = sorted(d for d in dirs if d not in EXCLUDE_DIRS)
            for fname in sorted(files):
                full_path = pathlib.Path(current_root) / fname
                rel = full_path.relative_to(zapi_dir).as_posix()
                posix_rel = pathlib.PurePosixPath(rel)
                if should_skip(posix_rel):
                    continue
                zf.write(full_path, arcname=rel)
                included_files.append(rel)

        zf.writestr("README_GITHUB_APK.txt", README_CONTENT)
        included_files.append("README_GITHUB_APK.txt")

    zip_bytes = zip_path.read_bytes()
    size_bytes = len(zip_bytes)
    sha256_hex = hashlib.sha256(zip_bytes).hexdigest()
    b64_payload = base64.b64encode(zip_bytes).decode("ascii")

    metadata = {
        "version": version_tag,
        "fileName": filename,
        "downloadUrl": f"/downloads/{filename}",
        "sizeBytes": size_bytes,
        "fileCount": len(included_files),
        "sha256": sha256_hex,
        "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }

    release_json = downloads_dir / "release.json"
    release_json.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    # Espelha os metadados também para import estático no TypeScript do painel web.
    src_data_dir = repo_root / "src" / "data"
    src_data_dir.mkdir(parents=True, exist_ok=True)

    src_release = src_data_dir / "releaseMeta.json"
    src_release.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    # Embute os bytes exatos do ZIP no bundle cliente para download via Blob sem passar pelo proxy de cookies.
    src_zip_data = src_data_dir / "releaseZipData.ts"
    src_zip_data.write_text(
        "// Arquivo gerado automaticamente por zapi/scripts/build_release_zip.py.\n"
        f"export const RELEASE_ZIP_FILE_NAME = {json.dumps(filename)};\n"
        f"export const RELEASE_ZIP_SIZE_BYTES = {size_bytes};\n"
        f"export const RELEASE_ZIP_BASE64 = {json.dumps(b64_payload)};\n",
        encoding="utf-8",
    )

    print(
        f"ZIP gerado: {zip_path} ({size_bytes} bytes, {len(included_files)} arquivos, sha256={sha256_hex[:12]})"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Empacotar projeto Zapi em ZIP para GitHub Actions")
    parser.add_argument("--version", default="etapa-6", help="Identificador da versão (ex.: etapa-6)")
    args = parser.parse_args()
    build_zip(args.version)


if __name__ == "__main__":
    main()
