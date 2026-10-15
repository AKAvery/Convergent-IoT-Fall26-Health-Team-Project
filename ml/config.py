"""Shared settings for the Sound Ring ML pipeline."""
from pathlib import Path

ML_DIR = Path(__file__).resolve().parent
DATA_DIR = ML_DIR / "data"
MODELS_DIR = ML_DIR / "models"
WORK_DIR = ML_DIR / "work"

ESC50_DIR = DATA_DIR / "ESC-50"
FSDD_DIR = DATA_DIR / "FSDD" / "recordings"
MY_CLIPS_DIR = DATA_DIR / "my_clips"   # optional: my_clips/<label>/*.wav recorded by the team

YAMNET_EMBED_TFLITE = MODELS_DIR / "yamnet_embedding_metadata.tflite"

SAMPLE_RATE = 16000
WINDOW = 15600          # 0.975 s, what YAMNet expects
HOP = 7800              # 50% overlap when slicing clips into windows

# ESC-50 category -> our label. Everything not listed becomes "other".
TARGETS = {
    "dog":              "dog",
    "cat":              "cat",
    "crying_baby":      "baby_cry",
    "door_wood_knock":  "knock",
    "glass_breaking":   "glass_break",
    "siren":            "siren",
    "car_horn":         "car_horn",
    "clapping":         "clap",
    "footsteps":        "footsteps",
    "clock_alarm":      "alarm",
    "vacuum_cleaner":   "appliance",
    "washing_machine":  "appliance",
}
SPEECH_LABEL = "speech"
OTHER_LABEL = "other"

# ESC-50 fold used as the held-out test set (folds are 1..5)
TEST_FOLD = 5
# FSDD speakers held out for test
TEST_SPEAKERS = {"theo"}

# cap speech clips per FSDD speaker (6 speakers)
SPEECH_PER_SPEAKER = 120

# cap "other" so it doesn't swamp the real classes (per fold)
OTHER_PER_FOLD = 120
