"""DEMO ONLY: research/educational ML description of a case's CT slices via the Hugging Face
Inference Providers router (OpenAI-compatible chat completions). Not a diagnosis, no prognosis.

Renders the same slices the app shows (axial and coronal through the first finding, or through
the volume centre), sends them to a vision-language model, and caches the answer to
App/Cases/<case>/analysis.json. The app reads that cache, so the demo still works offline.

Usage:
  HF_TOKEN=... uv run --python 3.12 --with numpy --with pillow --with requests \
      python scripts/ml/hf_analyze.py head [--model Qwen/Qwen3-VL-235B-A22B-Instruct] [--dry-run]
The token comes from $HF_TOKEN or from HF_TOKEN=... in ./.env (gitignored). It is never written anywhere.
"""
import argparse, base64, io, json, os, sys, time
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ROUTER = "https://router.huggingface.co/v1/chat/completions"
# Tried in order; all are ungated and were live on HF Inference Providers on 2026-09-26.
MODELS = ["Qwen/Qwen3-VL-235B-A22B-Instruct", "Qwen/Qwen2.5-VL-72B-Instruct", "Qwen/Qwen2.5-VL-7B-Instruct"]

PROMPT = """You are helping build an EDUCATIONAL anatomy demo from public, de-identified research CT data.
Images: {views}. Case: {title}. Window: level {level} HU, width {width} HU. {hint}
Describe what is visible for a lay audience. Do not diagnose, estimate prognosis, or recommend treatment.
Reply with ONLY a JSON object:
{{"structures": [up to 6 anatomical structures you can see],
  "observations": [2-4 short plain-language sentences about what stands out, hedged ("appears", "may")],
  "image_quality": "one short phrase",
  "confidence": "low|medium|high",
  "caveat": "one sentence saying this is an automated research description, not a diagnosis"}}"""


def token():
    if os.environ.get("HF_TOKEN"):
        return os.environ["HF_TOKEN"]
    env = ROOT / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if line.startswith("HF_TOKEN="):
                return line.split("=", 1)[1].strip().strip('"')
    sys.exit("No HF token: set HF_TOKEN or add HF_TOKEN=... to .env (needs 'Make calls to Inference Providers').")


def load(case):
    d = ROOT / "App/Cases" / case
    meta = json.loads((d / "meta.json").read_text())
    nx, ny, nz = meta["dims"]
    ct = np.fromfile(d / "ct.raw", dtype="<i2").reshape(nz, ny, nx)
    findings = json.loads((d / "findings.json").read_text())
    return d, meta, ct, findings


def window_png(img2d, level, width, flip_lr=True):
    """HU slice -> 8-bit PNG. Radiological convention: patient right on the image left
    (RAS +x = right, so flip x). Rows are flipped so anterior/superior is up."""
    lo = level - width / 2
    a = np.clip((img2d.astype(np.float32) - lo) / width, 0, 1)
    a = np.flipud(a)
    if flip_lr:
        a = np.fliplr(a)
    im = Image.fromarray((a * 255).astype(np.uint8))
    im = im.resize((max(256, im.width * 2), max(256, im.height * 2)), Image.BILINEAR)
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return buf.getvalue()


def render(case, window=None, roi=False):
    d, meta, ct, findings = load(case)
    presets = meta["window_presets"]
    level, width = window or presets.get("brain" if case == "head" else "density" if "density" in presets else "soft")
    nz, ny, nx = ct.shape
    if findings:
        c = np.array(findings[0]["center_mm"], float)
        ijk = np.rint((c - np.array(meta["origin_mm"])) / np.array(meta["spacing_mm"])).astype(int)
        i, j, k = np.clip(ijk, 0, [nx - 1, ny - 1, nz - 1])
        title = f'{case} ({findings[0]["title"]} is annotated in the dataset)'
    else:
        i, j, k = nx // 2, ny // 2, nz // 2
        title = case
    axial = window_png(ct[k, :, :], level, width)    # x across, y (anterior) up
    coronal = window_png(ct[:, j, :], level, width)  # x across, z (superior) up
    views = {"axial": axial, "coronal": coronal}
    if roi and findings:
        # Close-up of the annotated region: tells the model WHERE to look, not WHAT is there.
        half = int(max(30, 1.6 * findings[0]["radius_mm"]) / meta["spacing_mm"][0])
        y0, y1 = max(0, j - half), min(ny, j + half)
        x0, x1 = max(0, i - half), min(nx, i + half)
        views["axial close-up of the highlighted region"] = window_png(ct[k, y0:y1, x0:x1], level, width)
    return views, title, level, width, findings


def call(model, pngs, title, level, width, hint, tok):
    content = [{"type": "text", "text": PROMPT.format(views=", ".join(pngs), title=title, level=level, width=width, hint=hint)}]
    for png in pngs.values():
        content.append({"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(png).decode()}})
    import requests
    r = requests.post(ROUTER, headers={"Authorization": f"Bearer {tok}"}, timeout=180,
                      json={"model": model, "messages": [{"role": "user", "content": content}],
                            "max_tokens": 600, "temperature": 0.2})
    if r.status_code != 200:
        raise RuntimeError(f"{model}: HTTP {r.status_code} {r.text[:300]}")
    text = r.json()["choices"][0]["message"]["content"]
    start, end = text.find("{"), text.rfind("}")
    return json.loads(text[start:end + 1]), text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case")
    ap.add_argument("--model")
    ap.add_argument("--dry-run", action="store_true", help="render slices to build/ml/ and stop")
    ap.add_argument("--window", help="level,width in HU, e.g. 75,215 (subdural window)")
    ap.add_argument("--roi", action="store_true", help="add a close-up of the annotated region (location only)")
    ap.add_argument("--blind", action="store_true", help="don't tell the model what the dataset annotates (honest test)")
    a = ap.parse_args()
    pngs, title, level, width, findings = render(a.case, [float(x) for x in a.window.split(',')] if a.window else None, a.roi)
    out = ROOT / "build/ml"
    out.mkdir(parents=True, exist_ok=True)
    for name, png in pngs.items():
        (out / f"{a.case}_{name}.png").write_bytes(png)
    if a.dry_run:
        print("rendered", [str(out / f"{a.case}_{n}.png") for n in pngs])
        return
    hint = "The dataset annotates one region; you may mention where the image looks abnormal, hedged." if findings else ""
    if a.blind:
        title, hint = a.case, ("The third image is a close-up of a region researchers highlighted; describe how it compares with nearby tissue. " if a.roi else "") + "If anything looks unusual, you may mention it, hedged."
    tok = token()
    errors = []
    for model in ([a.model] if a.model else MODELS):
        try:
            t0 = time.time()
            result, raw = call(model, pngs, title, level, width, hint, tok)
            record = {"model": model, "provider_router": ROUTER, "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                      "latency_s": round(time.time() - t0, 1), "views": list(pngs), "window": [level, width], "blind": a.blind, "roi": a.roi,
                      "label": "Automated research description — not a diagnosis", "result": result}
            (ROOT / "App/Cases" / a.case / "analysis.json").write_text(json.dumps(record, indent=2) + "\n")
            print(json.dumps(record, indent=2))
            return
        except Exception as e:  # try the next model
            errors.append(str(e)[:300])
            print("fallback:", errors[-1], file=sys.stderr)
    sys.exit("all models failed:\n" + "\n".join(errors))


if __name__ == "__main__":
    main()
