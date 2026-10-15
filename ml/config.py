"""Shared settings for the Sound Ring ML pipeline."""
from pathlib import Path

ML_DIR = Path(__file__).resolve().parent
DATA_DIR = ML_DIR / "data"
MODELS_DIR = ML_DIR / "models"
WORK_DIR = ML_DIR / "work"

ESC50_DIR = DATA_DIR / "ESC-50"
FSDD_DIR = DATA_DIR / "FSDD" / "recordings"
DEMAND_DIR = DATA_DIR / "DEMAND"        # optional, see download_datasets.sh
MUSAN_DIR = DATA_DIR / "musan"          # optional, see download_datasets.sh
MY_CLIPS_DIR = DATA_DIR / "my_clips"    # optional: my_clips/<label>/*.wav recorded by the team

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

# Short, sharp sounds. For these we also train on single isolated hits (one clap,
# one knock) pasted onto background, so a lone clap is recognised, not just applause.
TRANSIENT_LABELS = {"clap", "knock"}

# How important each sound is when several are detected at once (used by the Pi + demo).
# score = priority * confidence * loudness_factor ; highest score wins the ring.
CLASS_PRIORITY = {
    "siren": 10, "alarm": 10, "glass_break": 8, "car_horn": 9, "baby_cry": 7,
    "knock": 5, "clap": 4, "dog": 3, "cat": 2, "appliance": 2, "speech": 2, "footsteps": 1,
}
# Per-class detection threshold (sigmoid output). Safety sounds fire easier.
CLASS_THRESHOLD = {
    "siren": 0.4, "alarm": 0.4, "glass_break": 0.45, "car_horn": 0.45, "baby_cry": 0.5,
    "knock": 0.55, "clap": 0.55, "dog": 0.55, "cat": 0.6, "appliance": 0.6,
    "speech": 0.6, "footsteps": 0.65,
}
DEFAULT_THRESHOLD = 0.6

# ESC-50 fold used as the held-out test set (folds are 1..5)
TEST_FOLD = 5
# FSDD speakers held out for test
TEST_SPEAKERS = {"theo"}
# cap speech clips per FSDD speaker (6 speakers)
SPEECH_PER_SPEAKER = 120
# cap "other" so it doesn't swamp the real classes (per fold)
OTHER_PER_FOLD = 120
# cap background chunks taken from DEMAND / MUSAN (per source folder)
BACKGROUND_CHUNKS_PER_FOLDER = 40
BACKGROUND_CHUNK_SECONDS = 5.0

# ---- augmentation (train split only) ----
AUG_COPIES = 2            # extra noisy copies of each target clip
AUG_SNR_DB = (0, 20)      # signal-to-noise range for mixing
AUG_GAIN_DB = (-6, 6)     # random level change
TRANSIENT_COPIES = 4      # extra "single hit on background" samples per transient clip
OVERLAP_COPIES = 1        # extra samples mixing two different target sounds (both labels on)
OVERLAP_RATIO_DB = (-12, 6)  # level of the second sound relative to the first
