"""Create a source/binary research bundle plus a SHA-256 inventory. No trading actions."""
from pathlib import Path
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "Biltech_VolumeProfile_EA_research_v1.zip"
MANIFEST = ROOT / "logs" / "SHA256SUMS.txt"

def main():
    files = sorted(p for p in ROOT.rglob("*") if p.is_file()
                   and p != ARCHIVE and p != MANIFEST
                   and not {".git", "__pycache__", ".native-runtime"}.intersection(p.relative_to(ROOT).parts)
                   and p.suffix not in {".pyc", ".zip"})
    lines = [f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(ROOT).as_posix()}" for p in files]
    MANIFEST.write_text("\n".join(lines)+"\n",encoding="utf-8")
    with zipfile.ZipFile(ARCHIVE,"w",compression=zipfile.ZIP_DEFLATED) as output:
        for path in files+[MANIFEST]:
            output.write(path, "Biltech_VolumeProfile_EA/"+path.relative_to(ROOT).as_posix())
    # Reopen only after the writer has flushed and finalized its directory.
    with zipfile.ZipFile(ARCHIVE,"r") as check:
        assert check.testzip() is None, "Archive integrity check failed"
    print(f"Bundle: {ARCHIVE.name}; {len(files)+1} files; {ARCHIVE.stat().st_size} bytes")
    print(f"SHA256: {hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()}")

if __name__ == "__main__":
    main()
