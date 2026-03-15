import os
import re
import json
import base64
import argparse
import logging
from mutagen.wave import WAVE
from mutagen.id3 import TIT2, TPE1, TPE2, TALB, TRCK, APIC

def sanitize_filename(filename):
    """Removes illegal characters so strings can be used safely as folder or file names."""
    cleaned = re.sub(r'[\\/*?:"<>|]', "", filename)
    return cleaned.strip()

def process_naim_directory(directory, root_dir, dry_run=False):
    meta_file = os.path.join(directory, 'meta.naim')
    
    if not os.path.exists(meta_file):
        return

    msg = f"\nProcessing Naim directory: {os.path.basename(directory)}"
    print(msg)
    logging.info(msg)
    
    with open(meta_file, 'r', encoding='utf-8') as f:
        try:
            naim_data = json.load(f)
        except json.JSONDecodeError as e:
            err_msg = f"Malformed JSON in {directory} | Error: {e}"
            logging.error(err_msg)
            print(f"  -> [ERROR] Failed to read JSON.")
            return

    # --- 1. Handle Artwork ---
    image_bytes = None
    b64_image_data = naim_data.get('image') or naim_data.get('artwork')
    
    if b64_image_data:
        if "," in b64_image_data:
            b64_image_data = b64_image_data.split(",")[1]
        try:
            image_bytes = base64.b64decode(b64_image_data)
        except Exception as e:
            logging.error(f"Artwork decode failure: {e}")
    else:
        possible_covers = ['userartwork.jpg', 'folder.jpg', 'cover.jpg']
        for cover_name in possible_covers:
            cover_path = os.path.join(directory, cover_name)
            if os.path.exists(cover_path):
                with open(cover_path, 'rb') as img_file:
                    image_bytes = img_file.read()
                break

    # --- 2. Extract Metadata ---
    user_data = naim_data.get('user', {})
    meta_default = naim_data.get('meta', {}).get('default', {})
    release_data = meta_default.get('release', {})

    album_title = user_data.get('title') or release_data.get('title', 'Unknown Album')
    album_artist = user_data.get('artist') or release_data.get('artistname', 'Unknown Artist')
    user_tracks_dict = user_data.get('tracks', {})

    # --- 3. Create the New Folder Hierarchy ---
    safe_artist = sanitize_filename(album_artist)
    safe_album = sanitize_filename(album_title)
    
    new_album_dir = os.path.join(root_dir, safe_artist, safe_album)
    
    if not dry_run:
        os.makedirs(new_album_dir, exist_ok=True)
        if image_bytes:
            cover_out_path = os.path.join(new_album_dir, 'folder.jpg')
            if not os.path.exists(cover_out_path):
                with open(cover_out_path, 'wb') as img_out:
                    img_out.write(image_bytes)

    # --- 4. Scan and Map Physical Files ---
    wav_files = sorted([f for f in os.listdir(directory) if f.lower().endswith('.wav')])

    if not wav_files:
        logging.info(f"No WAV files found in {directory}. Skipping.")
        return

    for index, filename in enumerate(wav_files):
        track_number = str(index + 1)
        filepath = os.path.join(directory, filename)
        track_title = user_tracks_dict.get(track_number, f"Track {track_number}")

        safe_title = sanitize_filename(track_title)
        padded_track = track_number.zfill(2)
        new_filename = f"{padded_track} - {safe_title}.wav"
        new_filepath = os.path.join(new_album_dir, new_filename)

        if dry_run:
            msg = f"  -> [DRY RUN] Would tag: {filename} | Title: '{track_title}'"
            print(msg)
            logging.info(msg)
            
            rename_msg = f"  -> [DRY RUN] Would move to: {safe_artist}/{safe_album}/{new_filename}"
            print(rename_msg)
            logging.info(rename_msg)
            continue

        # --- 5. Apply the ID3 Tags ---
        try:
            audio = WAVE(filepath)
            
            if audio.tags is None:
                audio.add_tags()

            audio.tags.add(TIT2(encoding=3, text=track_title))
            audio.tags.add(TPE1(encoding=3, text=album_artist))
            audio.tags.add(TPE2(encoding=3, text=album_artist))
            audio.tags.add(TALB(encoding=3, text=album_title))
            audio.tags.add(TRCK(encoding=3, text=track_number))
            
            if image_bytes:
                audio.tags.add(
                    APIC(
                        encoding=3,
                        mime='image/jpeg',
                        type=3,
                        desc='Front Cover',
                        data=image_bytes
                    )
                )

            audio.save()
            tag_msg = f"  -> Tagged: '{track_title}'"
            print(tag_msg)
            logging.info(tag_msg)
            
            # --- 6. Move and Rename the physical file ---
            os.rename(filepath, new_filepath)
            rename_msg = f"  -> Moved to: {safe_artist}/{safe_album}/{new_filename}"
            print(rename_msg)
            logging.info(rename_msg)
            
        except Exception as e:
            err_msg = f"Failed to tag or move {filename} | Error: {e}"
            logging.error(err_msg)
            print(f"  -> [ERROR] {err_msg}")

    # --- 7. Move Naim Sidecar Files ---
    sidecar_files = ['meta.naim', 'rip.naim']
    for sidecar in sidecar_files:
        sidecar_path = os.path.join(directory, sidecar)
        if os.path.exists(sidecar_path):
            new_sidecar_path = os.path.join(new_album_dir, sidecar)
            
            if dry_run:
                msg = f"  -> [DRY RUN] Would move sidecar: {sidecar} to {safe_artist}/{safe_album}/"
                print(msg)
                logging.info(msg)
                continue
                
            try:
                # Only move if the source and destination are actually different 
                # (prevents errors if running the script on an already-organized folder)
                if sidecar_path != new_sidecar_path:
                    os.rename(sidecar_path, new_sidecar_path)
                    msg = f"  -> Moved sidecar: {sidecar}"
                    print(msg)
                    logging.info(msg)
            except Exception as e:
                err_msg = f"Failed to move sidecar {sidecar} | Error: {e}"
                logging.error(err_msg)
                print(f"  -> [ERROR] {err_msg}")

def main():
    parser = argparse.ArgumentParser(description="Tag Naim WAVs, reorganize folders, and preserve sidecar files.")
    parser.add_argument("target_directory", help="The root directory to scan and output files to.")
    parser.add_argument("--dry-run", action="store_true", help="Dry run mode.")
    args = parser.parse_args()

    root_dir = os.path.abspath(args.target_directory)

    if not os.path.isdir(root_dir):
        print(f"Error: Directory not found.")
        return

    log_filename = 'tagger_activity.log'
    logging.basicConfig(
        filename=log_filename,
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

    start_msg = f"Scanning target directory: {root_dir} {'(DRY RUN)' if args.dry_run else ''}"
    print(start_msg)
    logging.info("========================================")
    logging.info(start_msg)

    for root, dirs, files in os.walk(root_dir):
        if 'meta.naim' in files:
            process_naim_directory(root, root_dir, dry_run=args.dry_run)
            
    end_msg = "Processing complete."
    print(f"\n{end_msg}")
    logging.info(end_msg)
    print(f"Activity log saved to: {os.path.join(os.getcwd(), log_filename)}")

if __name__ == "__main__":
    main()
