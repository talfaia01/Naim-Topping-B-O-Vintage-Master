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
    cleaned = re.sub(r'[\\/*?:"<>|]', "", str(filename))
    return cleaned.strip()

def is_valid_meta(val):
    """Helper to ensure we don't accidentally accept Naim's generic fallback strings."""
    if not val:
        return False
    val_str = str(val).strip()
    if not val_str or val_str.lower() == "unknown" or val_str.startswith("Album_"):
        return False
    return True

def safe_move(src, dst):
    """Safely moves a file, appending a number if the destination already exists to prevent overwriting."""
    if not os.path.exists(dst):
        os.rename(src, dst)
        return dst
    
    base, ext = os.path.splitext(dst)
    counter = 1
    new_dst = f"{base} ({counter}){ext}"
    while os.path.exists(new_dst):
        counter += 1
        new_dst = f"{base} ({counter}){ext}"
    
    os.rename(src, new_dst)
    return new_dst

def get_image_format(image_bytes):
    """Reads the magic numbers of the byte string to determine if it's a PNG or JPEG."""
    if image_bytes.startswith(b'\x89PNG\r\n\x1a\n'):
        return 'image/png', 'folder.png'
    # Fallback to JPEG for standard formats
    return 'image/jpeg', 'folder.jpg'

def extract_artist(data_block):
    """Extracts artist name gracefully, whether it's a string or a nested list."""
    if not isinstance(data_block, dict):
        return None
        
    for key in ['artistname', 'artist_name', 'albumartist']:
        val = data_block.get(key)
        if isinstance(val, str) and is_valid_meta(val):
            return val
            
    artist_data = data_block.get('artist')
    if isinstance(artist_data, str) and is_valid_meta(artist_data):
        return artist_data
    elif isinstance(artist_data, list):
        for item in artist_data:
            if isinstance(item, dict):
                name = item.get('name')
                if is_valid_meta(name):
                    return name
    return None

def extract_tracks(provider_data):
    """Dynamically extracts track lists whether Naim stored them as a Dictionary or a List."""
    extracted = {}
    tracks_data = provider_data.get('tracks')
    
    if isinstance(tracks_data, dict):
        extracted = {str(k): v for k, v in tracks_data.items() if is_valid_meta(v) and not str(v).lower().startswith("track ")}
    elif isinstance(tracks_data, list):
        for trk in tracks_data:
            if isinstance(trk, dict):
                t_id = str(trk.get('index', trk.get('id', '')))
                t_title = trk.get('title', '')
                if t_id and is_valid_meta(t_title) and not t_title.lower().startswith("track "):
                    extracted[t_id] = t_title
    return extracted

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
        # Now searches for both JPG and PNG formats
        possible_covers = [
            'userartwork.jpg', 'userartwork.png', 
            'folder.jpg', 'folder.png', 
            'cover.jpg', 'cover.png'
        ]
        for cover_name in possible_covers:
            cover_path = os.path.join(directory, cover_name)
            if os.path.exists(cover_path):
                with open(cover_path, 'rb') as img_file:
                    image_bytes = img_file.read()
                break

    # Determine exact image MIME type and target filename
    img_mime_type = 'image/jpeg'
    img_filename = 'folder.jpg'
    if image_bytes:
        img_mime_type, img_filename = get_image_format(image_bytes)

    # --- 2. Cascading Metadata Extraction ---
    album_title = None
    album_artist = None
    tracks_dict = {}

    # Priority 1: Manual User Edits
    user_data = naim_data.get('user')
    if isinstance(user_data, dict):
        album_title = user_data.get('title')
        album_artist = extract_artist(user_data) or user_data.get('artist')
        tracks_dict = extract_tracks(user_data)

    # Priority 2: ALL Internet Databases
    meta_block = naim_data.get('meta')
    if isinstance(meta_block, dict):
        providers = [k for k in meta_block.keys() if k != 'default'] + ['default']
        
        for provider in providers:
            provider_data = meta_block.get(provider)
            if not isinstance(provider_data, dict):
                continue
            
            release_data = provider_data.get('release', {})
            
            if not is_valid_meta(album_title):
                if isinstance(release_data, dict):
                    album_title = release_data.get('title')
                if not is_valid_meta(album_title):
                    album_title = provider_data.get('title')
                    
            if not is_valid_meta(album_artist):
                album_artist = extract_artist(release_data) or extract_artist(provider_data)
            
            if not tracks_dict:
                tracks_dict = extract_tracks(provider_data)

    # Priority 3: Safe Fallbacks (ISOLATE FOLDERS)
    if not is_valid_meta(album_title):
        album_title = os.path.basename(directory)
    if not is_valid_meta(album_artist):
        album_artist = "Unknown Artist"

    # --- 3. Create the New Folder Hierarchy ---
    safe_artist = sanitize_filename(album_artist)
    safe_album = sanitize_filename(album_title)
    
    new_album_dir = os.path.join(root_dir, safe_artist, safe_album)
    
    if not dry_run:
        os.makedirs(new_album_dir, exist_ok=True)
        if image_bytes:
            # Drops either folder.jpg or folder.png based on detection
            cover_out_path = os.path.join(new_album_dir, img_filename)
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
        
        track_title = tracks_dict.get(track_number)
        if not is_valid_meta(track_title):
            track_title = f"Track {track_number}"

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
                        mime=img_mime_type, # Dynamically sets image/png or image/jpeg
                        type=3,
                        desc='Front Cover',
                        data=image_bytes
                    )
                )

            audio.save()
            tag_msg = f"  -> Tagged: '{track_title}'"
            print(tag_msg)
            logging.info(tag_msg)
            
            # --- 6. Safe Move and Rename ---
            final_dest = safe_move(filepath, new_filepath)
            final_relative = os.path.relpath(final_dest, root_dir)
            rename_msg = f"  -> Moved to: {final_relative}"
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
                if sidecar_path != new_sidecar_path:
                    safe_move(sidecar_path, new_sidecar_path)
                    msg = f"  -> Moved sidecar: {sidecar}"
                    print(msg)
                    logging.info(msg)
            except Exception as e:
                err_msg = f"Failed to move sidecar {sidecar} | Error: {e}"
                logging.error(err_msg)
                print(f"  -> [ERROR] {err_msg}")

def main():
    parser = argparse.ArgumentParser(description="Tag Naim WAVs, safely reorganize folders, and preserve sidecar files.")
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
