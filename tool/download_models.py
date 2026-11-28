import json
import os
import sys
import tarfile
import time
import urllib.request

TARGET_REL_DIR = os.path.join("android", "ai_models", "src", "main", "assets", "models")

MODELS = [
    # Multilingual SenseVoice Small (INT8) ASR
    {
        "url": "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx",
        "dest": "asr/sense-voice.int8.onnx",
        "desc": "SenseVoice Small INT8 ASR Model",
    },
    {
        "url": "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt",
        "dest": "asr/sense-voice-tokens.txt",
        "desc": "SenseVoice Multilingual Tokens",
    },
    # Silero VAD
    {
        "url": "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx",
        "dest": "silero_vad.onnx",
        "desc": "Silero VAD ONNX Model",
    },
    # MarianMT NMT English -> Japanese
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/onnx/encoder_model_quantized.onnx",
        "dest": "nmt_en_ja/encoder_model_quantized.onnx",
        "desc": "MarianMT EN->JA Quantized Encoder",
    },
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/onnx/decoder_model_quantized.onnx",
        "dest": "nmt_en_ja/decoder_model_quantized.onnx",
        "desc": "MarianMT EN->JA Quantized Decoder",
    },
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/source.spm",
        "dest": "nmt_en_ja/source.spm",
        "desc": "MarianMT EN->JA Source SPM",
    },
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/target.spm",
        "dest": "nmt_en_ja/target.spm",
        "desc": "MarianMT EN->JA Target SPM",
    },
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/vocab.json",
        "dest": "nmt_en_ja/vocab.json",
        "desc": "MarianMT EN->JA Vocabulary",
    },
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/tokenizer_config.json",
        "dest": "nmt_en_ja/tokenizer_config.json",
        "desc": "MarianMT EN->JA Tokenizer Config",
    },
    # MarianMT NMT Japanese -> English
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/onnx/encoder_model_quantized.onnx",
        "dest": "nmt_ja_en/encoder_model_quantized.onnx",
        "desc": "MarianMT JA->EN Quantized Encoder",
    },
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/onnx/decoder_model_quantized.onnx",
        "dest": "nmt_ja_en/decoder_model_quantized.onnx",
        "desc": "MarianMT JA->EN Quantized Decoder",
    },
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/source.spm",
        "dest": "nmt_ja_en/source.spm",
        "desc": "MarianMT JA->EN Source SPM",
    },
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/target.spm",
        "dest": "nmt_ja_en/target.spm",
        "desc": "MarianMT JA->EN Target SPM",
    },
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/vocab.json",
        "dest": "nmt_ja_en/vocab.json",
        "desc": "MarianMT JA->EN Vocabulary",
    },
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/tokenizer_config.json",
        "dest": "nmt_ja_en/tokenizer_config.json",
        "desc": "MarianMT JA->EN Tokenizer Config",
    },
    # Sherpa Piper English TTS
    {
        "url": "https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/en_US-lessac-medium.onnx",
        "dest": "tts_en/en_US-lessac-medium.onnx",
        "desc": "Piper English VITS Model",
    },
    {
        "url": "https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/tokens.txt",
        "dest": "tts_en/tokens.txt",
        "desc": "Piper English Tokens",
    },
    {
        "url": "https://huggingface.co/csukuangfj/vits-melo-tts-en/resolve/main/lexicon.txt",
        "dest": "tts_en/lexicon.txt",
        "desc": "English Lexicon Dictionary",
    },
    # MeloTTS Japanese TTS
    {
        "url": "https://huggingface.co/qqder/vits-melo-tts-ja/resolve/main/model.onnx",
        "dest": "tts_ja/model (1).onnx",
        "desc": "MeloTTS Japanese VITS Model",
    },
    {
        "url": "https://huggingface.co/qqder/vits-melo-tts-ja/resolve/main/tokens.txt",
        "dest": "tts_ja/tokens (2).txt",
        "desc": "MeloTTS Japanese Tokens",
    },
    {
        "url": "https://huggingface.co/qqder/vits-melo-tts-ja/resolve/main/lexicon.txt",
        "dest": "tts_ja/lexicon.txt",
        "desc": "MeloTTS Japanese Lexicon",
    },
]

ESPEAK_ARCHIVE_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/espeak-ng-data.tar.bz2"
)
ESPEAK_HF_TREE_URL = (
    "https://huggingface.co/api/models/csukuangfj/vits-piper-en_US-lessac-medium/tree/main/espeak-ng-data?recursive=true"
)
ESPEAK_HF_RAW_BASE = (
    "https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/"
)


def download_file(url: str, dest_path: str, desc: str) -> None:
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)

    headers = {"User-Agent": "Mozilla/5.0"}
    req = urllib.request.Request(url, headers=headers)

    remote_size = None
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            content_length = resp.headers.get("Content-Length")
            if content_length:
                remote_size = int(content_length)
    except Exception as e:
        print(f"  [WARN] Failed to get content-length for {desc}: {e}")

    if os.path.exists(dest_path):
        local_size = os.path.getsize(dest_path)
        if remote_size is not None and local_size == remote_size:
            print(f"  [SKIP] {desc} already downloaded ({local_size / (1024 * 1024):.2f} MB).")
            return
        if remote_size is None and local_size > 0:
            print(f"  [SKIP] {desc} already exists ({local_size / (1024 * 1024):.2f} MB).")
            return

    tmp_path = dest_path + ".tmp"
    print(f"  [DOWNLOAD] {desc} -> {dest_path}")
    if remote_size:
        print(f"             Size: {remote_size / (1024 * 1024):.2f} MB")

    start_time = time.time()
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp, open(tmp_path, "wb") as out_file:
        downloaded = 0
        last_log = time.time()
        while True:
            chunk = resp.read(256 * 1024)
            if not chunk:
                break
            out_file.write(chunk)
            downloaded += len(chunk)
            now = time.time()
            if now - last_log > 1.0 or (remote_size and downloaded >= remote_size):
                pct = f"({(downloaded / remote_size * 100):.1f}%)" if remote_size else ""
                mb = downloaded / (1024 * 1024)
                speed = mb / max(0.1, now - start_time)
                sys.stdout.write(f"\r             Progress: {mb:.2f} MB {pct} [{speed:.2f} MB/s]")
                sys.stdout.flush()
                last_log = now

    print()
    if os.path.exists(dest_path):
        os.remove(dest_path)
    os.rename(tmp_path, dest_path)
    total_time = time.time() - start_time
    final_size = os.path.getsize(dest_path)
    print(f"  [COMPLETE] {desc} in {total_time:.1f}s ({final_size / (1024 * 1024):.2f} MB)\n")


def ensure_espeak_ng_data(target_models_dir: str) -> None:
    tts_en_dir = os.path.join(target_models_dir, "tts_en")
    en_dict = os.path.join(tts_en_dir, "espeak-ng-data", "en_dict")
    if os.path.exists(en_dict) and os.path.getsize(en_dict) > 100 * 1024:
        print("  [SKIP] espeak-ng-data already present.")
        return

    os.makedirs(tts_en_dir, exist_ok=True)
    archive_path = os.path.join(tts_en_dir, "espeak-ng-data.tar.bz2")
    try:
        download_file(ESPEAK_ARCHIVE_URL, archive_path, "espeak-ng-data archive")
        with tarfile.open(archive_path, "r:bz2") as tf:
            tf.extractall(tts_en_dir)
        os.remove(archive_path)
        if os.path.exists(en_dict) and os.path.getsize(en_dict) > 100 * 1024:
            print("  [COMPLETE] Extracted espeak-ng-data.")
            return
    except Exception as e:
        print(f"  [WARN] GitHub espeak-ng-data archive failed ({e}); falling back to HuggingFace tree...")
        if os.path.exists(archive_path):
            os.remove(archive_path)

    req = urllib.request.Request(ESPEAK_HF_TREE_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        entries = json.loads(resp.read().decode("utf-8"))
    files = [entry["path"] for entry in entries if entry.get("type") == "file"]
    print(f"  [DOWNLOAD] Fetching {len(files)} espeak-ng-data files from HuggingFace...")
    for idx, rel in enumerate(files, 1):
        dest = os.path.join(tts_en_dir, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if os.path.exists(dest) and os.path.getsize(dest) > 0:
            continue
        file_req = urllib.request.Request(
            ESPEAK_HF_RAW_BASE + rel, headers={"User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(file_req, timeout=30) as f_resp, open(dest, "wb") as out_f:
            out_f.write(f_resp.read())
        if idx % 50 == 0 or idx == len(files):
            print(f"             Fetched {idx}/{len(files)} espeak-ng-data files")


def main():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    target_models_dir = os.path.join(base_dir, TARGET_REL_DIR)
    print("=" * 60)
    print("EdgeTranslator AI Pack Model Downloader")
    print(f"Target Directory: {target_models_dir}")
    print("=" * 60)

    total_models = len(MODELS)
    for idx, item in enumerate(MODELS, 1):
        dest_path = os.path.join(target_models_dir, item["dest"].replace("/", os.sep))
        print(f"[{idx}/{total_models}] {item['desc']}...")
        download_file(item["url"], dest_path, item["desc"])

    print("[+] Checking espeak-ng-data for English Piper TTS...")
    ensure_espeak_ng_data(target_models_dir)

    print("=" * 60)
    print("All AI pack models successfully downloaded and verified!")
    print("=" * 60)


if __name__ == "__main__":
    main()
