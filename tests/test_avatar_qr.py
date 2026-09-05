"""Unit tests for avatar_qr module — Avatar QR creation & Substrate Security Audit."""
import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw

# Add project root to sys.path
sys.path.insert(0, str(Path(__file__).parent.parent))

from avatar_qr import generate_avatar_qr, audit_substrate, sanitize_substrate


def test_generate_avatar_qr_without_avatar(tmp_path):
    output_png = tmp_path / "test_qr.png"
    result_path = generate_avatar_qr(
        url="https://github.com/rctruta/ai-agent-utils",
        output_path=str(output_png)
    )
    assert Path(result_path).exists()
    img = Image.open(result_path)
    assert img.size[0] > 100
    assert img.size[1] > 100


def test_generate_avatar_qr_with_avatar(tmp_path):
    avatar_png = tmp_path / "avatar.png"
    # Create simple 100x100 RGB avatar
    avatar_img = Image.new("RGB", (100, 100), color=(15, 23, 42))
    draw = ImageDraw.Draw(avatar_img)
    draw.rectangle([25, 25, 75, 75], fill=(255, 255, 255))
    avatar_img.save(avatar_png)

    output_png = tmp_path / "test_avatar_qr.png"
    result_path = generate_avatar_qr(
        url="https://github.com/rctruta/substrate-steganography",
        output_path=str(output_png),
        avatar_path=str(avatar_png)
    )
    assert Path(result_path).exists()


def test_audit_substrate_clean_image(tmp_path):
    clean_png = tmp_path / "clean.png"
    img = Image.new("RGB", (200, 200), color=(240, 240, 240))
    img.save(clean_png)

    report = audit_substrate(str(clean_png))
    assert report["anomaly_score"] <= 0.5
    assert report["status"] == "CLEAN_SUBSTRATE"


def test_sanitize_substrate(tmp_path):
    input_png = tmp_path / "noisy.png"
    img = Image.new("RGB", (100, 100), color=(100, 100, 100))
    img.save(input_png)

    output_png = tmp_path / "sanitized.png"
    result_path = sanitize_substrate(str(input_png), str(output_png))
    assert Path(result_path).exists()
