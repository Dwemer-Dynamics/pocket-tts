import os
import torch
import scipy.io.wavfile
import uuid
import shutil
import json
import time
from fastapi import FastAPI, Request, BackgroundTasks
from fastapi.responses import FileResponse, JSONResponse
from pocket_tts import TTSModel
app = FastAPI()
# Configuration
PORT = 8020
SPEAKER_DIR = "./speakers"
os.makedirs(SPEAKER_DIR, exist_ok=True)
print("\n" + "="*60)
print(" POCKET TTS BRIDGE")
print(" Original code by Gestel. (thank you very much)")
print("="*60 + "\n")

# Initialize Model
model = TTSModel.load_model()
voice_cache = {}

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
	save_path = os.path.join(SPEAKER_DIR, f"{speaker_name}.wav")
	with open(save_path, "wb") as buffer:
		shutil.copyfileobj(uploaded_file.file, buffer)
	if speaker_name in voice_cache: del voice_cache[speaker_name]
	print(f" [SUCCESS] Synced voice clone for: {speaker_name}")
	return {"status": "success", "speaker": speaker_name}
	
# --- ENDPOINT: SPEAKERS_LIST ---
@app.get("/speakers_list")
async def speakers_list():
	files = [f.replace(".wav", "") for f in os.listdir(SPEAKER_DIR) if f.endswith(".wav")]
	return files if files else ["alba", "marius", "javert"]
	
# --- ENDPOINT: SETTINGS (Satisfies PHP Initialization) ---
@app.post("/set_tts_settings")
async def set_tts_settings(request: Request):
	return {"status": "success"}	
	
# --- ENDPOINT: TTS_TO_AUDIO (Agnostic JSON/Form) ---
@app.post("/tts_to_audio")
@app.post("/tts_to_audio/")
async def tts_to_audio(request: Request, background_tasks: BackgroundTasks):
	request_start = time.time()
	ctype = request.headers.get("Content-Type", "")
	if "application/json" in ctype:
		data = await request.json()
		text = data.get("text", "")
		speaker = data.get("speaker_wav", "alba")
	else:
		data = await request.form()
		text = data.get("text", "")
		speaker = data.get("speaker_wav", "alba")
		
	if not text: return {"error": "no text"}
	print(f"\n>>> [TTS] Generating: [{speaker}] {text[:45]}...")
	
	state_start = time.time()
	state = get_voice_state(speaker)
	state_elapsed = time.time() - state_start
	
	audio_start = time.time()
	audio = model.generate_audio(state, text)
	audio_elapsed = time.time() - audio_start
	print(f" [TIMING] Audio generation took {audio_elapsed:.3f}s")
	
	write_start = time.time()
	tmp_path = f"gen_{uuid.uuid4()}.wav"
	scipy.io.wavfile.write(tmp_path, model.sample_rate, audio.numpy())
	write_elapsed = time.time() - write_start
	print(f" [TIMING] Audio write took {write_elapsed:.3f}s")
	
	total_elapsed = time.time() - request_start
	print(f" [TIMING] TOTAL request time: {total_elapsed:.3f}s")
	
	background_tasks.add_task(cleanup, tmp_path)
	return FileResponse(tmp_path, media_type="audio/wav")

if __name__ == "__main__":
	import uvicorn
	uvicorn.run(app, host="0.0.0.0", port=PORT)
	
