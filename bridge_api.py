import argparse
import os
import shutil
import time
import uuid
from typing import Optional

import scipy.io.wavfile
import torch
from fastapi import BackgroundTasks, FastAPI, Form, Request
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

from pocket_tts import TTSModel
from voice_management import delete_voice_file, normalize_voice_id, voice_path

app = FastAPI()
# Configuration
PORT = 8020
SPEAKER_DIR = "./speakers"
os.makedirs(SPEAKER_DIR, exist_ok=True)
AVAILABLE_MODELS = [
    ("english", "English (alias for english_2026-04, default)"),
    ("english_2026-04", "English improved — better short sentences & voice cloning. 6 layers."),
    ("english_2026-01", "English original model. 6 layers."),
    ("italian", "Italian distilled. 6 layers."),
    ("italian_24l", "Italian undistilled. 24 layers."),
    ("german", "German distilled. 6 layers."),
    ("german_24l", "German undistilled. 24 layers."),
    ("spanish", "Spanish distilled. 6 layers."),
    ("spanish_24l", "Spanish undistilled. 24 layers."),
    ("portuguese", "Portuguese distilled. 6 layers."),
    ("portuguese_24l", "Portuguese undistilled. 24 layers."),
    ("french_24l", "French undistilled. 24 layers."),
]

parser = argparse.ArgumentParser(description="Pocket TTS Bridge API")
parser.add_argument(
    "--device", type=str, default="cpu", help="Device to run the model on (cpu, cuda, cuda:0, etc.)"
)
parser.add_argument(
    "--language", type=str, default=None, help="Language/model to load. See --list-models."
)
parser.add_argument(
    "--quantize",
    action="store_true",
    help="Apply dynamic int8 quantization (~30%% faster on CPU, recommended for 24-layer models)",
)
parser.add_argument(
    "--list-models", action="store_true", help="Print all available models/languages and exit"
)
parser.add_argument("--list-devices", action="store_true", help="Print available devices and exit")
args, _ = parser.parse_known_args()

if args.list_models:
    print("\nAvailable models (use with --language):\n")
    for name, desc in AVAILABLE_MODELS:
        print(f"  {name:<20} {desc}")
    print()
    raise SystemExit(0)

if args.list_devices:
    print("\nAvailable devices:\n")
    print(
        f"  {'cpu':<20} CPU ({os.cpu_count()} hardware threads, torch limited to {torch.get_num_threads()} for inference)"
    )
    if torch.cuda.is_available():
        for i in range(torch.cuda.device_count()):
            props = torch.cuda.get_device_properties(i)
            print(
                f"  {'cuda:' + str(i):<20} {props.name} ({props.total_memory // 1024**2} MB VRAM)"
            )
    else:
        print("  (no CUDA devices available)")
    print()
    raise SystemExit(0)

DEVICE = args.device
LANGUAGE = args.language
QUANTIZE = args.quantize

print("\n" + "=" * 60)
print(" POCKET TTS BRIDGE")
print(" Original code by Gestel. (thank you very much)")
print("=" * 60 + "\n")
if DEVICE.startswith("cuda"):
    if torch.cuda.is_available():
        idx = torch.device(DEVICE).index or 0
        print(f" Device  : {DEVICE} ({torch.cuda.get_device_name(idx)})")
        print(f" VRAM    : {torch.cuda.get_device_properties(idx).total_memory // 1024**2} MB")
    else:
        print(f" Device  : {DEVICE} requested but CUDA is not available — falling back to CPU")
        DEVICE = "cpu"
else:
    print(f" Device  : {DEVICE} ({torch.get_num_threads()} threads)")
print(f" Language: {LANGUAGE or 'english (default)'}")
print(f" Quantize: {QUANTIZE}")

# Initialize Model
model = TTSModel.load_model(device=DEVICE, language=LANGUAGE, quantize=QUANTIZE)
current_language = LANGUAGE  # tracks what's currently loaded
voice_cache = {}

# Maps common language names to model identifiers
LANGUAGE_TO_MODEL = {
    "english": "english",
    "en": "english",
    "italian": "italian",
    "it": "italian",
    "german": "german",
    "de": "german",
    "spanish": "spanish",
    "es": "spanish",
    "portuguese": "portuguese",
    "pt": "portuguese",
    "french": "french_24l",
    "fr": "french_24l",
}


def reload_model_if_needed(requested_lang: str | None):
    global model, current_language, voice_cache
    if not requested_lang:
        return
    target = LANGUAGE_TO_MODEL.get(requested_lang.lower(), requested_lang)
    current = current_language or "english"
    # Normalize current to its canonical model name
    current_target = LANGUAGE_TO_MODEL.get(current.lower(), current)
    if target == current_target:
        return
    print(f"\n [MODEL] Switching language: '{current}' → '{target}'")
    model = TTSModel.load_model(device=DEVICE, language=target, quantize=QUANTIZE)
    current_language = target
    voice_cache.clear()
    print(f" [MODEL] Model reloaded for language: {target}")


def cleanup(path: str):
    if os.path.exists(path):
        os.remove(path)


def get_voice_state(speaker_name):
    clean_name = os.path.basename(str(speaker_name)).replace(".wav", "")
    if clean_name in voice_cache:
        print(f" [TIMING] Voice cache hit for '{clean_name}'")
        return voice_cache[clean_name]

    start_time = time.time()
    path = os.path.join(SPEAKER_DIR, f"{clean_name}.wav")
    if os.path.exists(path):
        print(f" [VOICE] Loading local clone: {path}")
        state = model.get_state_for_audio_prompt(path)
    else:
        print(f" [VOICE] No clone for '{clean_name}', using 'alba' default.")
        state = model.get_state_for_audio_prompt("alba")

    elapsed = time.time() - start_time
    print(f" [TIMING] Voice state generation took {elapsed:.3f}s")
    voice_cache[clean_name] = state
    return state


# --- ENDPOINT: UPLOAD_SAMPLE (Fixes 422/400 Errors) ---
@app.post("/upload_sample")
async def upload_sample(request: Request):
    print("\n>>> [SYNC] Received Voice Upload Request")
    form = await request.form()
    uploaded_file = None
    speaker_name = "unknown"
    for key in form.keys():
        value = form[key]
        # Detect file (Handle CamelCase 'wavFile')
        if hasattr(value, "filename"):
            uploaded_file = value
            speaker_name = os.path.basename(value.filename).replace(".wav", "")
        # Detect name
        elif key in ["speaker_name", "speaker_id", "name"]:
            speaker_name = str(value).replace(".wav", "")
    if not uploaded_file:
        print(" [ERROR] No file object detected.")
        return JSONResponse(status_code=400, content={"error": "No file detected"})
    try:
        speaker_name = normalize_voice_id(speaker_name)
    except ValueError as exc:
        return JSONResponse(status_code=400, content={"error": str(exc)})
    save_path = voice_path(SPEAKER_DIR, speaker_name)
    replaced = save_path.exists()
    temp_path = save_path.parent / f".upload-{uuid.uuid4().hex}.wav"
    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(uploaded_file.file, buffer)
        if temp_path.stat().st_size == 0:
            return JSONResponse(status_code=400, content={"error": "Uploaded WAV is empty"})
        os.replace(temp_path, save_path)
    finally:
        if temp_path.exists():
            temp_path.unlink()
    voice_cache.pop(speaker_name, None)
    print(f" [SUCCESS] Synced voice clone for: {speaker_name}")
    return {"status": "success", "speaker": speaker_name, "replaced": replaced}


# --- ENDPOINT: SPEAKERS_LIST ---
@app.get("/speakers_list")
async def speakers_list():
    files = [f.replace(".wav", "") for f in os.listdir(SPEAKER_DIR) if f.endswith(".wav")]
    return files if files else ["alba", "marius", "javert"]


@app.get("/speakers_list_extended")
async def speakers_list_extended():
    files = sorted(f[:-4] for f in os.listdir(SPEAKER_DIR) if f.endswith(".wav"))
    if files:
        items = [
            {"voice_id": voice_id, "can_delete": True, "source": "uploaded_sample"}
            for voice_id in files
        ]
    else:
        items = [
            {"voice_id": voice_id, "can_delete": False, "source": "builtin"}
            for voice_id in ("alba", "marius", "javert")
        ]
    return {"speakers": items, "count": len(items)}


@app.delete("/voices/{voice_id}")
async def delete_voice(voice_id: str):
    try:
        normalized = normalize_voice_id(voice_id)
        removed = delete_voice_file(SPEAKER_DIR, normalized)
    except ValueError as exc:
        return JSONResponse(status_code=400, content={"error": str(exc)})
    if removed is None:
        return JSONResponse(
            status_code=404, content={"error": f"Uploaded voice '{normalized}' was not found"}
        )
    voice_cache.pop(normalized, None)
    return {
        "status": "deleted",
        "voice_id": normalized,
        "removed": [removed.name],
        "cache_invalidated": True,
    }


# --- ENDPOINT: SETTINGS (Satisfies PHP Initialization) ---
@app.post("/set_tts_settings")
async def set_tts_settings(request: Request):
    return {"status": "success"}


class TTSRequest(BaseModel):
    text: str
    speaker_wav: Optional[str] = "alba"
    language: Optional[str] = None


# --- ENDPOINT: TTS_TO_AUDIO (Agnostic JSON/Form) ---
async def _do_tts(
    text: str, speaker: str, background_tasks: BackgroundTasks, language: str | None = None
):
    if not text:
        return {"error": "no text"}
    reload_model_if_needed(language)
    request_start = time.time()
    print(f"\n>>> [TTS] Generating: [{speaker}] {text[:45]}...")

    state = get_voice_state(speaker)

    audio_start = time.time()
    audio = model.generate_audio(state, text)
    audio_elapsed = time.time() - audio_start
    print(f" [TIMING] Audio generation took {audio_elapsed:.3f}s")

    write_start = time.time()
    tmp_path = f"gen_{uuid.uuid4()}.wav"
    scipy.io.wavfile.write(tmp_path, model.sample_rate, audio.cpu().numpy())
    write_elapsed = time.time() - write_start
    print(f" [TIMING] Audio write took {write_elapsed:.3f}s")

    total_elapsed = time.time() - request_start
    print(f" [TIMING] TOTAL request time: {total_elapsed:.3f}s")

    background_tasks.add_task(cleanup, tmp_path)
    return FileResponse(tmp_path, media_type="audio/wav")


@app.post("/tts_to_audio", summary="TTS to Audio (JSON)")
@app.post("/tts_to_audio/", include_in_schema=False)
async def tts_to_audio_json(body: TTSRequest, background_tasks: BackgroundTasks):
    return await _do_tts(
        body.text, body.speaker_wav or "alba", background_tasks, language=body.language
    )


@app.post("/tts_to_audio_form", summary="TTS to Audio (Form)")
async def tts_to_audio_form(
    background_tasks: BackgroundTasks,
    text: str = Form(...),
    speaker_wav: str = Form("alba"),
    language: Optional[str] = Form(None),
):
    return await _do_tts(text, speaker_wav, background_tasks, language=language)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)
