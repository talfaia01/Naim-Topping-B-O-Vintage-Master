## Naim Uniti Core Metadata Liberator (`naim_tagger.py`)

Naim's proprietary ripping engine stores metadata and artwork in sidecar JSON files (`meta.naim`) rather than embedding them in the audio files. This script parses those Naim-specific files, extracts your custom metadata and artwork, and permanently embeds them into the `.wav` files as standard ID3 tags inside a RIFF chunk. It also renames the physical files for clean network browsing.

### Prerequisites
This script requires the Mutagen library to handle the WAVE RIFF envelopes.
`pip install mutagen`

### Usage
Point the script at the root directory of your Naim Core rips (e.g., the `Music/MQ` folder on the network share). It will recursively walk through all subfolders, processing any directory that contains a `meta.naim` file.

**Standard Execution:**
```bash
python naim_tagger.py "/Volumes/Music/MQ"
```
**Dry Run Mode (Recommended for Testing):**
To simulate the tagging and renaming process without altering any files on disk, append the `--dry-run` flag:
```bash
python naim_tagger.py "/Volumes/Music/MQ" --dry-run
```

### Output & Logging
* **Audio Files:** WAV files are updated in-place with ID3 metadata and renamed to match the track title (e.g., `01 - Song Name.wav`).
* **Activity Log:** A file named `tagger_activity.log` is generated in the directory where the script is executed, providing a complete audit trail of all modified files, renames, and any malformed JSON errors skipped during processing.
##
