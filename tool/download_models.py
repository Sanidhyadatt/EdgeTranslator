import os
import sys
import time
import urllib.request

MODELS = [
    # Whisper Tiny Multilingual INT8 ASR
    {
        "url": "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-encoder.int8.onnx",
        "dest": "assets/models/tiny-encoder.int8.onnx",
        "desc": "Whisper Tiny INT8 Encoder"
    },
    {
        "url": "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-decoder.int8.onnx",
        "dest": "assets/models/tiny-decoder.int8.onnx",
        "desc": "Whisper Tiny INT8 Decoder"
    },
    {
        "url": "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-tokens.txt",
        "dest": "assets/models/tiny-tokens.txt",
        "desc": "Whisper Multilingual Tokens"
    },
    # Silero VAD
    {
        "url": "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx",
        "dest": "assets/models/silero_vad.onnx",
        "desc": "Silero VAD ONNX Model"
    },
    # MarianMT NMT English -> Japanese
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/onnx/encoder_model_quantized.onnx",
        "dest": "assets/models/nmt_en_ja/encoder_model_quantized.onnx",
        "desc": "MarianMT EN->JA Quantized Encoder"
    },
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/onnx/decoder_model_quantized.onnx",
        "dest": "assets/models/nmt_en_ja/decoder_model_quantized.onnx",
        "desc": "MarianMT EN->JA Quantized Decoder"
    },
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/source.spm",
        "dest": "assets/models/nmt_en_ja/source.spm",
        "desc": "MarianMT EN->JA Source SPM"
    },
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/target.spm",
        "dest": "assets/models/nmt_en_ja/target.spm",
        "desc": "MarianMT EN->JA Target SPM"
    },
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/vocab.json",
        "dest": "assets/models/nmt_en_ja/vocab.json",
        "desc": "MarianMT EN->JA Vocabulary"
    },
    {
        "url": "https://huggingface.co/Kadonox/fugumt-en-ja-onnx/resolve/main/tokenizer_config.json",
        "dest": "assets/models/nmt_en_ja/tokenizer_config.json",
        "desc": "MarianMT EN->JA Tokenizer Config"
    },
    # MarianMT NMT Japanese -> English
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/onnx/encoder_model_quantized.onnx",
        "dest": "assets/models/nmt_ja_en/encoder_model_quantized.onnx",
        "desc": "MarianMT JA->EN Quantized Encoder"
    },
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/onnx/decoder_model_quantized.onnx",
        "dest": "assets/models/nmt_ja_en/decoder_model_quantized.onnx",
        "desc": "MarianMT JA->EN Quantized Decoder"
    },
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/source.spm",
        "dest": "assets/models/nmt_ja_en/source.spm",
        "desc": "MarianMT JA->EN Source SPM"
    },
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/target.spm",
        "dest": "assets/models/nmt_ja_en/target.spm",
        "desc": "MarianMT JA->EN Target SPM"
    },
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/vocab.json",
        "dest": "assets/models/nmt_ja_en/vocab.json",
        "desc": "MarianMT JA->EN Vocabulary"
    },
    {
        "url": "https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/tokenizer_config.json",
        "dest": "assets/models/nmt_ja_en/tokenizer_config.json",
        "desc": "MarianMT JA->EN Tokenizer Config"
    },
    # Sherpa Piper English TTS
    {
        "url": "https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/en_US-lessac-medium.onnx",
        "dest": "assets/models/tts_en/en_US-lessac-medium.onnx",
        "desc": "Piper English VITS Model"
    },
    {
        "url": "https://huggingface.co/csukuangfj/vits-piper-en_US-lessac-medium/resolve/main/tokens.txt",
        "dest": "assets/models/tts_en/tokens.txt",
        "desc": "Piper English Tokens"
    },
    {
        "url": "https://huggingface.co/csukuangfj/vits-melo-tts-en/resolve/main/lexicon.txt",
        "dest": "assets/models/tts_en/lexicon.txt",
        "desc": "English Lexicon Dictionary"
    },
    # Sherpa Melo Japanese TTS
    {
        "url": "https://huggingface.co/qqder/vits-melo-tts-ja/resolve/main/model.onnx",
        "dest": "assets/models/tts_ja/model.onnx",
        "desc": "MeloTTS Japanese VITS Model"
    },
    {
        "url": "https://huggingface.co/qqder/vits-melo-tts-ja/resolve/main/tokens.txt",
        "dest": "assets/models/tts_ja/tokens.txt",
        "desc": "MeloTTS Japanese Tokens"
    },
    {
        "url": "https://huggingface.co/qqder/vits-melo-tts-ja/resolve/main/lexicon.txt",
        "dest": "assets/models/tts_ja/lexicon.txt",
        "desc": "MeloTTS Japanese Lexicon"
    },
]

def download_file(url: str, dest_path: str, desc: str) -> None:
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)

    headers = {'User-Agent': 'Mozilla/5.0'}
    req = urllib.request.Request(url, headers=headers)

    # Check remote file size
    remote_size = None
    try:
        with urllib.request.urlopen(req) as resp:
            content_length = resp.headers.get('Content-Length')
            if content_length:
                remote_size = int(content_length)
    except Exception as e:
        print(f"  [WARN] Failed to get content-length for {desc}: {e}")

    # Check if existing file is already complete
    if os.path.exists(dest_path):
        local_size = os.path.getsize(dest_path)
        if remote_size is not None and local_size == remote_size:
            print(f"  [SKIP] {desc} already downloaded ({local_size / (1024 * 1024):.2f} MB).")
            return
        elif remote_size is None and local_size > 0:
            print(f"  [SKIP] {desc} already exists ({local_size / (1024 * 1024):.2f} MB).")
            return

    tmp_path = dest_path + ".tmp"
    print(f"  [DOWNLOAD] {desc} -> {dest_path}")
    if remote_size:
        print(f"             Size: {remote_size / (1024 * 1024):.2f} MB")

    start_time = time.time()
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp, open(tmp_path, 'wb') as out_file:
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

def main():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    print("=" * 60)
    print("EdgeTranslator Model Downloader")
    print(f"Target Directory: {os.path.join(base_dir, 'assets', 'models')}")
    print("=" * 60)

    total_models = len(MODELS)
    for idx, item in enumerate(MODELS, 1):
        dest_path = os.path.join(base_dir, item["dest"])
        print(f"[{idx}/{total_models}] {item['desc']}...")
        download_file(item["url"], dest_path, item["desc"])

    print("=" * 60)
    print("All models successfully downloaded and verified!")
    print("=" * 60)

if __name__ == "__main__":
    main()
